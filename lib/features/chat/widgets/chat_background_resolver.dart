import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/assistant_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/chat/conversation_background.dart';
import '../../simulator/simulator_meta.dart';

/// 当前生效的聊天背景图路径。
///
/// 顺序：对话自定义图 → 助手背景图 → 空字符串。
///
/// 预览页（消息画廊、样式预览）里不一定有 ChatService，
/// 所以这里对它的读取做了容错，取不到就回落到助手背景。
///
/// 模拟器里一律返回空：模拟器的正文是一页文档，先不支持任何背景图。
String resolveChatBackgroundPath(BuildContext context) {
  String? conversationPath;
  bool simulator = false;
  try {
    final current = context.select<ChatService, ({String? path, bool sim})>((
      chat,
    ) {
      final id = chat.currentConversationId;
      final conversation = id == null ? null : chat.getConversation(id);
      return (
        path: conversation == null
            ? null
            : ConversationBackground.pathOf(conversation),
        sim: SimulatorMeta.isSimulator(conversation),
      );
    });
    conversationPath = current.path;
    simulator = current.sim;
  } catch (_) {
    conversationPath = null;
  }
  if (simulator) return '';
  if (conversationPath != null) return conversationPath;
  final assistantPath = context.select<AssistantProvider, String?>(
    (p) => (p.currentAssistant?.background ?? '').trim(),
  );
  return (assistantPath ?? '').trim();
}
