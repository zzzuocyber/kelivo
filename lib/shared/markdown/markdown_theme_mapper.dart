import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:markstream/markstream.dart';
import 'package:Kelivo/features/chat/widgets/frosted/chat_frosted_backdrop.dart';
import 'package:Kelivo/shared/widgets/export_capture_scope.dart';
import 'markdown_surface_scope.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/theme/app_font_weights.dart';
import 'package:Kelivo/theme/custom_theme.dart' show buildCustomThemePalette;
import 'package:Kelivo/theme/palettes.dart' show ThemePalettes;
import 'package:Kelivo/theme/surface_ladder.dart' show atTone, surfaceTone;
import 'package:Kelivo/theme/theme_factory.dart'
    show buildLightThemeForScheme, getPlatformFontFallback;

/// 夜间模式下的「白底卡片」补丁
/// ---------------------------------------------------------------------------
/// 目标：夜间模式下，行内代码、代码块、表格、折叠块这四类元素改用时用的
/// 浅色配色（白底深字），其余内容（正文、标题、引用、列表、分割线、
/// 任务框、链接、代码高亮以外的语法色）保持夜间不变。
///
/// 做法：用 App 自己的浅色主题配色再算一套 Markstream 主题，只从里面挑出
/// 这四类元素的配色（外加卡片内部工具条用到的 chrome），覆盖到夜间主题上；
/// 夜间主题的正文、气泡底色等原样保留。
///
/// 要退回原样：把这份文件删掉，换回上游仓库里的同名文件即可。
MarkstreamTheme mapMarkdownTheme(
  BuildContext context,
  SettingsProvider settings,
  TextStyle? baseStyle,
) {
  final scheme = Theme.of(context).colorScheme;
  final family = settings.appFontFamily;
  final body =
      (baseStyle ?? Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
          .copyWith(
            fontFamily: family == null || family.isEmpty
                ? baseStyle?.fontFamily
                : family,
            fontFamilyFallback:
                baseStyle?.fontFamilyFallback ?? getPlatformFontFallback(),
            fontSize: baseStyle?.fontSize ?? 15.5,
            height: baseStyle?.height ?? 1.55,
            letterSpacing:
                baseStyle?.letterSpacing ??
                (Localizations.localeOf(context).languageCode == 'zh'
                    ? 0
                    : .05),
            color: DefaultTextStyle.of(context).style.color ?? scheme.onSurface,
          );
  final desktop =
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows;
  final backdrop = resolveMarkdownBackdrop(context, settings);
  final exporting = ExportCaptureScope.of(context);
  final customBackground = exporting
      ? null
      : MarkdownSurfaceScope.maybeOf(context)?.customBackground;
  final maskStrength = backdrop == MarkstreamBackdrop.plain
      ? 1.0
      : settings.chatBackgroundMaskStrength;
  final codeFontFamily = (settings.codeFontFamily?.isNotEmpty ?? false)
      ? settings.codeFontFamily!
      : 'monospace';

  /// 用给定配色算一套完整的 Markdown 主题（含旧版样式开关）。
  MarkstreamTheme assemble(ColorScheme raw) {
    var resolved = raw;
    if (backdrop != MarkstreamBackdrop.plain && customBackground != null) {
      // Fixed syntax colors need a near-dark or near-light block surface, even
      // over arbitrary wallpaper. Retain the bubble's hue, but always follow
      // the app's brightness rather than inferring it from the bubble color.
      final tone = surfaceTone(customBackground);
      final isDark = resolved.brightness == Brightness.dark;
      final blockTone = isDark
          ? tone.clamp(0.0, 5.0)
          : tone.clamp(98.0, 100.0);
      resolved = resolved.copyWith(
        surface: blockTone == tone
            ? customBackground
            : atTone(customBackground, blockTone),
        onSurface: isDark ? Colors.white : Colors.black,
      );
    }
    var theme = MarkstreamTheme.fromColorScheme(
      resolved,
      backdrop: backdrop,
      maskStrength: maskStrength,
      // Fixed syntax colors need an opaque surface over arbitrary custom
      // bubbles, including diagram source tabs that use the shared palette.
      blockBackgroundColor: customBackground == null || backdrop == MarkstreamBackdrop.plain
          ? null
          : resolved.surface,
      bodyStyle: body,
      desktop: desktop,
      codeFontFamily: codeFontFamily,
      fontWeightResolver: AppFontWeights.normalize,
    );
    if (settings.useLegacyCodeBlockStyle) {
      theme = theme.copyWith(
        code: _legacyCodeBlockTheme(
          theme,
          resolved,
          customSurface: customBackground != null,
          exporting: exporting,
        ),
      );
    }
    if (settings.useLegacyInlineCodeStyle) {
      theme = _applyLegacyInlineCode(theme);
    }
    return theme;
  }

  final theme = assemble(scheme);
  if (scheme.brightness != Brightness.dark) return theme;

  // 夜间：把四类块级元素换成浅色主题里的那一份。
  final light = assemble(_lightSchemeFor(settings));
  return theme.copyWith(
    // 让代码语法高亮走浅色那套配色，否则夜间的高饱和浅色 token 落在白底上看不清。
    brightness: Brightness.light,
    // 卡片内部的工具条（代码块头、表格工具条、折叠块箭头）都要跟着卡片变深。
    chrome: light.chrome,
    inlineCode: light.inlineCode,
    keyboard: light.keyboard,
    code: light.code,
    table: light.table,
    details: light.details,
    // 折叠块展开后的正文用的是 ink2，必须跟着换深，否则白底白字。
    colors: theme.colors.copyWith(ink2: light.colors.ink2),
  );
}

/// 取 App 当前的浅色配色（和白天模式用的是同一份），按设置缓存。
ColorScheme? _lightSchemeCache;
String? _lightSchemeKey;

ColorScheme _lightSchemeFor(SettingsProvider settings) {
  final key =
      '${settings.themePaletteId}|${settings.selectedCustomThemeId}|'
      '${settings.usePureBackground}|${settings.useLayeredSurfaces}';
  final cached = _lightSchemeCache;
  if (cached != null && _lightSchemeKey == key) return cached;
  final custom = settings.selectedCustomTheme;
  final palette =
      settings.themePaletteId == ThemePalettes.customPaletteId && custom != null
      ? buildCustomThemePalette(custom)
      : ThemePalettes.byId(settings.themePaletteId);
  final scheme = buildLightThemeForScheme(
    palette.light,
    pureBackground: settings.usePureBackground,
    layeredSurfaces: settings.useLayeredSurfaces,
  ).colorScheme;
  _lightSchemeKey = key;
  _lightSchemeCache = scheme;
  return scheme;
}

MarkstreamTheme _applyLegacyInlineCode(MarkstreamTheme theme) {
  final translucent =
      theme.backdrop == MarkstreamBackdrop.wallpaper ||
      theme.backdrop == MarkstreamBackdrop.frostedBubble;
  return theme.copyWith(
    inlineCode: theme.inlineCode.copyWith(
      text: theme.inlineCode.text.copyWith(
        height: 1.4,
        color: theme.colors.ink,
      ),
      // Keep short code within the paragraph's line height while giving
      // wrapped code room between lines.
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      backgroundColor: translucent
          ? theme.colors.fillBlock
          : theme.brightness == Brightness.dark
          ? Colors.white12
          : const Color(0x66F1F3F5),
      borderColor: theme.colors.border,
    ),
  );
}

CodeBlockTheme _legacyCodeBlockTheme(
  MarkstreamTheme theme,
  ColorScheme scheme, {
  required bool customSurface,
  required bool exporting,
}) {
  final dark = theme.brightness == Brightness.dark;
  final outline = scheme.outlineVariant;
  final border = outline == Colors.black || outline == Colors.white
      ? Color.alphaBlend(
          scheme.onSurfaceVariant.withValues(alpha: dark ? .32 : .24),
          scheme.surface,
        )
      : outline;
  // Custom chat colors still need the paired block surface/ink resolved above.
  // Other surfaces retain the original theme-container colors and 80% fill.
  final fillAlpha = exporting ? 1.0 : .8;
  final backdropTint = !exporting && theme.backdrop != MarkstreamBackdrop.plain;
  return theme.code.copyWith(
    text: theme.code.text.copyWith(fontSize: 13, height: 1.5),
    margin: const EdgeInsets.symmetric(vertical: 6),
    bodyPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    titlePadding: EdgeInsets.zero,
    actionSpacing: 16,
    radius: 16,
    backgroundColor: customSurface
        ? theme.code.backgroundColor
        : scheme.surfaceContainer.withValues(alpha: fillAlpha),
    borderColor: customSurface ? theme.colors.border : border,
    chrome: theme.code.chrome.copyWith(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      // The code surface already paints the backdrop fill. Use only a light
      // tint here instead of stacking another 80% layer over the wallpaper.
      background: backdropTint
          ? theme.colors.fillHead
          : (customSurface ? scheme.surface : scheme.surfaceContainerHighest)
                .withValues(alpha: fillAlpha),
      divider: Colors.transparent,
      label: theme.code.chrome.label.copyWith(
        fontSize: 12,
        letterSpacing: theme.body.letterSpacing,
        color: backdropTint
            ? theme.colors.ink.withValues(alpha: .9)
            : customSurface
            ? theme.colors.ink2
            : scheme.onSurfaceVariant.withValues(alpha: .72),
      ),
      actionSize: 24,
      actionIconSize: 16,
      actionRadius: 4,
      actionColor: backdropTint
          ? theme.colors.ink2
          : customSurface
          ? theme.colors.ink3
          : scheme.onSurfaceVariant.withValues(alpha: .5),
    ),
  );
}

MarkstreamBackdrop resolveMarkdownBackdrop(
  BuildContext context,
  SettingsProvider settings,
) {
  if (ExportCaptureScope.of(context)) return MarkstreamBackdrop.plain;
  // ChatBackdropSpec already resolves this with stable provider selectors.
  // Reuse that boolean instead of registering another selector per stream tick.
  final scope = ChatFrostedBackdropScope.maybeOf(context);
  if (scope == null || !scope.backgroundActive) return MarkstreamBackdrop.plain;
  final surface = MarkdownSurfaceScope.maybeOf(context);
  // Custom bubbles need the readable block fill even when the outer bubble is
  // opaque: a small tint cannot shield fixed syntax colors from a midtone.
  if (surface?.customBackground != null) {
    return MarkstreamBackdrop.wallpaper;
  }
  return switch (surface?.kind) {
    MarkdownSurfaceKind.solid => MarkstreamBackdrop.solidBubble,
    MarkdownSurfaceKind.frosted => MarkstreamBackdrop.frostedBubble,
    // User/reasoning tints can be only 8% opaque and cannot shield the text
    // like a frosted bubble. Keep the wallpaper readability guard here.
    MarkdownSurfaceKind.tinted => MarkstreamBackdrop.wallpaper,
    null => MarkstreamBackdrop.wallpaper,
  };
}
