import 'package:flutter/material.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/design_tokens.dart';
import '../simulator_options.dart';

/// Turns the parsed options into four square keys plus the free-text field.
///
/// Nothing here touches storage: a tapped key simply sends its text through
/// the same composer path the chat page uses, so the record stays an ordinary
/// conversation.
class SimulatorOptionBar extends StatefulWidget {
  const SimulatorOptionBar({
    super.key,
    required this.options,
    required this.onSend,
    this.enabled = true,
  });

  final List<SimulatorOption> options;
  final ValueChanged<String> onSend;
  final bool enabled;

  @override
  State<SimulatorOptionBar> createState() => _SimulatorOptionBarState();
}

class _SimulatorOptionBarState extends State<SimulatorOptionBar> {
  final TextEditingController _free = TextEditingController();
  SimulatorOption? _selected;

  @override
  void dispose() {
    _free.dispose();
    super.dispose();
  }

  SimulatorOption? _optionFor(String letter) {
    for (final option in widget.options) {
      if (option.letter == letter) return option;
    }
    return null;
  }

  void _pick(SimulatorOption option) {
    if (!widget.enabled) return;
    setState(() => _selected = option);
  }

  void _sendSelected() {
    final option = _selected;
    if (option == null) return;
    setState(() => _selected = null);
    widget.onSend(option.text);
  }

  void _sendFree() {
    final text = _free.text.trim();
    if (text.isEmpty || !widget.enabled) return;
    _free.clear();
    widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final strong = cs.onSurface.withValues(alpha: 0.82);
    final faint = cs.onSurface.withValues(alpha: 0.45);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_selected != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.md,
              0,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_selected!.letter}. ${_selected!.text}',
                      style: TextStyle(fontSize: 13, color: cs.onSurface),
                    ),
                  ),
                  TextButton(
                    onPressed: widget.enabled ? _sendSelected : null,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: const Text('发送'),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _selected = null),
                    icon: Icon(Lucide.X, size: 16, color: faint),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: Row(
            children: [
              for (final letter in SimulatorOptions.buttonLetters) ...[
                _SquareKey(
                  letter: letter,
                  option: _optionFor(letter),
                  selected: _selected?.letter == letter,
                  color: strong,
                  accent: cs.primary,
                  onTap: widget.enabled
                      ? () {
                          final option = _optionFor(letter);
                          if (option != null) _pick(option);
                        }
                      : null,
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'E',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: faint,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: _free,
                          enabled: widget.enabled,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _sendFree(),
                          style: TextStyle(fontSize: 13, color: cs.onSurface),
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 6,
                            ),
                            hintText: '自己写一个走向',
                            hintStyle: TextStyle(fontSize: 13, color: faint),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: widget.enabled ? _sendFree : null,
                        icon: Icon(Lucide.ArrowUp, size: 16, color: cs.primary),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SquareKey extends StatelessWidget {
  const _SquareKey({
    required this.letter,
    required this.option,
    required this.selected,
    required this.color,
    required this.accent,
    required this.onTap,
  });

  final String letter;
  final SimulatorOption? option;
  final bool selected;
  final Color color;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final missing = option == null;
    final background = selected
        ? accent
        : theme.colorScheme.onSurface.withValues(alpha: missing ? 0.03 : 0.06);
    final ink = selected
        ? theme.colorScheme.onPrimary
        : color.withValues(alpha: missing ? 0.35 : 0.9);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: missing ? null : onTap,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.onSurface.withValues(
              alpha: missing ? 0.06 : 0.12,
            ),
          ),
        ),
        child: Text(
          letter,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
      ),
    );
  }
}
