import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/models/conversation.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/design_tokens.dart';
import '../simulator_meta.dart';

/// The list of simulations. Every row is an ordinary conversation carrying the
/// simulator flag; picking one pops its id so the chat page can open it.
class SimulatorListPage extends StatelessWidget {
  const SimulatorListPage({super.key});

  Future<void> _create(BuildContext context) async {
    final chat = context.read<ChatService>();
    final assistant = context.read<AssistantProvider>().currentAssistant;
    final conversation = await chat.createConversation(
      title: '新的模拟器',
      assistantId: assistant?.id,
      activate: false,
    );
    await chat.updateConversationExtras(conversation.id, SimulatorMeta.mark);
    if (!context.mounted) return;
    Navigator.of(context).pop(conversation.id);
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatService>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final items = chat
        .getAllConversations()
        .where(SimulatorMeta.isSimulator)
        .toList();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('模拟器'),
        actions: [
          IconButton(
            tooltip: '新建',
            onPressed: () => _create(context),
            icon: Icon(Lucide.Plus, size: 20, color: cs.onSurface),
          ),
        ],
      ),
      body: items.isEmpty
          ? Center(
              child: Text(
                '还没有模拟器，右上角新建一个',
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface.withValues(alpha: 0.45),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.xs,
                AppSpacing.sm,
                AppSpacing.lg,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final conversation = items[index];
                return _SimulatorTile(
                  conversation: conversation,
                  turns: _turnCount(chat, conversation.id),
                  onOpen: () => Navigator.of(context).pop(conversation.id),
                  onConvert: () async {
                    await chat.updateConversationExtras(
                      conversation.id,
                      SimulatorMeta.unmark,
                    );
                    if (context.mounted) Navigator.of(context).maybePop();
                  },
                  onDelete: () async {
                    await chat.deleteConversation(conversation.id);
                  },
                );
              },
            ),
    );
  }

  int _turnCount(ChatService chat, String conversationId) {
    try {
      return chat
          .getMessages(conversationId)
          .where((message) => message.role == 'assistant')
          .length;
    } catch (_) {
      return 0;
    }
  }
}

class _SimulatorTile extends StatelessWidget {
  const _SimulatorTile({
    required this.conversation,
    required this.turns,
    required this.onOpen,
    required this.onConvert,
    required this.onDelete,
  });

  final Conversation conversation;
  final int turns;
  final VoidCallback onOpen;
  final VoidCallback onConvert;
  final VoidCallback onDelete;

  String get _subtitle {
    final stamp = conversation.updatedAt;
    final month = stamp.month;
    final day = stamp.day;
    final hour = stamp.hour.toString().padLeft(2, '0');
    final minute = stamp.minute.toString().padLeft(2, '0');
    return '第 $turns 回合 · $month 月 $day 日 $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  AppSpacing.sm,
                  AppSpacing.xs,
                  AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conversation.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(
              Lucide.MoreVertical,
              size: 18,
              color: cs.onSurface.withValues(alpha: 0.5),
            ),
            onSelected: (value) {
              if (value == 'convert') onConvert();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(value: 'convert', child: Text('转为普通对话')),
              PopupMenuItem<String>(value: 'delete', child: Text('删除')),
            ],
          ),
        ],
      ),
    );
  }
}
