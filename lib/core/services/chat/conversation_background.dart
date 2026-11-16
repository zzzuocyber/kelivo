import 'dart:io';

import '../../models/conversation.dart';
import '../../utils/app_directories.dart';
import 'chat_service.dart';

/// 对话级背景图。
///
/// 存在对话的扩展字段里：
///   background.path = 本地图片路径
///   background.mode = custom 或 assistant
///
/// 两个键都没有，或者 mode 是 assistant，就表示「跟随助手背景」。
class ConversationBackground {
  const ConversationBackground._();

  static const String pathKey = 'background.path';
  static const String modeKey = 'background.mode';
  static const String modeCustom = 'custom';
  static const String modeAssistant = 'assistant';

  /// 对话自己指定的背景图。返回 null 表示跟随助手。
  static String? pathOf(Conversation? conversation) =>
      pathFromExtras(conversation?.extras);

  static String? pathFromExtras(Map<String, dynamic>? extras) {
    if (extras == null) return null;
    if (extras[modeKey] == modeAssistant) return null;
    final raw = extras[pathKey];
    if (raw is! String) return null;
    final path = raw.trim();
    return path.isEmpty ? null : path;
  }

  static bool followsAssistant(Conversation? conversation) =>
      pathOf(conversation) == null;

  /// 只删除 App 自己管理的图片，外部路径一律不碰。
  static Future<void> deleteManagedFile(String? path) async {
    final raw = (path ?? '').trim();
    if (raw.isEmpty) return;
    try {
      final directory = await AppDirectories.getImagesDirectory();
      if (!raw.startsWith(directory.path)) return;
      final file = File(raw);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

/// 给某个对话设置 / 清除背景图，并负责图片文件的新建与清理。
class ConversationBackgroundService {
  const ConversationBackgroundService(this._chat);

  final ChatService _chat;

  /// 用一张本地图片作为该对话的背景。
  ///
  /// 图片会复制到 App 私有目录；对话原来那张自定义图会被删除。
  Future<void> setImage(String conversationId, String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) return;
    final directory = await AppDirectories.getImagesDirectory();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final target = File(
      '${directory.path}/conversation_background_'
      '${_safeId(conversationId)}_$stamp${_extensionOf(sourcePath)}',
    );
    await source.copy(target.path);
    final previous = ConversationBackground.pathOf(
      _chat.getConversation(conversationId),
    );
    await _chat.updateConversationExtras(conversationId, (current) {
      return <String, dynamic>{
        ...current,
        ConversationBackground.pathKey: target.path,
        ConversationBackground.modeKey: ConversationBackground.modeCustom,
      };
    });
    if (previous != target.path) {
      await ConversationBackground.deleteManagedFile(previous);
    }
  }

  /// 删除该对话的自定义背景，回到跟随助手。图片文件一起删掉。
  Future<void> clear(String conversationId) async {
    final previous = ConversationBackground.pathOf(
      _chat.getConversation(conversationId),
    );
    await _chat.updateConversationExtras(conversationId, (current) {
      final next = Map<String, dynamic>.of(current)
        ..remove(ConversationBackground.pathKey)
        ..[ConversationBackground.modeKey] =
            ConversationBackground.modeAssistant;
      return next;
    });
    await ConversationBackground.deleteManagedFile(previous);
  }

  static String _safeId(String id) {
    final buffer = StringBuffer();
    for (final rune in id.runes) {
      final character = String.fromCharCode(rune);
      if (RegExp(r'[A-Za-z0-9_-]').hasMatch(character)) {
        buffer.write(character);
      }
    }
    final text = buffer.toString();
    return text.isEmpty ? 'conversation' : text;
  }

  static String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot <= 0 || dot == path.length - 1) return '.jpg';
    final extension = path.substring(dot).toLowerCase();
    if (extension.length > 6) return '.jpg';
    for (final character in extension.substring(1).split('')) {
      if (!RegExp(r'[a-z0-9]').hasMatch(character)) return '.jpg';
    }
    return extension;
  }
}
