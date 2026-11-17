import 'package:flutter/material.dart';

import '../../../shared/markdown/markdown_with_code_highlight.dart';
import '../../../theme/design_tokens.dart';
import '../pages/simulator_list_page.dart';

/// Shown when the reply carries a `:::结局` block. It sits above the keys as a
/// card; "接着写" folds it away, "重新开始" opens the simulation list so a new
/// run can be started.
class SimulatorEndingCard extends StatefulWidget {
  const SimulatorEndingCard({super.key, required this.markdown});

  final String markdown;

  @override
  State<SimulatorEndingCard> createState() => _SimulatorEndingCardState();
}

class _SimulatorEndingCardState extends State<SimulatorEndingCard> {
  bool _dismissed = false;
  String? _known;

  @override
  Widget build(BuildContext context) {
    if (widget.markdown != _known) {
      _known = widget.markdown;
      _dismissed = false;
    }
    if (_dismissed) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.xs, AppSpacing.sm, AppSpacing.xs),
        decoration: BoxDecoration(
          color: cs.onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.onSurface.withValues(alpha: 0.10)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  '结局',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _dismissed = true),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('接着写'),
                ),
                TextButton(
                  onPressed: () {
                    setState(() => _dismissed = true);
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const SimulatorListPage(),
                      ),
                    );
                  },
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('重新开始'),
                ),
              ],
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: MarkdownWithCodeHighlight(
                  text: widget.markdown,
                  detailsStateKey: 'simulator-ending',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
