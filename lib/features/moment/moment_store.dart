import '../../core/models/conversation.dart';
import '../../core/services/chat/chat_service.dart';
import 'moment_models.dart';

/// 朋友圈的全部数据都挂在一条例外的隐藏对话的 extras 里：
/// 这样备份、导出、恢复全都跟着现有那套走，不用动数据库结构。
/// 键名都带 moment. 前缀，不会被拼进任何提示词。
const String momentHiddenKey = 'moment.hidden';
const String momentPostsKey = 'moment.posts';
const String momentCharactersKey = 'moment.characters';

/// 隐藏对话的标题，只在备份/导出里可见。
const String momentFeedTitle = '朋友圈';

bool isMomentConversation(Conversation conversation) =>
    conversation.extras[momentHiddenKey] == true;

List<MomentCharacter> momentCharactersFromExtras(Map<String, dynamic>? extras) {
  final raw = extras?[momentCharactersKey];
  if (raw is! List) return const <MomentCharacter>[];
  final out = <MomentCharacter>[];
  for (final item in raw) {
    final character = MomentCharacter.fromJson(item);
    if (character != null) out.add(character);
  }
  return out;
}

List<MomentPost> momentPostsFromExtras(Map<String, dynamic>? extras) {
  final raw = extras?[momentPostsKey];
  if (raw is! List) return const <MomentPost>[];
  final out = <MomentPost>[];
  for (final item in raw) {
    final post = MomentPost.fromJson(item);
    if (post != null) out.add(post);
  }
  return out;
}

List<MomentCharacter> momentCharactersOf(Conversation? conversation) =>
    momentCharactersFromExtras(conversation?.extras);

List<MomentPost> momentPostsOf(Conversation? conversation) =>
    momentPostsFromExtras(conversation?.extras);

/// 朋友圈数据进出的唯一入口。
class MomentStore {
  MomentStore(this.chat);

  final ChatService chat;

  Conversation? findConversation() {
    for (final conversation in chat.getAllConversations()) {
      if (isMomentConversation(conversation)) return conversation;
    }
    return null;
  }

  /// 拿隐藏对话的 id，第一次用时创建出来。
  Future<String> ensureConversation() async {
    final existing = findConversation();
    if (existing != null) return existing.id;
    final created = await chat.createConversation(
      title: momentFeedTitle,
      activate: false,
    );
    try {
      await chat.updateConversationExtras(created.id, (extras) {
        final next = Map<String, dynamic>.from(extras);
        next[momentHiddenKey] = true;
        return next;
      });
    } catch (_) {
      // 标记没写进去也还能用，只是列表里会露出来。
    }
    return created.id;
  }

  Future<void> saveCharacters(List<MomentCharacter> characters) async {
    final id = await ensureConversation();
    await chat.updateConversationExtras(id, (extras) {
      final next = Map<String, dynamic>.from(extras);
      next[momentCharactersKey] = characters
          .map((c) => c.toJson())
          .toList(growable: false);
      return next;
    });
  }

  Future<void> appendPosts(List<MomentPost> incoming) async {
    if (incoming.isEmpty) return;
    final id = await ensureConversation();
    await chat.updateConversationExtras(id, (extras) {
      final next = Map<String, dynamic>.from(extras);
      final existing = momentPostsFromExtras(extras);
      next[momentPostsKey] = <Map<String, dynamic>>[
        ...existing.map((p) => p.toJson()),
        ...incoming.map((p) => p.toJson()),
      ];
      return next;
    });
  }

  Future<void> clearPosts() async {
    final existing = findConversation();
    if (existing == null) return;
    await chat.updateConversationExtras(existing.id, (extras) {
      final next = Map<String, dynamic>.from(extras);
      next.remove(momentPostsKey);
      return next;
    });
  }
}
