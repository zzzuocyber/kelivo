import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/database/business_preferences.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../theme/chat_bubble_style.dart';
import '../../chat/utils/ensure_conversation.dart';
import '../../chat/widgets/frosted/frosted_surface.dart';
import 'conversation_note_editor.dart';

/// 「临时笔记」入口，跟「对话系统提示词」并排放在页脚。
class ConversationNoteButton extends StatelessWidget {
  const ConversationNoteButton({
    super.key,
    this.conversationId,
    this.assistantId,
    this.backgroundImageActive = false,
  });

  final String? conversationId;
  final String? assistantId;
  final bool backgroundImageActive;

  @override
  Widget build(BuildContext context) {
    final prefs = context.read<BusinessPreferences>();
    final hasNote = context.select<ChatService, bool>((chat) {
      final extras =
          chat.getConversation(conversationId ?? '')?.extras ?? const {};
      if (conversationNoteText(extras).trim().isNotEmpty) return true;
      // 跟随助手时笔记存在助手那边，这个对话自己是空的。
      if (!conversationNoteFollowsAssistant(extras)) return false;
      final id = assistantId ?? '';
      if (id.isEmpty) return false;
      return readAssistantNotes(
        prefs,
        id,
      ).any((text) => text.trim().isNotEmpty);
    });
    final cs = Theme.of(context).colorScheme;
    final color = hasNote ? cs.primary : cs.onSurfaceVariant;
    const borderRadius = BorderRadius.all(Radius.circular(10));
    Widget button = IosCardPress(
      key: const ValueKey('conversation-note-button'),
      baseColor: Colors.transparent,
      borderRadius: borderRadius,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      onTap: () async {
        final id = await ensureConversationId(
          context,
          conversationId: conversationId,
          assistantId: assistantId,
        );
        if (id == null || !context.mounted) return;
        await editConversationNote(context, conversationId: id);
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Lucide.NotebookTabs, size: 14, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '临时笔记',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: color),
            ),
          ),
          if (hasNote) ...[
            const SizedBox(width: 5),
            Icon(Lucide.Check, size: 13, color: color),
          ],
        ],
      ),
    );
    if (backgroundImageActive) {
      button = FrostedSurface(
        style: ResolvedBubbleStyle(
          background: cs.surface.withValues(alpha: 0.10),
          border: Colors.transparent,
          text: color,
          borderWidth: 0,
          radius: 10,
          blurSigma: 3,
        ),
        borderRadius: borderRadius,
        child: button,
      );
    }
    return button;
  }
}
