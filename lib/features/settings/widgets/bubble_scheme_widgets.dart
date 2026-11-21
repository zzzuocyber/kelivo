import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../theme/app_font_weights.dart';
import '../../../theme/bubble_color_scheme.dart';
import '../../../theme/chat_bubble_style.dart';
import 'custom_theme_widgets.dart';
import '../../../shared/widgets/section_card.dart';

/// A collapsible card. Header stays visible; body can be expanded/collapsed.
class CollapsibleSectionCard extends StatefulWidget {
  const CollapsibleSectionCard({
    super.key,
    required this.title,
    this.initiallyExpanded = false,
    required this.children,
  });

  final String title;
  final bool initiallyExpanded;
  final List<Widget> children;

  @override
  State<CollapsibleSectionCard> createState() =>
      _CollapsibleSectionCardState();
}

class _CollapsibleSectionCardState extends State<CollapsibleSectionCard> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SectionCard(
      padding: EdgeInsets.zero,
      children: [
        IosCardPress(
          baseColor: Colors.transparent,
          borderRadius: BorderRadius.zero,
          pressedBlendStrength: 0,
          pressedScale: 1,
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(Lucide.SlidersHorizontal, size: 18, color: cs.onSurface),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: AppFontWeights.semibold,
                      color: cs.onSurface.withValues(alpha: 0.9),
                    ),
                  ),
                ),
                Icon(
                  _expanded ? Lucide.ChevronUp : Lucide.ChevronDown,
                  size: 18,
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...widget.children,
      ],
    );
  }
}

/// Saved bubble color schemes library, styled after the custom themes section.
class BubbleSchemeSection extends StatelessWidget {
  const BubbleSchemeSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();
    final schemes = settings.bubbleColorSchemes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          context,
          title: l10n.bubbleSchemeSectionTitle,
          actions: [
            _headerAction(
              context,
              icon: Lucide.Plus,
              tooltip: l10n.bubbleSchemeNew,
              onTap: () => showBubbleSchemeEditor(context),
            ),
            _headerAction(
              context,
              icon: Lucide.Download,
              tooltip: l10n.bubbleSchemeImport,
              onTap: () => showBubbleSchemeImportDialog(context),
            ),
            _headerAction(
              context,
              icon: Lucide.Share2,
              tooltip: l10n.bubbleSchemeExportAll,
              onTap: () => _exportAll(context, settings),
            ),
          ],
        ),
        if (schemes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Text(
              l10n.bubbleSchemeEmptyHint,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface.withValues(
                  alpha: 0.6,
                ),
              ),
            ),
          )
        else
          SectionCard(
            children: [
              for (int i = 0; i < schemes.length; i++) ...[
                _schemeRow(context, schemes[i]),
                if (i != schemes.length - 1) _divider(context),
              ],
            ],
          ),
      ],
    );
  }

  Future<void> _exportAll(BuildContext context, SettingsProvider settings) async {
    final l10n = AppLocalizations.of(context)!;
    await Clipboard.setData(
      ClipboardData(text: settings.exportBubbleColorSchemesText()),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.bubbleSchemeCopied)),
      );
    }
  }

  Widget _sectionHeader(
    BuildContext context, {
    required String title,
    required List<Widget> actions,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: AppFontWeights.semibold,
                color: cs.onSurface.withValues(alpha: 0.9),
              ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }

  Widget _headerAction(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: IosIconButton(
        icon: icon,
        color: cs.onSurface.withValues(alpha: 0.7),
        onTap: onTap,
      ),
    );
  }

  Widget _schemeRow(BuildContext context, BubbleColorScheme scheme) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.read<SettingsProvider>();
    return IosCardPress(
      baseColor: Colors.transparent,
      borderRadius: BorderRadius.zero,
      pressedBlendStrength: 0,
      pressedScale: 1,
      onTap: () => showBubbleSchemeEditor(context, initial: scheme),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            _schemeDot(scheme),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                scheme.name.isEmpty ? l10n.bubbleSchemeNameLabel : scheme.name,
                style: TextStyle(
                  fontSize: 15,
                  color: Theme.of(context).colorScheme.onSurface.withValues(
                    alpha: 0.9,
                  ),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _rowAction(
              context,
              icon: Lucide.Copy,
              tooltip: l10n.bubbleSchemeCopyAction,
              onTap: () => settings.duplicateBubbleColorScheme(scheme.id),
            ),
            _rowAction(
              context,
              icon: Lucide.Pencil,
              tooltip: l10n.bubbleSchemeEditAction,
              onTap: () => showBubbleSchemeEditor(context, initial: scheme),
            ),
            _rowAction(
              context,
              icon: Lucide.Trash2,
              tooltip: l10n.bubbleSchemeDeleteAction,
              color: Theme.of(context).colorScheme.error,
              onTap: () => _confirmDelete(context, scheme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _schemeDot(BubbleColorScheme scheme) {
    final light = scheme.assistantOverrides.backgroundArgbLight;
    final color = light == null
        ? Colors.grey.shade400
        : Color(light);
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey.shade500, width: 1),
      ),
    );
  }

  Widget _rowAction(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color? color,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: IosIconButton(
        icon: icon,
        color: color ?? cs.onSurface.withValues(alpha: 0.6),
        onTap: onTap,
      ),
    );
  }

  Widget _divider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 56),
      child: Divider(
        height: 1,
        color: Theme.of(context).colorScheme.outlineVariant.withValues(
          alpha: 0.35,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    BubbleColorScheme scheme,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.bubbleSchemeDeleteAction),
        content: Text(l10n.bubbleSchemeDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.bubbleSchemeCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.bubbleSchemeDeleteAction),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<SettingsProvider>().deleteBubbleColorScheme(scheme.id);
    }
  }
}

/// Editor for a bubble color scheme (create / rename / edit).
Future<void> showBubbleSchemeEditor(
  BuildContext context, {
  BubbleColorScheme? initial,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final settings = context.read<SettingsProvider>();
  final isNew = initial == null;
  final nameCtrl = TextEditingController(text: initial?.name ?? '');
  ChatBubbleStyleOverrides user = initial?.userOverrides ?? const ChatBubbleStyleOverrides();
  ChatBubbleStyleOverrides assistant = initial?.assistantOverrides ?? const ChatBubbleStyleOverrides();

  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(
          isNew
              ? l10n.bubbleSchemeNew
              : l10n.bubbleSchemeEditAction,
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: l10n.bubbleSchemeNameLabel,
                ),
              ),
              const SizedBox(height: 16),
              _schemeColorRow(
                ctx,
                label: l10n.bubbleSchemeUserColor,
                overrides: user,
                onChanged: (v) => setState(() => user = v),
              ),
              const SizedBox(height: 8),
              _schemeColorRow(
                ctx,
                label: l10n.bubbleSchemeAssistantColor,
                overrides: assistant,
                onChanged: (v) => setState(() => assistant = v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.bubbleSchemeCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.bubbleSchemeSave),
          ),
        ],
      ),
    ),
  );

  if (saved != true) return;
  final name = nameCtrl.text.trim();
  final scheme = BubbleColorScheme(
    id: initial?.id ?? '',
    name: name,
    userOverrides: user,
    assistantOverrides: assistant,
  );
  if (isNew) {
    await settings.addBubbleColorScheme(scheme);
  } else {
    await settings.updateBubbleColorScheme(scheme);
  }
}

Widget _schemeColorRow(
  BuildContext context, {
  required String label,
  required ChatBubbleStyleOverrides overrides,
  required ValueChanged<ChatBubbleStyleOverrides> onChanged,
}) {
  final cs = Theme.of(context).colorScheme;
  Future<void> pick(bool dark, bool background) async {
    final currentArgb = background
        ? (dark ? overrides.backgroundArgbDark : overrides.backgroundArgbLight)
        : (dark ? overrides.textArgbDark : overrides.textArgbLight);
    final initial = currentArgb == null ? cs.surface : Color(currentArgb);
    final picked = await showAppColorPicker(
      context,
      title: label,
      initial: initial,
    );
    if (picked == null) return;
    final argb = picked.toARGB32();
    if (background) {
      onChanged(
        dark
            ? overrides.copyWith(backgroundArgbDark: () => argb)
            : overrides.copyWith(backgroundArgbLight: () => argb),
      );
    } else {
      onChanged(
        dark
            ? overrides.copyWith(textArgbDark: () => argb)
            : overrides.copyWith(textArgbLight: () => argb),
      );
    }
  }

  Color swatch(int? argb) => argb == null ? cs.surface : Color(argb);

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(fontSize: 14, color: cs.onSurface.withValues(alpha: 0.85))),
      const SizedBox(height: 6),
      Row(
        children: [
          _swatchButton(context, '浅·背景', swatch(overrides.backgroundArgbLight), () => pick(false, true)),
          const SizedBox(width: 8),
          _swatchButton(context, '深·背景', swatch(overrides.backgroundArgbDark), () => pick(true, true)),
          const SizedBox(width: 8),
          _swatchButton(context, '浅·文字', swatch(overrides.textArgbLight), () => pick(false, false)),
          const SizedBox(width: 8),
          _swatchButton(context, '深·文字', swatch(overrides.textArgbDark), () => pick(true, false)),
        ],
      ),
    ],
  );
}

Widget _swatchButton(BuildContext context, String label, Color color, VoidCallback onTap) {
  return Expanded(
    child: IosCardPress(
      baseColor: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      pressedScale: 0.97,
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            height: 28,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade500, width: 1),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Import schemes from JSON text on the clipboard / manual paste.
Future<void> showBubbleSchemeImportDialog(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final settings = context.read<SettingsProvider>();
  final ctrl = TextEditingController();
  String? error;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(l10n.bubbleSchemeImport),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: l10n.bubbleSchemeImportHint,
                errorText: error,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.bubbleSchemeCancel),
          ),
          TextButton(
            onPressed: () async {
              final count = await settings.importBubbleColorSchemesText(ctrl.text);
              if (count == 0) {
                setState(() => error = l10n.bubbleSchemeImportInvalid);
                return;
              }
              if (ctx.mounted) Navigator.of(ctx).pop(true);
            },
            child: Text(l10n.bubbleSchemeImport),
          ),
        ],
      ),
    ),
  );
  if (ok == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.bubbleSchemeCopied)),
    );
  }
}

/// A dropdown used by assistant settings to pick a scheme. Value is the id;
/// null means "follow global".
class BubbleSchemePicker extends StatelessWidget {
  const BubbleSchemePicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();
    final schemes = settings.bubbleColorSchemes;
    // A non-null empty id means "not following global but no scheme chosen yet".
    final current = value;
    final resolved = current == null
        ? null
        : (current.isEmpty || schemes.any((s) => s.id == current)
            ? current
            : null);
    return DropdownButton<String?>(
      value: resolved,
      isExpanded: true,
      items: [
        DropdownMenuItem<String?>(value: null, child: Text(l10n.assistantEditBubbleSchemeNone)),
        if (value?.isEmpty == true)
          DropdownMenuItem<String?>(value: '', child: Text('—')),
        ...schemes.map(
          (s) => DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
        ),
      ],
      onChanged: onChanged,
    );
  }
}
