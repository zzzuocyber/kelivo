import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/database/business_preferences.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/sheet_drag_region.dart';
import '../../../theme/app_font_weights.dart';
import '../../../theme/app_semantic_colors.dart';

/// 临时笔记：只存在对话自带的附加数据里，不落任何文件。
/// 键名避开 prompt.* 与 background，不会被拼进提示词。
/// 第一格沿用老键名，之前写过的内容不会丢。
const conversationNoteKey = 'note.text';

/// 这一格笔记「跟随助手」：为真时四格笔记存在助手上，同一助手的会话共用。
const conversationNoteFollowKey = 'note.follow_assistant';

/// 跟着助手走的四格笔记，存成 {助手 id: [四段文字]} 的 JSON。
const conversationNoteAssistantStoreKey = 'note.assistant.v1';

/// 面板上有几格笔记。
const conversationNoteSlotCount = 4;

String _slotKey(int index) =>
    index == 0 ? conversationNoteKey : '$conversationNoteKey.${index + 1}';

/// 这个对话的笔记是不是挂在助手身上。
bool conversationNoteFollowsAssistant(Map<String, dynamic> extras) =>
    extras[conversationNoteFollowKey] == true;

/// 读某一格的正文，没写过就是空串。
String conversationNoteSlotText(Map<String, dynamic> extras, int index) {
  final raw = extras[_slotKey(index)];
  return raw is String ? raw : '';
}

/// 四格正文，按顺序。
List<String> conversationNoteSlots(Map<String, dynamic> extras) => [
  for (var i = 0; i < conversationNoteSlotCount; i++)
    conversationNoteSlotText(extras, i),
];

/// 从这个对话自己的附加数据里读笔记正文：返回第一格有内容的，都没有就是空串。
/// 跟随助手的那一份用 [readAssistantNotes] 单独读。
String conversationNoteText(Map<String, dynamic> extras) {
  for (final text in conversationNoteSlots(extras)) {
    if (text.trim().isNotEmpty) return text;
  }
  return '';
}

/// 读某个助手名下的四格笔记（跟随助手时用）。
List<String> readAssistantNotes(
  BusinessPreferences prefs,
  String assistantId,
) {
  // 必须是可增长的：调用方会直接改其中一格。
  final empty = List<String>.filled(
    conversationNoteSlotCount,
    '',
    growable: true,
  );
  if (assistantId.isEmpty) return empty;
  final raw = prefs.getString(conversationNoteAssistantStoreKey);
  if (raw == null || raw.isEmpty) return empty;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return empty;
    final stored = decoded[assistantId];
    if (stored is! List) return empty;
    return [
      for (var i = 0; i < conversationNoteSlotCount; i++)
        i < stored.length && stored[i] is String ? stored[i] as String : '',
    ];
  } catch (_) {
    return empty;
  }
}

/// 写某个助手的四格笔记；四格全空时把这名助手从表里删掉。
Future<void> writeAssistantNotes(
  BusinessPreferences prefs,
  String assistantId,
  List<String> slots,
) async {
  if (assistantId.isEmpty) return;
  Map<String, dynamic> map;
  try {
    final raw = prefs.getString(conversationNoteAssistantStoreKey);
    final decoded = raw == null || raw.isEmpty ? null : jsonDecode(raw);
    map = decoded is Map<String, dynamic>
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
  } catch (_) {
    map = <String, dynamic>{};
  }
  if (slots.every((text) => text.trim().isEmpty)) {
    map.remove(assistantId);
  } else {
    map[assistantId] = slots;
  }
  if (map.isEmpty) {
    await prefs.remove(conversationNoteAssistantStoreKey);
  } else {
    await prefs.setString(conversationNoteAssistantStoreKey, jsonEncode(map));
  }
}

Future<void> editConversationNote(
  BuildContext context, {
  required String conversationId,
}) async {
  final chat = context.read<ChatService>();
  final prefs = context.read<BusinessPreferences>();
  final assistantId =
      context
          .read<AssistantProvider>()
          .resolveConversationAssistant(
            chat.getConversation(conversationId)?.assistantId,
          )
          ?.id ??
      '';
  final extras = chat.getConversation(conversationId)?.extras ?? const {};
  final initialFollow =
      conversationNoteFollowsAssistant(extras) && assistantId.isNotEmpty;
  await prefs.load();

  Future<List<String>> loadSlots(bool follow) async {
    if (follow && assistantId.isNotEmpty) {
      return readAssistantNotes(prefs, assistantId);
    }
    final current = chat.getConversation(conversationId)?.extras ?? const {};
    return conversationNoteSlots(current);
  }

  Future<void> saveSlot(bool follow, int index, String text) async {
    if (follow && assistantId.isNotEmpty) {
      try {
        final slots = readAssistantNotes(prefs, assistantId);
        slots[index] = text;
        await writeAssistantNotes(prefs, assistantId, slots);
      } catch (_) {
        // 保存失败不影响聊天，静默。
      }
      return;
    }
    await _persistNote(chat, conversationId, index, text);
  }

  Future<void> toggleFollow(bool follow) async {
    // 刚打开跟随时，若助手那边四格全空，先把当前对话的笔记搬过去，
    // 免得一按按钮文字就「消失」了。
    if (follow && assistantId.isNotEmpty) {
      final existing = readAssistantNotes(prefs, assistantId);
      if (existing.every((text) => text.trim().isEmpty)) {
        final own = conversationNoteSlots(
          chat.getConversation(conversationId)?.extras ?? const {},
        );
        if (own.any((text) => text.trim().isNotEmpty)) {
          await writeAssistantNotes(prefs, assistantId, own);
        }
      }
    }
    await chat.updateConversationExtras(conversationId, (extras) {
      final next = Map<String, dynamic>.from(extras);
      if (follow) {
        next[conversationNoteFollowKey] = true;
      } else {
        next.remove(conversationNoteFollowKey);
      }
      return next;
    });
  }

  await showConversationNoteSheet(
    context,
    initialSlots: await loadSlots(initialFollow),
    followAssistant: initialFollow,
    canFollowAssistant: assistantId.isNotEmpty,
    onToggleFollow: toggleFollow,
    loadSlots: loadSlots,
    onChanged: saveSlot,
  );
}

Future<void> _persistNote(
  ChatService chat,
  String conversationId,
  int index,
  String text,
) async {
  try {
    await chat.updateConversationExtras(conversationId, (extras) {
      final next = Map<String, dynamic>.from(extras);
      if (text.isEmpty) {
        next.remove(_slotKey(index));
      } else {
        next[_slotKey(index)] = text;
      }
      return next;
    });
  } catch (_) {
    // 笔记丢了不影响聊天，静默失败。
  }
}

Future<void> showConversationNoteSheet(
  BuildContext context, {
  required List<String> initialSlots,
  required bool followAssistant,
  required bool canFollowAssistant,
  required Future<void> Function(bool follow) onToggleFollow,
  required Future<List<String>> Function(bool follow) loadSlots,
  required Future<void> Function(bool follow, int index, String text) onChanged,
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
      initialSlots: initialSlots,
      followAssistant: followAssistant,
      canFollowAssistant: canFollowAssistant,
      onToggleFollow: onToggleFollow,
      loadSlots: loadSlots,
      onChanged: onChanged,
    ),
  );
}

class _ConversationNoteSheet extends StatefulWidget {
  const _ConversationNoteSheet({
    required this.initialSlots,
    required this.followAssistant,
    required this.canFollowAssistant,
    required this.onToggleFollow,
    required this.loadSlots,
    required this.onChanged,
  });

  final List<String> initialSlots;
  final bool followAssistant;
  final bool canFollowAssistant;
  final Future<void> Function(bool follow) onToggleFollow;
  final Future<List<String>> Function(bool follow) loadSlots;
  final Future<void> Function(bool follow, int index, String text) onChanged;

  @override
  State<_ConversationNoteSheet> createState() => _ConversationNoteSheetState();
}

class _ConversationNoteSheetState extends State<_ConversationNoteSheet> {
  static const _autoSaveDelay = Duration(milliseconds: 600);
  static const _minSize = 0.32;
  static const _maxSize = 0.94;

  late final List<TextEditingController> _controllers = [
    for (final text in widget.initialSlots) TextEditingController(text: text),
  ];
  late final List<String> _saved = List<String>.from(widget.initialSlots);
  late bool _follow = widget.followAssistant;
  // builder 给的是内容滚动控制器；面板伸缩要单独建一个。
  final _sheetController = DraggableScrollableController();
  late int _slot = _firstFilledSlot(widget.initialSlots);
  bool _switching = false;
  Timer? _timer;

  /// 打开时直接落在第一格有内容的笔记上，四格都空才停在 1。
  static int _firstFilledSlot(List<String> slots) {
    for (var i = 0; i < slots.length; i++) {
      if (slots[i].trim().isNotEmpty) return i;
    }
    return 0;
  }

  @override
  void dispose() {
    _sheetController.dispose();
    _timer?.cancel();
    _commit(_slot, _controllers[_slot].text);
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _commit(int index, String text) {
    if (index < 0 || index >= _saved.length) return;
    if (text == _saved[index]) return;
    _saved[index] = text;
    widget.onChanged(_follow, index, text);
  }

  void _handleChanged(String text) {
    final slot = _slot;
    _timer?.cancel();
    _timer = Timer(_autoSaveDelay, () => _commit(slot, text));
  }

  void _selectSlot(int index) {
    if (index == _slot) return;
    _timer?.cancel();
    // 切走之前先把当前这格存下来，不然刚打的字会跟着计时器丢掉。
    _commit(_slot, _controllers[_slot].text);
    setState(() => _slot = index);
  }

  Future<void> _toggleFollow() async {
    if (_switching || !widget.canFollowAssistant) return;
    _switching = true;
    _timer?.cancel();
    _commit(_slot, _controllers[_slot].text);
    final next = !_follow;
    try {
      await widget.onToggleFollow(next);
      final slots = await widget.loadSlots(next);
      if (!mounted) return;
      setState(() {
        _follow = next;
        for (var i = 0; i < _controllers.length; i++) {
          final text = i < slots.length ? slots[i] : '';
          _controllers[i].text = text;
          _saved[i] = text;
        }
        _slot = _firstFilledSlot(slots);
      });
    } finally {
      _switching = false;
    }
  }

  Widget _grabber(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: cs.onSurface.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }

  Widget _followButton(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final on = _follow;
    final color = widget.canFollowAssistant
        ? (on ? cs.primary : cs.onSurface.withValues(alpha: 0.35))
        : cs.onSurface.withValues(alpha: 0.18);
    return Tooltip(
      message: on ? '笔记跟随这个助手的所有会话' : '笔记只属于这个会话',
      child: Semantics(
        button: true,
        selected: on,
        label: '跟随助手',
        child: IosCardPress(
          key: const ValueKey('conversation-note-follow'),
          baseColor: on
              ? cs.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          padding: const EdgeInsets.all(6),
          onTap: widget.canFollowAssistant ? _toggleFollow : null,
          child: Icon(Lucide.Bot, size: 16, color: color),
        ),
      ),
    );
  }

  Widget _slotTab(BuildContext context, int index) {
    final cs = Theme.of(context).colorScheme;
    final selected = _slot == index;
    final hasText = _controllers[index].text.trim().isNotEmpty;
    final bg = selected
        ? cs.primary.withValues(alpha: 0.14)
        : context.appColors.surfaceCardFill;
    final fg = selected
        ? cs.primary
        : cs.onSurface.withValues(alpha: hasText ? 0.85 : 0.42);
    return Semantics(
      button: true,
      selected: selected,
      label: '第 ${index + 1} 格笔记',
      child: IosCardPress(
        baseColor: bg,
        borderRadius: BorderRadius.circular(9),
        padding: EdgeInsets.zero,
        onTap: () => _selectSlot(index),
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected
                  ? cs.primary.withValues(alpha: 0.35)
                  : cs.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Text(
            '${index + 1}',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected
                  ? AppFontWeights.semibold
                  : AppFontWeights.medium,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final insets = MediaQuery.viewInsetsOf(context);
    final available = MediaQuery.sizeOf(context).height - insets.bottom;
    // 键盘占掉一截后可用高度会矮很多，此时再按 0.32 收起，标题行就塞不下
    // （输入区会被挤成负数直接报溢出），所以抬高下限。
    final minSize = insets.bottom > 0 ? 0.58 : _minSize;
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
        child: DraggableScrollableSheet(
          controller: _sheetController,
          expand: false,
          initialChildSize: 0.5,
          minChildSize: minSize,
          maxChildSize: _maxSize,
          builder: (ctx, _) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetDragRegion(
                  controller: _sheetController,
                  height: available,
                  minSize: minSize,
                  maxSize: _maxSize,
                  child: Column(
                    children: [
                      const SizedBox(height: 6),
                      _grabber(context),
                      const SizedBox(height: 12),
                      // 标题行：左边「跟不跟随助手」，右边四格。都放同一行，
                      // 输入区一点高度都不用让。
                      Row(
                        children: [
                          _followButton(context),
                          const SizedBox(width: 4),
                          Text(
                            '临时笔记',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: AppFontWeights.semibold,
                            ),
                          ),
                          const Spacer(),
                          for (var i = 0; i < _controllers.length; i++) ...[
                            if (i > 0) const SizedBox(width: 6),
                            _slotTab(context, i),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
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
                      key: ValueKey('conversation-note-input-$_slot'),
                      controller: _controllers[_slot],
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      style: textStyle,
                      onChanged: _handleChanged,
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: '第 ${_slot + 1} 格…',
                        hintStyle: textStyle.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.38),
                        ),
                      ),
                      cursorColor: cs.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
