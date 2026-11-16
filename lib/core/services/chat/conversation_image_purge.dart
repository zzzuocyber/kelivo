import '../../models/message_part.dart';
import 'chat_service.dart';

/// 一次「清空图片」的结果。
class ConversationImagePurgeResult {
  const ConversationImagePurgeResult({
    required this.removedImages,
    required this.changedMessages,
    required this.skippedStreamingMessages,
  });

  /// 实际删掉的图片张数。
  final int removedImages;

  /// 被改动的消息条数。
  final int changedMessages;

  /// 因为还在生成而跳过的消息条数。
  final int skippedStreamingMessages;

  bool get isEmpty => removedImages == 0;
}

/// 清空一个对话里的全部图片。
///
/// 只把消息内容里的图片片段摘掉，消息本身、文字、工具卡片全部保留。
/// 磁盘上的图片文件不动，避免误删被别处引用的文件。
class ConversationImagePurger {
  const ConversationImagePurger(this._chat);

  final ChatService _chat;

  /// 统计对话里有多少张图片。只读操作。
  Future<int> countImages(String conversationId) async {
    final messages = await _chat.loadMessages(conversationId);
    var total = 0;
    for (final message in messages) {
      for (final part in message.parts) {
        if (part is ImagePart) total++;
      }
    }
    return total;
  }

  /// 删掉对话里的全部图片。
  Future<ConversationImagePurgeResult> purge(String conversationId) async {
    final messages = await _chat.loadMessages(conversationId);
    var removed = 0;
    var changed = 0;
    var skipped = 0;
    for (final message in messages) {
      final parts = message.parts;
      final hasImage = parts.any((part) => part is ImagePart);
      if (!hasImage) continue;
      if (message.isStreaming) {
        // 正在生成的消息先跳过，避免和流式写入互相覆盖。
        skipped++;
        continue;
      }
      final kept = <MessagePart>[
        for (final part in parts)
          if (part is! ImagePart) part,
      ];
      removed += parts.length - kept.length;
      changed++;
      await _chat.updateMessage(message.id, parts: kept);
    }
    return ConversationImagePurgeResult(
      removedImages: removed,
      changedMessages: changed,
      skippedStreamingMessages: skipped,
    );
  }
}
