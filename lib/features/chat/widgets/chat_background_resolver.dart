import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/assistant_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/chat/conversation_background.dart';

/// 当前生效的聊天背景图路径。
///
/// 顺序：对话自定义图 → 助手背景图 → 空字符串。
///
/// 预览页（消息画廊、样式预览）里不一定有 ChatService，
/// 所以这里对它的读取做了容错，取不到就回落到助手背景。
String resolveChatBackgroundPath(BuildContext context) {
  String? conversationPath;
  try {
    conversationPath = context.select<ChatService, String?>((chat) {
      final id = chat.currentConversationId;
      if (id == null) return null;
      return ConversationBackground.pathOf(chat.getConversation(id));
    });
  } catch (_) {
    conversationPath = null;
  }
  if (conversationPath != null) return conversationPath;
  final assistantPath = context.select<AssistantProvider, String?>(
    (p) => (p.currentAssistant?.background ?? '').trim(),
  );
  return (assistantPath ?? '').trim();
}
