import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_sliders/sliders.dart';
import 'package:syncfusion_flutter_core/theme.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/section_card.dart';
import '../../chat/widgets/chat_assistant_background.dart';

/// Settings page for the chat background mask.
///
/// Hosts two mutually exclusive styles (linear / radial), the shared strength
/// slider plus the radial-only parameters, and a live preview that reuses the
/// assistant's current chat background. With no wallpaper the preview area is
/// simply empty (ChatAssistantBackground renders shrink/empty).
class BackgroundMaskSettingsPage extends StatelessWidget {
  const BackgroundMaskSettingsPage({super.key, this.desktop = false});

  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();
    final radial =
        settings.chatBackgroundMaskMode == ChatBackgroundMaskMode.radial;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.backgroundMaskSettingsTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // Live preview using the assistant's current chat background.
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 200,
              width: double.infinity,
              child: ChatAssistantBackground(desktop: desktop),
            ),
          ),
          const SizedBox(height: 16),

          _header(context, l10n.backgroundMaskSettingsModeTitle, first: true),
          SectionCard(
            children: [
              _ModeRow(
                label: l10n.backgroundMaskSettingsModeLinear,
                selected: !radial,
                onTap: () => context
                    .read<SettingsProvider>()
                    .setChatBackgroundMaskMode(ChatBackgroundMaskMode.linear),
              ),
              const Divider(height: 1),
              _ModeRow(
                label: l10n.backgroundMaskSettingsModeRadial,
                selected: radial,
                onTap: () => context
                    .read<SettingsProvider>()
                    .setChatBackgroundMaskMode(ChatBackgroundMaskMode.radial),
              ),
            ],
          ),
          const SizedBox(height: 16),

          _header(context, l10n.backgroundMaskSettingsParamsTitle),
          SectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                _ParamSlider(
                  label: radial
                      ? l10n.backgroundMaskSettingsVignetteStrength
                      : l10n.displaySettingsPageChatBackgroundMaskTitle,
                  value: settings.chatBackgroundMaskStrength,
                  min: 0,
                  max: 2,
                  step: 0.05,
                  onChanged: (v) => context
                      .read<SettingsProvider>()
                      .setChatBackgroundMaskStrength(v),
                ),
                if (radial) ...[
                  const Divider(height: 1),
                  _ParamSlider(
                    label: l10n.backgroundMaskSettingsFeather,
                    value: settings.radialMaskFeather,
                    min: 0,
                    max: 0.8,
                    step: 0.01,
                    onChanged: (v) => context
                        .read<SettingsProvider>()
                        .setRadialMaskFeather(v),
                  ),
                  const Divider(height: 1),
                  _ParamSlider(
                    label: l10n.backgroundMaskSettingsSize,
                    value: settings.radialMaskSize,
                    min: 0.5,
                    max: 1.5,
                    step: 0.01,
                    onChanged: (v) => context
                        .read<SettingsProvider>()
                        .setRadialMaskSize(v),
                  ),
                  const Divider(height: 1),
                  _ParamSlider(
                    label: l10n.backgroundMaskSettingsCenterX,
                    value: settings.radialMaskCenterX,
                    min: 0,
                    max: 1,
                    step: 0.01,
                    onChanged: (v) => context
                        .read<SettingsProvider>()
                        .setRadialMaskCenterX(v),
                  ),
                  const Divider(height: 1),
                  _ParamSlider(
                    label: l10n.backgroundMaskSettingsCenterY,
                    value: settings.radialMaskCenterY,
                    min: 0,
                    max: 1,
                    step: 0.01,
                    onChanged: (v) => context
                        .read<SettingsProvider>()
                        .setRadialMaskCenterY(v),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              l10n.backgroundMaskSettingsHint,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _header(BuildContext context, String text, {bool first = false}) {
  final cs = Theme.of(context).colorScheme;
  return Padding(
    padding: EdgeInsets.fromLTRB(12, first ? 6 : 18, 12, 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 13,
        color: cs.onSurface.withValues(alpha: 0.8),
      ),
    ),
  );
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      title: Text(label),
      trailing: selected
          ? Icon(Icons.check_circle, color: cs.primary, size: 22)
          : Icon(
              Icons.circle_outlined,
              color: cs.onSurface.withValues(alpha: 0.4),
              size: 22,
            ),
      onTap: onTap,
    );
  }
}

class _ParamSlider extends StatelessWidget {
  const _ParamSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fmt = (double v) =>
        '${(v * 100).round()}%';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(fontSize: 14)),
              Text(
                fmt(value),
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SfSliderTheme(
            data: SfSliderThemeData(
              activeTrackHeight: 6,
              inactiveTrackHeight: 6,
              activeTrackColor: cs.primary,
              inactiveTrackColor: cs.onSurface.withValues(
                alpha: isDark ? 0.25 : 0.20,
              ),
              thumbColor: cs.primary,
              overlayColor: cs.primary.withValues(alpha: 0.16),
            ),
            child: SfSlider(
              value: value,
              min: min,
              max: max,
              stepSize: step,
              onChanged: (dynamic v) => onChanged((v as num).toDouble()),
            ),
          ),
        ],
      ),
    );
  }
}
