import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/chat/chat_service.dart';
import '../../../theme/app_font_weights.dart';
import '../../../theme/app_semantic_colors.dart';

/// 临时笔记：每个对话一份，只存在对话自带的附加数据里，不落任何文件。
/// 键名避开 prompt.* 与 background，不会被拼进提示词。
const conversationNoteKey = 'note.text';

/// 从对话附加数据里读出笔记正文，没写过就是空串。
String conversationNoteText(Map<String, dynamic> extras) {
  final raw = extras[conversationNoteKey];
  return raw is String ? raw : '';
}

Future<void> editConversationNote(
  BuildContext context, {
  required String conversationId,
}) async {
  final chat = context.read<ChatService>();
  final initial = conversationNoteText(
    chat.getConversation(conversationId)?.extras ?? const {},
  );
  await showConversationNoteSheet(
    context,
    initial: initial,
    onChanged: (text) => _persistNote(chat, conversationId, text),
  );
}

Future<void> _persistNote(
  ChatService chat,
  String conversationId,
  String text,
) async {
  try {
    await chat.updateConversationExtras(conversationId, (extras) {
      final next = Map<String, dynamic>.from(extras);
      if (text.isEmpty) {
        next.remove(conversationNoteKey);
      } else {
        next[conversationNoteKey] = text;
      }
      return next;
    });
  } catch (_) {
    // 笔记丢了不影响聊天，静默失败。
  }
}

Future<void> showConversationNoteSheet(
  BuildContext context, {
  required String initial,
  required ValueChanged<String> onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : null,
    backgroundColor: context.overlaySurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _ConversationNoteSheet(
      initial: initial,
      onChanged: onChanged,
    ),
  );
}

class _ConversationNoteSheet extends StatefulWidget {
  const _ConversationNoteSheet({required this.initial, required this.onChanged});

  final String initial;
  final ValueChanged<String> onChanged;

  @override
  State<_ConversationNoteSheet> createState() => _ConversationNoteSheetState();
}

class _ConversationNoteSheetState extends State<_ConversationNoteSheet> {
  static const _autoSaveDelay = Duration(milliseconds: 600);
  // 面板总高对齐「对话系统提示词」面板，那边多出来的说明文字和按钮位置
  // 在这里全部换成输入框，所以框比那边高不少。
  static const _targetFieldHeight = 240.0;
  static const _headerHeight = 54.0;
  static const _sheetPadding = 28.0;

  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  late String _saved = widget.initial;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _commit(_controller.text);
    _controller.dispose();
    super.dispose();
  }

  void _commit(String text) {
    if (text == _saved) return;
    _saved = text;
    widget.onChanged(text);
  }

  void _handleChanged(String text) {
    _timer?.cancel();
    _timer = Timer(_autoSaveDelay, () => _commit(text));
  }

  double _fieldHeight(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context);
    final padding = MediaQuery.paddingOf(context);
    final available =
        MediaQuery.sizeOf(context).height -
        insets.bottom -
        padding.top -
        24 -
        _headerHeight -
        _sheetPadding;
    if (available <= _targetFieldHeight) {
      return available.clamp(140.0, _targetFieldHeight);
    }
    return _targetFieldHeight;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final insets = MediaQuery.viewInsetsOf(context);
    final fieldBg = context.appColors.surfaceCardFill;
    final textStyle = TextStyle(
      fontSize: 15,
      fontWeight: AppFontWeights.medium,
      color: cs.onSurface.withValues(alpha: 0.92),
      height: 1.25,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  '临时笔记',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: AppFontWeights.semibold,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: _fieldHeight(context),
                child: Container(
                  decoration: BoxDecoration(
                    color: fieldBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  child: TextField(
                    key: const ValueKey('conversation-note-input'),
                    controller: _controller,
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    style: textStyle,
                    onChanged: _handleChanged,
                    decoration: const InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                    ),
                    cursorColor: cs.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
