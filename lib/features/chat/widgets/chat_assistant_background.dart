import 'dart:io' show File;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../utils/sandbox_path_resolver.dart';
import 'chat_background_resolver.dart';
import 'chat_gradient_background.dart';
import 'frosted/chat_frosted_backdrop.dart';

/// Shared assistant wallpaper + surface-mask for chat surfaces.
///
/// Two mask styles, selected by [SettingsProvider.chatBackgroundMaskMode]:
///  * linear: mobile 0.20→0.50, desktop/tablet 0.08→0.36 top-to-bottom;
///  * radial: a vignette whose inner/outer radius, center and strength come
///    from the radial mask settings.
/// Every tint scales with [SettingsProvider.chatBackgroundMaskStrength]; at
/// zero no gradient widget is built at all, so the wallpaper is truly untouched.
class ChatAssistantBackground extends StatelessWidget {
  const ChatAssistantBackground({
    super.key,
    this.desktop = false,
    this.pinnedToBackdrop = false,
    this.includeSurfaceFill = false,
    this.expand = true,
  });

  /// Desktop chat uses a lighter mask so the wallpaper stays more visible.
  final bool desktop;

  /// Overlay copies use the full backdrop's size and composited origin.
  final bool pinnedToBackdrop;

  /// Desktop layout paints [ColorScheme.surface] under the wallpaper.
  final bool includeSurfaceFill;

  /// When false, an empty background is [SizedBox.shrink] (home mobile body).
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final assistant = context.watch<AssistantProvider>().currentAssistant;
    if (assistant?.useGradientBackground ?? false) {
      return ChatGradientBackground(pinned: pinnedToBackdrop);
    }
    final wallpaper = _buildWallpaper(
      context,
      resolveChatBackgroundPath(context),
    );
    if (!pinnedToBackdrop) return wallpaper;

    final scope = ChatFrostedBackdropScope.maybeOf(context)!;
    return IgnorePointer(
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: scope.size.width,
          maxWidth: scope.size.width,
          minHeight: scope.size.height,
          maxHeight: scope.size.height,
          child: CompositedTransformFollower(
            link: scope.controller.link,
            showWhenUnlinked: false,
            child: RepaintBoundary(child: wallpaper),
          ),
        ),
      ),
    );
  }

  /// A radial vignette matching the standalone editor: transparent in the
  /// inner radius, black × strength at the outer radius, multiplied onto the
  /// wallpaper. `feather`/`size` are fractions of the box's corner radius;
  /// `centerX`/`centerY` are 0..1 fractions of width/height.
  Widget _radialMask({
    required BuildContext context,
    required double strength,
    required double feather,
    required double size,
    required double centerX,
    required double centerY,
  }) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          if (!w.isFinite || !h.isFinite || w <= 0 || h <= 0) {
            return const SizedBox.shrink();
          }
          final cornerRadius = math.sqrt(w * w + h * h) / 2.0;
          final innerPx = feather * cornerRadius;
          var outerPx = size * cornerRadius;
          if (outerPx <= innerPx + 0.01) outerPx = innerPx + 0.01;
          // RadialGradient.radius is in units of half the shortest side.
          final halfShort = math.min(w, h) / 2.0;
          final outerFraction = (outerPx / halfShort).clamp(0.01, 100.0);
          final innerStop = (innerPx / outerPx).clamp(0.0, 1.0);
          final alpha = strength.clamp(0.0, 1.0);
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(
                  (centerX - 0.5) * 2,
                  (centerY - 0.5) * 2,
                ),
                radius: outerFraction,
                colors: [
                  const Color(0x00000000),
                  Color.fromRGBO(0, 0, 0, alpha),
                ],
                stops: [innerStop, 1.0],
                tileMode: TileMode.clamp,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildWallpaper(BuildContext context, String? bg) {
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    final maskStrength = settings.chatBackgroundMaskStrength;
    final maskOff = maskStrength <= 0;
    final radial = settings.chatBackgroundMaskMode == ChatBackgroundMaskMode.radial;
    final empty = expand ? const SizedBox.expand() : const SizedBox.shrink();

    if (bg == null || bg.trim().isEmpty) {
      return includeSurfaceFill ? ColoredBox(color: cs.surface) : empty;
    }

    ImageProvider? provider;
    Widget? imageWidget;
    if (bg.startsWith('http')) {
      if (includeSurfaceFill) {
        imageWidget = Image.network(
          bg,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        );
      } else {
        provider = NetworkImage(bg);
      }
    } else {
      try {
        final localPath = SandboxPathResolver.fix(bg);
        final file = File(localPath);
        if (!file.existsSync()) {
          return includeSurfaceFill ? ColoredBox(color: cs.surface) : empty;
        }
        if (includeSurfaceFill) {
          imageWidget = Image(image: FileImage(file), fit: BoxFit.cover);
        } else {
          provider = FileImage(file);
        }
      } catch (_) {
        return includeSurfaceFill ? ColoredBox(color: cs.surface) : empty;
      }
    }

    // Strength <= 0 means the mask is genuinely off: no gradient widget is
    // created at all, so the wallpaper renders unmodified.
    final Widget mask;
    if (maskOff) {
      mask = const SizedBox.shrink();
    } else if (radial) {
      mask = _radialMask(
        context: context,
        strength: maskStrength,
        feather: settings.radialMaskFeather,
        size: settings.radialMaskSize,
        centerX: settings.radialMaskCenterX,
        centerY: settings.radialMaskCenterY,
      );
    } else {
      final topAlpha = ((desktop ? 0.08 : 0.20) * maskStrength).clamp(
        0.0,
        1.0,
      );
      final bottomAlpha = ((desktop ? 0.36 : 0.50) * maskStrength).clamp(
        0.0,
        1.0,
      );
      mask = IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                cs.surface.withValues(alpha: topAlpha),
                cs.surface.withValues(alpha: bottomAlpha),
              ],
            ),
          ),
        ),
      );
    }

    if (includeSurfaceFill) {
      return IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: cs.surface),
            if (imageWidget != null)
              Opacity(
                opacity: (1.0 - 0.1 * maskStrength).clamp(0.0, 1.0),
                child: imageWidget,
              ),
            mask,
          ],
        ),
      );
    }

    final wallpaper = DecoratedBox(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: provider!,
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            cs.shadow.withValues(alpha: (0.04 * maskStrength).clamp(0.0, 1.0)),
            BlendMode.srcATop,
          ),
        ),
      ),
    );

    if (expand) {
      return Stack(fit: StackFit.expand, children: [wallpaper, mask]);
    }

    return Stack(
      children: [
        Positioned.fill(child: wallpaper),
        Positioned.fill(child: mask),
      ],
    );
  }
}
