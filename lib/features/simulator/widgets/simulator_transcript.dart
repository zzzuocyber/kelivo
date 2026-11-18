import 'package:flutter/material.dart';

import '../../../shared/markdown/markdown_with_code_highlight.dart';
import '../../../theme/design_tokens.dart';

/// 模拟器的正文：草图里那一页文档。
///
/// 不是聊天记录——没有头像、没有名字行、没有一条条气泡；所有叙述排在同一张
/// 卡片里，从上往下连续读，内容长出来就自动贴住底部（用户自己往上翻过之后
/// 就不再抢他的位置）。
class SimulatorTranscript extends StatefulWidget {
  const SimulatorTranscript({
    super.key,
    required this.text,
    this.conversationId,
    this.streaming = false,
  });

  final String text;
  final String? conversationId;
  final bool streaming;

  @override
  State<SimulatorTranscript> createState() => _SimulatorTranscriptState();
}

class _SimulatorTranscriptState extends State<SimulatorTranscript> {
  final ScrollController _scroll = ScrollController();
  bool _follow = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _reveal(animate: false);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SimulatorTranscript oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      _follow = true;
      _reveal(animate: false);
      return;
    }
    if (oldWidget.text != widget.text) {
      // 流式时每个片段都可能变长，直接贴底不排队做动画。
      _reveal(animate: !widget.streaming);
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    _follow = position.pixels >= position.maxScrollExtent - 48;
  }

  void _reveal({required bool animate}) {
    if (!_follow) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (animate) {
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
        );
      } else {
        _scroll.jumpTo(target);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    if (text.trim().isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: cs.onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: MarkdownWithCodeHighlight(
          text: text,
          conversationId: widget.conversationId,
          streaming: widget.streaming,
          baseStyle: TextStyle(
            fontSize: 14.5,
            height: 1.85,
            color: cs.onSurface,
          ),
        ),
      ),
    );
  }
}
