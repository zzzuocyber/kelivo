import 'package:flutter/material.dart';

import '../../../shared/markdown/markdown_with_code_highlight.dart';
import '../simulator_blocks.dart';

/// The status area, pinned above the composer.
///
/// The content is rendered as markdown `<details>` blocks, so it inherits the
/// app's collapsible styling (light surface with dark ink, also in dark mode)
/// and nests per character without any custom drawing here.
class SimulatorStatusPanel extends StatelessWidget {
  const SimulatorStatusPanel({
    super.key,
    required this.sections,
    this.maxHeight = 240,
  });

  final List<SimulatorStatusSection> sections;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    if (sections.isEmpty) return const SizedBox.shrink();
    final markdown = SimulatorBlocks.statusDetailsMarkdown(sections);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
        child: MarkdownWithCodeHighlight(
          text: markdown,
          detailsStateKey: 'simulator-status',
        ),
      ),
    );
  }
}
