import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models/assistant.dart';
import '../../core/models/chat_message.dart';
import '../../core/models/message_part.dart';
import '../../core/providers/assistant_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/world_book_provider.dart';
import '../chat/widgets/chat_message_widget.dart';
import '../wechat/wechat_service.dart' show WechatServiceException;
import 'group_chat_models.dart';
import 'group_chat_service.dart';

/// 助手「群聊模式」的聊天页。
///
/// 气泡直接复用主界面原生 ChatMessageWidget，一个字不改。
/// 消息只存在于本页内存（不落库、不进主消息列表），退出即散——
/// 这样完全不碰数据库和主聊天链路，最安全、最容易回退。
class GroupChatPage extends StatefulWidget {
  const GroupChatPage({super.key, required this.assistantId});

  final String assistantId;

  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<ChatMessage> _messages = <ChatMessage>[];
  final Map<String, GroupChatMember> _speakers = <String, GroupChatMember>{};

  bool _busy = false;
  String? _error;
  int _lastSpeakerIndex = -1;

  Assistant get _assistant =>
      context.read<AssistantProvider>().getById(widget.assistantId)!;
  GroupChatConfig get _config => _assistant.groupChat;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _addUser(String text) {
    setState(() {
      _messages.add(
        ChatMessage(
          role: 'user',
          content: text,
          parts: <MessagePart>[TextPart(text)],
          conversationId: 'group-${widget.assistantId}',
        ),
      );
    });
  }

  void _addSpeak(GroupChatTurn turn) {
    final msg = ChatMessage(
      role: 'assistant',
      content: turn.text,
      parts: <MessagePart>[TextPart(turn.text)],
      conversationId: 'group-${widget.assistantId}',
      providerId: turn.member.providerKey,
      modelId: turn.member.modelId,
    );
    setState(() {
      _speakers[msg.id] = turn.member;
      _messages.add(msg);
      _lastSpeakerIndex = _config.members.indexWhere(
        (m) => m.name == turn.member.name,
      );
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    final config = _config;
    if (!config.enabled || config.members.isEmpty) {
      setState(() => _error = '还没开启群聊或没选角色');
      return;
    }
    _input.clear();
    setState(() {
      _error = null;
      _busy = true;
    });
    _addUser(text);
    _scrollToBottom();

    final service = GroupChatService(
      settings: context.read<SettingsProvider>(),
      worldBooks: context.read<WorldBookProvider>(),
      config: config,
      assistantName: _assistant.name,
      fallbackProviderKey: _assistant.chatModelProvider,
      fallbackModelId: _assistant.chatModelId,
    );

    final history = <String>[
      for (final m in _messages.where((m) => m.role == 'assistant'))
        '${_speakers[m.id]?.name ?? _assistant.name}：${m.content}',
    ];

    try {
      // 第一步：轮流/随机挑一个人先回主人这句。
      var speaker = service.pickFirst(afterIndex: _lastSpeakerIndex);
      if (speaker == null) throw const WechatServiceException('empty');
      var relay = 0;
      while (speaker != null && relay < config.maxRelay) {
        final turn = await service.speak(
          speaker,
          userText: text,
          historyLines: List<String>.from(history),
        );
        _addSpeak(turn);
        _scrollToBottom();
        history.add('${turn.member.name}：${turn.text}');

        // 第二步：这句话 @ 了谁，就叫谁接着说（@ 接力）。
        final mentioned = service.mentionsIn(turn.text, turn.member);
        if (mentioned.isEmpty) break;
        speaker = mentioned.first;
        relay++;
      }
    } on WechatServiceException catch (e) {
      setState(() => _error = e.code == 'model_missing' ? '没有可用的模型' : '生成失败');
    } catch (_) {
      setState(() => _error = '生成失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final config = _config;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_assistant.name),
            Text(
              '群聊 · ${config.members.length} 个角色 · ${config.mode == GroupChatMode.round ? '轮流' : '随机'}',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '群聊设置',
            icon: const Icon(Icons.group_settings_outlined),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              color: cs.errorContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(_error!, style: TextStyle(color: cs.onErrorContainer)),
            ),
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        '这是「${_assistant.name}」的群聊。\n发一句话，群里的角色会轮流回你；\n它在话里 @ 谁，谁就接着说。',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurfaceVariant, height: 1.6),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final member = _speakers[msg.id];
                      return ChatMessageWidget(
                        message: msg,
                        useAssistantAvatar: msg.role == 'assistant',
                        useAssistantName: msg.role == 'assistant',
                        assistantName: member?.name,
                        assistantAvatar: (member?.avatar ?? '').isEmpty
                            ? null
                            : member!.avatar,
                        showModelIcon: false,
                        showTokenStats: false,
                        showUserAvatar: true,
                        enableStreamingTextMotion: false,
                        // 群聊消息不需要单聊那些操作，给空实现避免点按时解引用 null。
                        onCopy: () {},
                        onRegenerate: () {},
                        onResend: () {},
                        onMore: () {},
                        onEdit: () {},
                        onDelete: () {},
                        onSpeak: () {},
                        onTranslate: () {},
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: '说点什么，喊大家一起聊…',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy ? null : _send,
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
