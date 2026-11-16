import 'dart:convert';

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

/// 清空一个对话里的图片。
///
/// 分两类：
///   聊天图片 = 消息内容里的图片片段，你发的和 AI 生成的
///   工具图片 = 工具卡片元数据里的图片地址，工具返回的和浏览器缩略图
///
/// 只摘掉图片本身，消息、正文、工具卡片全部保留。磁盘上的文件不动。
class ConversationImagePurger {
  const ConversationImagePurger(this._chat);

  final ChatService _chat;

  /// 聊天图片张数。只读操作。
  Future<int> countChatImages(String conversationId) async {
    final messages = await _chat.loadMessages(conversationId);
    var total = 0;
    for (final message in messages) {
      for (final part in message.parts) {
        if (part is ImagePart) total++;
      }
    }
    return total;
  }

  /// 工具图片张数。只读操作。
  Future<int> countToolImages(String conversationId) async {
    final messages = await _chat.loadMessages(conversationId);
    var total = 0;
    for (final message in messages) {
      for (final part in message.parts) {
        if (part is! ToolCallPart) continue;
        total += _stripToolPayload(part.payloadJson)?.removedImages ?? 0;
      }
    }
    return total;
  }

  /// 清空聊天图片：去掉消息内容里的图片片段。
  Future<ConversationImagePurgeResult> purgeChatImages(
    String conversationId,
  ) async {
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

  /// 清空工具图片：去掉工具卡片元数据里的图片地址。
  Future<ConversationImagePurgeResult> purgeToolImages(
    String conversationId,
  ) async {
    final messages = await _chat.loadMessages(conversationId);
    var removed = 0;
    var changed = 0;
    var skipped = 0;
    for (final message in messages) {
      if (message.isStreaming) {
        final pending = message.parts.any(
          (part) =>
              part is ToolCallPart &&
              (_stripToolPayload(part.payloadJson)?.removedImages ?? 0) > 0,
        );
        if (pending) skipped++;
        continue;
      }
      final parts = <MessagePart>[];
      var messageRemoved = 0;
      for (final part in message.parts) {
        if (part is ToolCallPart) {
          final stripped = _stripToolPayload(part.payloadJson);
          if (stripped != null && stripped.removedImages > 0) {
            messageRemoved += stripped.removedImages;
            parts.add(ToolCallPart(stripped.payload));
            continue;
          }
        }
        parts.add(part);
      }
      if (messageRemoved == 0) continue;
      removed += messageRemoved;
      changed++;
      await _chat.updateMessage(message.id, parts: parts);
    }
    return ConversationImagePurgeResult(
      removedImages: removed,
      changedMessages: changed,
      skippedStreamingMessages: skipped,
    );
  }

  static _StrippedToolPayload? _stripToolPayload(String payloadJson) {
    if (!payloadJson.contains('imageUris') &&
        !payloadJson.contains('chatImage') &&
        !payloadJson.contains('previewImage')) {
      return null;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(payloadJson);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final payload = Map<String, dynamic>.from(decoded);
    final metadataRaw = payload['metadata'];
    if (metadataRaw is! Map) return null;
    final metadata = Map<String, dynamic>.from(metadataRaw);

    var removed = 0;
    final mcpRaw = metadata['mcpResult'];
    if (mcpRaw is Map) {
      final mcp = Map<String, dynamic>.from(mcpRaw);
      final uris = mcp['imageUris'];
      if (uris is List && uris.isNotEmpty) {
        removed += uris.length;
        mcp['imageUris'] = const <String>[];
        metadata['mcpResult'] = mcp;
      }
    }
    if (metadata.containsKey('chatImage')) {
      metadata.remove('chatImage');
      removed += 1;
    }
    final browserRaw = metadata['browser'];
    if (browserRaw is Map && browserRaw.containsKey('previewImage')) {
      final browser = Map<String, dynamic>.from(browserRaw)
        ..remove('previewImage');
      metadata['browser'] = browser;
      removed += 1;
    }
    if (removed == 0) return null;
    payload['metadata'] = metadata;
    return _StrippedToolPayload(
      removedImages: removed,
      payload: jsonEncode(payload),
    );
  }
}

class _StrippedToolPayload {
  const _StrippedToolPayload({
    required this.removedImages,
    required this.payload,
  });

  final int removedImages;
  final String payload;
}
