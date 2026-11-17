import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/assistant_regex.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../core/services/haptics.dart';
import '../../../theme/app_font_weights.dart';
import 'package:Kelivo/theme/app_semantic_colors.dart';

class AssistantRegexTab extends StatefulWidget {
  const AssistantRegexTab({super.key, required this.assistantId});
  final String assistantId;

  @override
  State<AssistantRegexTab> createState() => _AssistantRegexTabState();
}

class _AssistantRegexTabState extends State<AssistantRegexTab> {
  List<AssistantRegexScope> _normalizeScopes(
    Iterable<AssistantRegexScope> scopes,
  ) {
    final set = {...scopes};
    return AssistantRegexScope.values
        .where((e) => set.contains(e))
        .toList(growable: false);
  }

  void _reorder(int oldIndex, int newIndex) {
    final ap = context.read<AssistantProvider>();
    final assistant = ap.getById(widget.assistantId);
    if (assistant == null) return;
    ap.reorderAssistantRegex(
      assistantId: widget.assistantId,
      oldIndex: oldIndex,
      newIndex: newIndex,
    );
  }

  Future<void> _toggleRule(AssistantRegex rule, bool enabled) async {
    final ap = context.read<AssistantProvider>();
    final assistant = ap.getById(widget.assistantId);
    if (assistant == null) return;
    final list = assistant.regexRules.map((r) {
      if (r.id == rule.id) return r.copyWith(enabled: enabled);
      return r;
    }).toList();
    await ap.updateAssistant(assistant.copyWith(regexRules: list));
  }

  Future<void> _deleteRule(AssistantRegex rule) async {
    final ap = context.read<AssistantProvider>();
    final assistant = ap.getById(widget.assistantId);
    if (assistant == null) return;
    final list = List<AssistantRegex>.of(assistant.regexRules)
      ..removeWhere((r) => r.id == rule.id);
    await ap.updateAssistant(assistant.copyWith(regexRules: list));
  }

  Future<void> _addOrEdit({AssistantRegex? rule}) async {
    final ap = context.read<AssistantProvider>();
    final data = await _showRegexEditor(context, rule: rule);
    if (data == null) return;
    final assistant = ap.getById(widget.assistantId);
    if (assistant == null) return;
    final list = List<AssistantRegex>.of(assistant.regexRules);
    final updated = AssistantRegex(
      id: rule?.id ?? const Uuid().v4(),
      name: data.name,
      pattern: data.pattern,
      replacement: data.replacement,
      scopes: _normalizeScopes(data.scopes),
      visualOnly: data.visualOnly,
      replaceOnly: data.replaceOnly,
      enabled: rule?.enabled ?? true,
    );
    if (rule == null) {
      list.add(updated);
    } else {
      final idx = list.indexWhere((r) => r.id == rule.id);
      if (idx == -1) {
        list.add(updated);
      } else {
        list[idx] = updated;
      }
    }
    await ap.updateAssistant(assistant.copyWith(regexRules: list));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final assistant = context.watch<AssistantProvider>().getById(
      widget.assistantId,
    );
    if (assistant == null) return const SizedBox.shrink();
    final rules = assistant.regexRules;

    if (rules.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Lucide.Wand2,
                size: 64,
                color: cs.primary.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.assistantEditRegexDescription,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 24),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 200),
                child: IosCardPress(
                  onTap: () => _addOrEdit(),
                  borderRadius: BorderRadius.circular(12),
                  baseColor: cs.primary.withValues(alpha: isDark ? 0.18 : 0.12),
                  pressedBlendStrength: 0.18,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Lucide.Plus, size: 18, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(
                        l10n.assistantEditAddRegexButton,
                        style: TextStyle(
                          color: cs.primary,
                          fontWeight: AppFontWeights.emphasis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        ReorderableListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
          itemCount: rules.length,
          buildDefaultDragHandles: false,
          proxyDecorator: (child, index, animation) {
            return AnimatedBuilder(
              animation: animation,
              builder: (context, _) {
                final t = Curves.easeOut.transform(animation.value);
                return Transform.scale(scale: 0.98 + 0.02 * t, child: child);
              },
            );
          },
          onReorderItem: _reorder,
          itemBuilder: (context, index) {
            final rule = rules[index];
            return KeyedSubtree(
              key: ValueKey('assistant-regex-${rule.id}'),
              child: ReorderableDelayedDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _RegexRuleCard(
                    rule: rule,
                    onTap: () => _addOrEdit(rule: rule),
                    onDelete: () => _deleteRule(rule),
                    onToggle: (v) => _toggleRule(rule, v),
                    desktop: false,
                  ),
                ),
              ),
            );
          },
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 60,
          child: Center(
            child: _GlassCircleButton(
              icon: Lucide.Plus,
              color: cs.primary,
              onTap: () => _addOrEdit(),
            ),
          ),
        ),
      ],
    );
  }
}

class AssistantRegexDesktopPane extends StatefulWidget {
  const AssistantRegexDesktopPane({super.key, required this.assistantId});
  final String assistantId;

  @override
  State<AssistantRegexDesktopPane> createState() =>
      _AssistantRegexDesktopPaneState();
}

class _AssistantRegexDesktopPaneState extends State<AssistantRegexDesktopPane> {
  List<AssistantRegexScope> _normalizeScopes(
    Iterable<AssistantRegexScope> scopes,
  ) {
    final set = {...scopes};
    return AssistantRegexScope.values
        .where((e) => set.contains(e))
        .toList(growable: false);
  }

  void _reorder(int oldIndex, int newIndex) {
    final ap = context.read<AssistantProvider>();
    final assistant = ap.getById(widget.assistantId);
    if (assistant == null) return;
    ap.reorderAssistantRegex(
      assistantId: widget.assistantId,
      oldIndex: oldIndex,
      newIndex: newIndex,
    );
  }

  Future<void> _toggleRule(AssistantRegex rule, bool enabled) async {
    final ap = context.read<AssistantProvider>();
    final assistant = ap.getById(widget.assistantId);
    if (assistant == null) return;
    final list = assistant.regexRules.map((r) {
      if (r.id == rule.id) return r.copyWith(enabled: enabled);
      return r;
    }).toList();
    await ap.updateAssistant(assistant.copyWith(regexRules: list));
  }

  Future<void> _deleteRule(AssistantRegex rule) async {
    final ap = context.read<AssistantProvider>();
    final assistant = ap.getById(widget.assistantId);
    if (assistant == null) return;
    final list = List<AssistantRegex>.of(assistant.regexRules)
      ..removeWhere((r) => r.id == rule.id);
    await ap.updateAssistant(assistant.copyWith(regexRules: list));
  }

  Future<void> _addOrEdit({AssistantRegex? rule}) async {
    final ap = context.read<AssistantProvider>();
    final data = await _showRegexEditor(context, rule: rule);
    if (data == null) return;
    final assistant = ap.getById(widget.assistantId);
    if (assistant == null) return;
    final list = List<AssistantRegex>.of(assistant.regexRules);
    final updated = AssistantRegex(
      id: rule?.id ?? const Uuid().v4(),
      name: data.name,
      pattern: data.pattern,
      replacement: data.replacement,
      scopes: _normalizeScopes(data.scopes),
      visualOnly: data.visualOnly,
      replaceOnly: data.replaceOnly,
      enabled: rule?.enabled ?? true,
    );
    if (rule == null) {
      list.add(updated);
    } else {
      final idx = list.indexWhere((r) => r.id == rule.id);
      if (idx == -1) {
        list.add(updated);
      } else {
        list[idx] = updated;
      }
    }
    await ap.updateAssistant(assistant.copyWith(regexRules: list));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final assistant = context.watch<AssistantProvider>().getById(
      widget.assistantId,
    );
    if (assistant == null) return const SizedBox.shrink();
    final rules = assistant.regexRules;

    return Container(
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.assistantEditPageRegexTab,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: AppFontWeights.emphasis,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.assistantEditRegexDescription,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
                IosCardPress(
                  onTap: () => _addOrEdit(),
                  borderRadius: BorderRadius.circular(12),
                  baseColor: cs.primary.withValues(alpha: isDark ? 0.18 : 0.12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  pressedBlendStrength: 0.18,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Lucide.Plus, size: 16, color: cs.primary),
                      const SizedBox(width: 6),
                      Text(
                        l10n.assistantEditAddRegexButton,
                        style: TextStyle(
                          color: cs.primary,
                          fontWeight: AppFontWeights.emphasis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: rules.isEmpty
                ? Center(
                    child: Text(
                      l10n.assistantEditRegexDescription,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: rules.length,
                    buildDefaultDragHandles: false,
                    proxyDecorator: (child, index, animation) {
                      return AnimatedBuilder(
                        animation: animation,
                        builder: (context, _) {
                          final t = Curves.easeOut.transform(animation.value);
                          return Transform.scale(
                            scale: 0.985 + 0.015 * t,
                            child: child,
                          );
                        },
                      );
                    },
                    onReorderItem: _reorder,
                    itemBuilder: (context, index) {
                      final rule = rules[index];
                      return KeyedSubtree(
                        key: ValueKey('assistant-regex-desktop-${rule.id}'),
                        child: ReorderableDragStartListener(
                          index: index,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _RegexRuleCard(
                              rule: rule,
                              onTap: () => _addOrEdit(rule: rule),
                              onDelete: () => _deleteRule(rule),
                              onToggle: (v) => _toggleRule(rule, v),
                              desktop: true,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _RegexRuleCard extends StatefulWidget {
  const _RegexRuleCard({
    required this.rule,
    required this.onTap,
    required this.onDelete,
    required this.onToggle,
    required this.desktop,
  });

  final AssistantRegex rule;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggle;
  final bool desktop;

  @override
  State<_RegexRuleCard> createState() => _RegexRuleCardState();
}

class _RegexRuleCardState extends State<_RegexRuleCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final bg = context.appColors.surfaceCard;
    final borderBase = cs.outlineVariant.withValues(
      alpha: isDark ? 0.08 : 0.06,
    );
    final borderColor = widget.desktop && _hovered
        ? cs.primary.withValues(alpha: 0.55)
        : borderBase;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: IosCardPress(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(14),
        baseColor: bg,
        pressedBlendStrength: 0.16,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: 0.7),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.rule.name.isEmpty
                            ? l10n.assistantRegexUntitled
                            : widget.rule.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: AppFontWeights.emphasis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IosSwitch(
                      value: widget.rule.enabled,
                      onChanged: widget.onToggle,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _buildScopePills(context, widget.rule),
                      ),
                    ),
                    IosCardPress(
                      onTap: widget.onDelete,
                      borderRadius: BorderRadius.circular(12),
                      baseColor: Colors.transparent,
                      pressedBlendStrength: 0.16,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Lucide.Trash2, size: 16, color: cs.error),
                          const SizedBox(width: 6),
                          Text(
                            l10n.assistantRegexDeleteButton,
                            style: TextStyle(
                              color: cs.error,
                              fontWeight: AppFontWeights.emphasis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildScopePills(BuildContext context, AssistantRegex rule) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pills = <String>[];
    if (rule.scopes.contains(AssistantRegexScope.user)) {
      pills.add(l10n.assistantRegexScopeUser);
    }
    if (rule.scopes.contains(AssistantRegexScope.assistant)) {
      pills.add(l10n.assistantRegexScopeAssistant);
    }
    if (rule.visualOnly) {
      pills.add(l10n.assistantRegexScopeVisualOnly);
    }
    if (rule.replaceOnly) {
      pills.add(l10n.assistantRegexScopeReplaceOnly);
    }
    return pills
        .map(
          (p) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isDark
                  ? cs.onSurface.withValues(alpha: 0.06)
                  : cs.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: cs.primary.withValues(alpha: 0.35)),
            ),
            child: Text(
              p,
              style: TextStyle(
                fontSize: 12,
                fontWeight: AppFontWeights.semibold,
                color: cs.primary,
              ),
            ),
          ),
        )
        .toList();
  }
}

class _GlassCircleButton extends StatefulWidget {
  const _GlassCircleButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_GlassCircleButton> createState() => _GlassCircleButtonState();
}

class _GlassCircleButtonState extends State<_GlassCircleButton> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final glassBase = cs.surface.withValues(alpha: 0.06);
    final overlay = cs.onSurface.withValues(alpha: isDark ? 0.06 : 0.05);
    final tileColor = _pressed
        ? Color.alphaBlend(overlay, glassBase)
        : glassBase;
    final borderColor = cs.outlineVariant.withValues(alpha: 0.10);

    final child = SizedBox(
      width: 48,
      height: 48,
      child: Center(child: Icon(widget.icon, size: 18, color: widget.color)),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        Haptics.light();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
            child: Container(
              decoration: BoxDecoration(
                color: tileColor,
                border: Border.all(color: borderColor, width: 0.8),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _RegexFormData {
  const _RegexFormData({
    required this.name,
    required this.pattern,
    required this.replacement,
    required this.scopes,
    required this.visualOnly,
    required this.replaceOnly,
  });
  final String name;
  final String pattern;
  final String replacement;
  final List<AssistantRegexScope> scopes;
  final bool visualOnly;
  final bool replaceOnly;
}

Future<_RegexFormData?> _showRegexEditor(
  BuildContext context, {
  AssistantRegex? rule,
}) async {
  final platform = Theme.of(context).platform;
  final isDesktop =
      platform == TargetPlatform.macOS ||
      platform == TargetPlatform.linux ||
      platform == TargetPlatform.windows;
  return isDesktop
      ? _showRegexDialog(context, rule: rule)
      : _showRegexBottomSheet(context, rule: rule);
}

Future<_RegexFormData?> _showRegexBottomSheet(
  BuildContext context, {
  AssistantRegex? rule,
}) async {
  final cs = Theme.of(context).colorScheme;
  final l10n = AppLocalizations.of(context)!;
  final nameCtrl = TextEditingController(text: rule?.name ?? '');
  final patternCtrl = TextEditingController(text: rule?.pattern ?? '');
  final replacementCtrl = TextEditingController(text: rule?.replacement ?? '');
  final fieldsKey = GlobalKey<_RegexFieldsBlockState>();
  final Set<AssistantRegexScope> scopes = {
    ...(rule?.scopes ?? <AssistantRegexScope>[AssistantRegexScope.user]),
  };
  bool visualOnly = rule?.visualOnly ?? false;
  bool replaceOnly = rule?.replaceOnly ?? false;

  final result = await showModalBottomSheet<_RegexFormData>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.overlaySurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          Future<void> submit() async {
            // Read the JSON box back first; a bad paste keeps the sheet open.
            if (!(fieldsKey.currentState?.syncToFields() ?? true)) return;
            final name = nameCtrl.text.trim();
            final pattern = patternCtrl.text.trim();
            if (name.isEmpty || pattern.isEmpty || scopes.isEmpty) {
              showAppSnackBar(
                ctx,
                message: l10n.assistantRegexValidationError,
                type: NotificationType.warning,
              );
              return;
            }
            try {
              RegExp(pattern);
            } catch (_) {
              showAppSnackBar(
                ctx,
                message: l10n.assistantRegexInvalidPattern,
                type: NotificationType.warning,
              );
              return;
            }
            Navigator.of(ctx).pop(
              _RegexFormData(
                name: name,
                pattern: pattern,
                replacement: replacementCtrl.text,
                scopes: scopes.toList(),
                visualOnly: visualOnly,
                replaceOnly: replaceOnly,
              ),
            );
          }

          final bottom = MediaQuery.of(ctx).viewInsets.bottom;
          final maxHeight = MediaQuery.of(ctx).size.height * 0.9;
          return SafeArea(
            top: false,
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.only(bottom: bottom),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                        child: Row(
                          children: [
                            IosIconButton(
                              icon: Lucide.X,
                              size: 20,
                              minSize: 44,
                              onTap: () => Navigator.of(ctx).maybePop(),
                            ),
                            Expanded(
                              child: Center(
                                child: Text(
                                  rule == null
                                      ? l10n.assistantRegexAddTitle
                                      : l10n.assistantRegexEditTitle,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: AppFontWeights.emphasis,
                                  ),
                                ),
                              ),
                            ),
                            IosCardPress(
                              onTap: submit,
                              borderRadius: BorderRadius.circular(10),
                              baseColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              pressedBlendStrength: 0.1,
                              child: Text(
                                rule == null
                                    ? l10n.assistantRegexAddAction
                                    : l10n.assistantRegexSaveAction,
                                style: TextStyle(
                                  color: cs.primary,
                                  fontWeight: AppFontWeights.emphasis,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _RegexFieldsBlock(
                              key: fieldsKey,
                              nameCtrl: nameCtrl,
                              patternCtrl: patternCtrl,
                              replacementCtrl: replacementCtrl,
                              autofocusName: true,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              l10n.assistantRegexScopeLabel,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: AppFontWeights.emphasis,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _ScopeChoiceCard(
                                  label: l10n.assistantRegexScopeUser,
                                  selected: scopes.contains(
                                    AssistantRegexScope.user,
                                  ),
                                  onTap: () {
                                    setState(() {
                                      if (scopes.contains(
                                        AssistantRegexScope.user,
                                      )) {
                                        scopes.remove(AssistantRegexScope.user);
                                      } else {
                                        scopes.add(AssistantRegexScope.user);
                                      }
                                    });
                                  },
                                  desktop: false,
                                ),
                                _ScopeChoiceCard(
                                  label: l10n.assistantRegexScopeAssistant,
                                  selected: scopes.contains(
                                    AssistantRegexScope.assistant,
                                  ),
                                  onTap: () {
                                    setState(() {
                                      if (scopes.contains(
                                        AssistantRegexScope.assistant,
                                      )) {
                                        scopes.remove(
                                          AssistantRegexScope.assistant,
                                        );
                                      } else {
                                        scopes.add(
                                          AssistantRegexScope.assistant,
                                        );
                                      }
                                    });
                                  },
                                  desktop: false,
                                ),
                                _ScopeChoiceCard(
                                  label: l10n.assistantRegexScopeVisualOnly,
                                  selected: visualOnly,
                                  onTap: () {
                                    setState(() {
                                      visualOnly = !visualOnly;
                                      if (visualOnly) replaceOnly = false;
                                    });
                                  },
                                  desktop: false,
                                ),
                                _ScopeChoiceCard(
                                  label: l10n.assistantRegexScopeReplaceOnly,
                                  selected: replaceOnly,
                                  onTap: () {
                                    setState(() {
                                      replaceOnly = !replaceOnly;
                                      if (replaceOnly) visualOnly = false;
                                    });
                                  },
                                  desktop: false,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Center(
                              child: TextButton(
                                onPressed: () =>
                                    fieldsKey.currentState?.toggleMode(),
                                child: const Text('切换输入模式'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
  return result;
}

Future<_RegexFormData?> _showRegexDialog(
  BuildContext context, {
  AssistantRegex? rule,
}) async {
  final cs = Theme.of(context).colorScheme;
  final l10n = AppLocalizations.of(context)!;
  final nameCtrl = TextEditingController(text: rule?.name ?? '');
  final patternCtrl = TextEditingController(text: rule?.pattern ?? '');
  final replacementCtrl = TextEditingController(text: rule?.replacement ?? '');
  final fieldsKey = GlobalKey<_RegexFieldsBlockState>();
  final Set<AssistantRegexScope> scopes = {
    ...(rule?.scopes ?? <AssistantRegexScope>[AssistantRegexScope.user]),
  };
  bool visualOnly = rule?.visualOnly ?? false;
  bool replaceOnly = rule?.replaceOnly ?? false;

  final result = await showDialog<_RegexFormData>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return Dialog(
        backgroundColor: context.overlaySurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: StatefulBuilder(
          builder: (ctx, setState) {
            Future<void> submit() async {
              // Read the JSON box back first; a bad paste keeps the dialog open.
              if (!(fieldsKey.currentState?.syncToFields() ?? true)) return;
              final name = nameCtrl.text.trim();
              final pattern = patternCtrl.text.trim();
              if (name.isEmpty || pattern.isEmpty || scopes.isEmpty) {
                showAppSnackBar(
                  ctx,
                  message: l10n.assistantRegexValidationError,
                  type: NotificationType.warning,
                );
                return;
              }
              try {
                RegExp(pattern);
              } catch (_) {
                showAppSnackBar(
                  ctx,
                  message: l10n.assistantRegexInvalidPattern,
                  type: NotificationType.warning,
                );
                return;
              }
              Navigator.of(ctx).pop(
                _RegexFormData(
                  name: name,
                  pattern: pattern,
                  replacement: replacementCtrl.text,
                  scopes: scopes.toList(),
                  visualOnly: visualOnly,
                  replaceOnly: replaceOnly,
                ),
              );
            }

            return ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 48,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                rule == null
                                    ? l10n.assistantRegexAddTitle
                                    : l10n.assistantRegexEditTitle,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: AppFontWeights.emphasis,
                                ),
                              ),
                            ),
                            IosIconButton(
                              icon: Lucide.X,
                              size: 18,
                              padding: const EdgeInsets.all(8),
                              onTap: () => Navigator.of(ctx).maybePop(),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _RegexFieldsBlock(
                              key: fieldsKey,
                              nameCtrl: nameCtrl,
                              patternCtrl: patternCtrl,
                              replacementCtrl: replacementCtrl,
                              autofocusName: true,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              l10n.assistantRegexScopeLabel,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: AppFontWeights.emphasis,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _ScopeChoiceCard(
                                  label: l10n.assistantRegexScopeUser,
                                  selected: scopes.contains(
                                    AssistantRegexScope.user,
                                  ),
                                  onTap: () {
                                    setState(() {
                                      if (scopes.contains(
                                        AssistantRegexScope.user,
                                      )) {
                                        scopes.remove(AssistantRegexScope.user);
                                      } else {
                                        scopes.add(AssistantRegexScope.user);
                                      }
                                    });
                                  },
                                  desktop: true,
                                ),
                                _ScopeChoiceCard(
                                  label: l10n.assistantRegexScopeAssistant,
                                  selected: scopes.contains(
                                    AssistantRegexScope.assistant,
                                  ),
                                  onTap: () {
                                    setState(() {
                                      if (scopes.contains(
                                        AssistantRegexScope.assistant,
                                      )) {
                                        scopes.remove(
                                          AssistantRegexScope.assistant,
                                        );
                                      } else {
                                        scopes.add(
                                          AssistantRegexScope.assistant,
                                        );
                                      }
                                    });
                                  },
                                  desktop: true,
                                ),
                                _ScopeChoiceCard(
                                  label: l10n.assistantRegexScopeVisualOnly,
                                  selected: visualOnly,
                                  onTap: () {
                                    setState(() {
                                      visualOnly = !visualOnly;
                                      if (visualOnly) replaceOnly = false;
                                    });
                                  },
                                  desktop: true,
                                ),
                                _ScopeChoiceCard(
                                  label: l10n.assistantRegexScopeReplaceOnly,
                                  selected: replaceOnly,
                                  onTap: () {
                                    setState(() {
                                      replaceOnly = !replaceOnly;
                                      if (replaceOnly) visualOnly = false;
                                    });
                                  },
                                  desktop: true,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Center(
                              child: TextButton(
                                onPressed: () =>
                                    fieldsKey.currentState?.toggleMode(),
                                child: const Text('切换输入模式'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IosCardPress(
                            onTap: () => Navigator.of(ctx).maybePop(),
                            borderRadius: BorderRadius.circular(12),
                            baseColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            pressedBlendStrength: 0.12,
                            child: Text(
                              l10n.assistantRegexCancelButton,
                              style: TextStyle(
                                color: cs.onSurface.withValues(alpha: 0.8),
                                fontWeight: AppFontWeights.semibold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          IosCardPress(
                            onTap: submit,
                            borderRadius: BorderRadius.circular(12),
                            baseColor: cs.primary.withValues(alpha: 0.12),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            pressedBlendStrength: 0.16,
                            child: Text(
                              rule == null
                                  ? l10n.assistantRegexAddAction
                                  : l10n.assistantRegexSaveAction,
                              style: TextStyle(
                                color: cs.primary,
                                fontWeight: AppFontWeights.emphasis,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    },
  );

  nameCtrl.dispose();
  patternCtrl.dispose();
  replacementCtrl.dispose();
  return result;
}

/// Reads the pasted rule JSON without being picky, in three passes:
///
/// 1. strict JSON;
/// 2. the same, after escaping real line breaks that notes and chat apps leave
///    inside quoted strings;
/// 3. a hand-written fallback where every backslash is taken literally, so a
///    pattern can be pasted as `[\s\S]+` instead of `[\\s\\S]+`.
///
/// Returns null when nothing can be understood. Callers must leave every field
/// untouched in that case.
Map<String, String>? _parseLooseRegexJson(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } catch (_) {
    try {
      decoded = jsonDecode(_escapeControlCharsInsideStrings(text));
    } catch (_) {
      decoded = null;
    }
  }
  // A strict decode that turns a backslash into a control character (,
  // and friends) means the text was a regular expression, not JSON: keep the
  // backslashes by reading it the hand-written way instead.
  if (decoded is Map && !_holdsSuspectControlChars(decoded)) {
    return _collectRuleFields(decoded);
  }

  final relaxed = _parseRelaxedRuleObject(text);
  if (relaxed == null) return null;
  return _collectRuleFields(relaxed);
}

/// True when a decoded object contains control characters that only appear
/// because a regular expression's `\\b` / `\\f` were read as JSON escapes.
/// Line breaks and tabs are left alone: those are what a JSON string means.
bool _holdsSuspectControlChars(Object source) {
  if (source is! Map) return false;
  for (final value in source.values) {
    if (value is! String) continue;
    for (final rune in value.runes) {
      if (rune == 0x0A || rune == 0x0D || rune == 0x09) continue;
      if (rune < 0x20) return true;
    }
  }
  return false;
}

/// Keeps the fields this editor knows about and ignores everything else, so an
/// extra note in the JSON cannot break a paste.
Map<String, String>? _collectRuleFields(Object source) {
  if (source is! Map) return null;
  String? asText(Object? value) {
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();
    return null;
  }

  final out = <String, String>{};
  for (final entry in source.entries) {
    final key = entry.key.toString().trim().toLowerCase();
    final value = asText(entry.value);
    if (value == null) return null;
    if (key == '名称' || key == 'name') {
      out['name'] = value;
    } else if (key == '正则表达式' || key == 'pattern') {
      out['pattern'] = value;
    } else if (key == '替换字符串' || key == 'replacement') {
      out['replacement'] = value;
    }
  }
  return out.isEmpty ? null : out;
}

/// Hand-written fallback: reads `{"key": "value", ...}` where real line breaks
/// are allowed inside values and only `\\` and `\\"` are unescaped. Everything
/// else keeps its backslash, which is what a regular expression wants.
Map<String, String>? _parseRelaxedRuleObject(String text) {
  var i = 0;
  void skipSpace() {
    while (i < text.length && ' \t\r\n'.contains(text[i])) {
      i++;
    }
  }

  String? readString() {
    if (i >= text.length || text[i] != '"') return null;
    i++;
    final buffer = StringBuffer();
    var escaped = false;
    while (i < text.length) {
      final ch = text[i];
      if (escaped) {
        if (ch == '"' || ch == '\\') {
          buffer.write(ch);
        } else {
          buffer
            ..write(r'\')
            ..write(ch);
        }
        escaped = false;
        i++;
        continue;
      }
      if (ch == r'\') {
        escaped = true;
        i++;
        continue;
      }
      if (ch == '"') {
        i++;
        return buffer.toString();
      }
      buffer.write(ch);
      i++;
    }
    return null;
  }

  skipSpace();
  if (i >= text.length || text[i] != '{') return null;
  i++;

  final out = <String, String>{};
  while (true) {
    skipSpace();
    if (i < text.length && text[i] == '}') break;
    final key = readString();
    if (key == null) return null;
    skipSpace();
    if (i >= text.length || text[i] != ':') return null;
    i++;
    skipSpace();
    final value = readString();
    if (value == null) return null;
    out[key] = value;
    skipSpace();
    if (i < text.length && text[i] == ',') {
      i++;
      continue;
    }
    if (i < text.length && text[i] == '}') break;
    return null;
  }
  return out;
}

/// Turns real line breaks, tabs and carriage returns that sit inside quoted
/// strings into their escape sequences, which is what JSON actually wants.
String _escapeControlCharsInsideStrings(String source) {
  final out = StringBuffer();
  var inString = false;
  var escaped = false;
  for (var i = 0; i < source.length; i++) {
    final ch = source[i];
    if (inString) {
      if (escaped) {
        escaped = false;
        out.write(ch);
        continue;
      }
      if (ch == r'\') {
        escaped = true;
        out.write(ch);
        continue;
      }
      if (ch == '"') {
        inString = false;
        out.write(ch);
        continue;
      }
      if (ch == '\n') {
        out.write(r'\n');
        continue;
      }
      if (ch == '\r') {
        continue;
      }
      if (ch == '\t') {
        out.write(r'\t');
        continue;
      }
      out.write(ch);
      continue;
    }
    if (ch == '"') inString = true;
    out.write(ch);
  }
  return out.toString();
}

/// The three rule fields, with a text mode that folds them into one JSON box.
///
/// Switching never rewrites content: going to text mode dumps the three
/// controllers verbatim, and coming back fills them only from keys the JSON
/// actually carries. A paste that cannot be understood reports itself and
/// leaves both the JSON box and the three fields exactly as they were.
class _RegexFieldsBlock extends StatefulWidget {
  const _RegexFieldsBlock({
    super.key,
    required this.nameCtrl,
    required this.patternCtrl,
    required this.replacementCtrl,
    this.autofocusName = false,
  });

  final TextEditingController nameCtrl;
  final TextEditingController patternCtrl;
  final TextEditingController replacementCtrl;
  final bool autofocusName;

  @override
  State<_RegexFieldsBlock> createState() => _RegexFieldsBlockState();
}

class _RegexFieldsBlockState extends State<_RegexFieldsBlock> {
  static const String _nameKey = '名称';
  static const String _patternKey = '正则表达式';
  static const String _replacementKey = '替换字符串';

  final TextEditingController _jsonCtrl = TextEditingController();
  bool _textMode = false;

  @override
  void dispose() {
    _jsonCtrl.dispose();
    super.dispose();
  }

  String _composeJson() {
    return const JsonEncoder.withIndent('  ').convert(<String, String>{
      _nameKey: widget.nameCtrl.text,
      _patternKey: widget.patternCtrl.text,
      _replacementKey: widget.replacementCtrl.text,
    });
  }

  /// Writes the JSON box back into the three fields. False means "could not be
  /// read": nothing has been changed and the caller must stay put.
  bool syncToFields() {
    if (!_textMode) return true;
    final parsed = _parseLooseRegexJson(_jsonCtrl.text);
    if (parsed == null) {
      showAppSnackBar(
        context,
        message: '这段 JSON 读不出来，原文没动，改好再切',
        type: NotificationType.warning,
      );
      return false;
    }
    final name = parsed['name'];
    final pattern = parsed['pattern'];
    final replacement = parsed['replacement'];
    if (name != null) widget.nameCtrl.text = name;
    if (pattern != null) widget.patternCtrl.text = pattern;
    if (replacement != null) widget.replacementCtrl.text = replacement;
    return true;
  }

  /// Entry point for the sheet's toggle button, which lives below the scope
  /// cards so the whole editor does not jump around when the mode flips.
  void toggleMode() {
    if (_textMode) {
      if (!syncToFields()) return;
      setState(() => _textMode = false);
      return;
    }
    _jsonCtrl.text = _composeJson();
    setState(() => _textMode = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_textMode) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RegexTextField(
            controller: widget.nameCtrl,
            label: AppLocalizations.of(context)!.assistantRegexNameLabel,
            autofocus: widget.autofocusName,
          ),
          const SizedBox(height: 12),
          _RegexTextField(
            controller: widget.patternCtrl,
            label: AppLocalizations.of(context)!.assistantRegexPatternLabel,
          ),
          const SizedBox(height: 12),
          _RegexTextField(
            controller: widget.replacementCtrl,
            label: AppLocalizations.of(context)!.assistantRegexReplacementLabel,
            multiline: true,
          ),
        ],
      );
    }
    return _RegexTextField(
      controller: _jsonCtrl,
      label: '规则 JSON',
      multiline: true,
    );
  }
}

class _RegexTextField extends StatelessWidget {
  const _RegexTextField({
    required this.controller,
    required this.label,
    this.autofocus = false,
    this.multiline = false,
  });

  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      autofocus: autofocus,
      minLines: multiline ? 1 : 1,
      maxLines: multiline ? null : 1,
      keyboardType: multiline ? TextInputType.multiline : TextInputType.text,
      textInputAction: multiline
          ? TextInputAction.newline
          : TextInputAction.done,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: context.appColors.surfaceFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.primary.withValues(alpha: 0.5)),
        ),
      ),
    );
  }
}

class _ScopeChoiceCard extends StatefulWidget {
  const _ScopeChoiceCard({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.desktop,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool desktop;

  @override
  State<_ScopeChoiceCard> createState() => _ScopeChoiceCardState();
}

class _ScopeChoiceCardState extends State<_ScopeChoiceCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = widget.selected
        ? cs.primary.withValues(alpha: 0.16)
        : (context.appColors.surfaceFill);
    final borderBase = widget.selected
        ? cs.primary.withValues(alpha: 0.55)
        : cs.outlineVariant.withValues(alpha: isDark ? 0.14 : 0.12);
    final borderColor = (widget.desktop && _hovered) ? cs.primary : borderBase;
    final fg = widget.selected
        ? cs.primary
        : cs.onSurface.withValues(alpha: 0.8);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: AppFontWeights.emphasis,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}
