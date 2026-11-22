import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:markstream/markstream.dart';

import 'package:Kelivo/icons/lucide_adapter.dart';
import 'package:Kelivo/shared/widgets/snackbar.dart';

/// Height of a `:::scroll` block, including its optional title row.
const double scrollDirectiveBlockHeight = 320;

const _ink = Color(0xFF1C1C1E);
const _mutedInk = Color(0xFFB8B8BD);
const _border = Color(0xFFE4E4E7);

/// Renders a `:::scroll[标题] ... :::` directive as a fixed white scrolling
/// card. The card deliberately ignores dark mode: both the surface and its
/// text are pinned to light values so it stays readable in every theme.
///
/// Only text is projected into the card. `toPlainText` keeps paragraph and
/// list wording while dropping chrome such as code fences, which matches the
/// narrative use case this syntax was added for.
Widget buildScrollDirectiveBlock(
  BuildContext context,
  BlockNode node,
  MarkstreamRenderContext rendering,
) {
  final named = node as NamedBlockNode;
  final bodyNodes = <BlockNode>[
    for (final child in named.children)
      if (child is! DirectiveLabelNode) child,
  ];
  final text = bodyNodes.map(toPlainText).join('\n\n').trim();
  final title = _resolveTitle(named);
  return _ScrollDirectiveCard(title: title, text: text);
}

String? _resolveTitle(NamedBlockNode node) {
  final attribute = node.attributes['title']?.trim();
  if (attribute != null && attribute.isNotEmpty) return attribute;
  for (final child in node.children) {
    if (child is! DirectiveLabelNode) continue;
    final label = toPlainText(child).trim();
    if (label.isNotEmpty) return label;
  }
  return null;
}

/// 右侧细滚动条。不用内置 Scrollbar：它挂在 ConstrainedBox(maxHeight) 里的
/// SingleChildScrollView 上时，首次布局拿到的 extent 是 0，会把 thumb 画在中间。
/// 这里直接按 controller 的实时 pixels/extent 算，顶部就是 pixels == 0。
class _ScrollThumb extends StatelessWidget {
  const _ScrollThumb({required this.controller, required this.color});

  final ScrollController controller;
  final Color color;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      if (!controller.hasClients) return const SizedBox.shrink();
      final position = controller.position;
      final viewport = position.viewportDimension;
      final total = position.extentTotal;
      if (viewport <= 0 || total <= viewport + 1) {
        return const SizedBox.shrink();
      }
      // Stack 的高度就是滚动视口高度，把它们当同一条轨道算比例。
      final thumbHeight =
          (viewport / total * viewport).clamp(24.0, viewport).toDouble();
      final maxScroll = total - viewport;
      final progress = maxScroll <= 0
          ? 0.0
          : (position.pixels / maxScroll).clamp(0.0, 1.0);
      final top =
          (progress * (viewport - thumbHeight)).clamp(0.0, viewport - thumbHeight).toDouble();
      return Align(
        alignment: AlignmentDirectional.topEnd,
        child: Padding(
          padding: EdgeInsetsDirectional.only(end: 2, top: top),
          child: Container(
            width: 4,
            height: thumbHeight,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      );
    },
  );
}

class _ScrollDirectiveCard extends StatefulWidget {
  const _ScrollDirectiveCard({required this.title, required this.text});

  final String? title;
  final String text;

  @override
  State<_ScrollDirectiveCard> createState() => _ScrollDirectiveCardState();
}

class _ScrollDirectiveCardState extends State<_ScrollDirectiveCard> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: '已复制',
      type: NotificationType.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasTitle = widget.title != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _border, width: 1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 24,
                child: SelectionContainer.disabled(
                  child: Row(
                    children: [
                      if (hasTitle) ...[
                        Icon(
                          Lucide.FileText,
                          size: 15,
                          color: _mutedInk,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            widget.title!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _ink,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ] else
                        const Spacer(),
                      _copyButton,
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: scrollDirectiveBlockHeight - 44,
                ),
                child: Stack(
                  children: [
                    // 这块卡片刻意钉死白底深字：禁用文字选择，免得 SelectionArea
                    // 的选中高亮把正文冲成灰底浅字（有右上角一键复制兜底）。
                    SingleChildScrollView(
                      controller: _controller,
                      primary: false,
                      physics: const ClampingScrollPhysics(),
                      child: SelectionContainer.disabled(
                        child: Text(
                          widget.text,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 15.5,
                            height: 1.55,
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: _ScrollThumb(
                        controller: _controller,
                        color: _mutedInk,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget get _copyButton => Tooltip(
    message: '复制',
    child: InkWell(
      onTap: _copy,
      borderRadius: BorderRadius.circular(6),
      child: const Padding(
        padding: EdgeInsets.all(4),
        child: Icon(Lucide.Copy, size: 16, color: _mutedInk),
      ),
    ),
  );
}
