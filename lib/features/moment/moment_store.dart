import '../../core/models/conversation.dart';
import '../../core/services/chat/chat_service.dart';
import 'moment_models.dart';

/// 朋友圈的全部数据都挂在一条例外的隐藏对话的 extras 里：
/// 这样备份、导出、恢复全都跟着现有那套走，不用动数据库结构。
/// 键名都带 moment. 前缀，不会被拼进任何提示词。
const String momentHiddenKey = 'moment.hidden';
const String momentPostsKey = 'moment.posts';
const String momentCharactersKey = 'moment.characters';
const String momentAssetsKey = 'moment.assets';

/// 当前「天意」是谁：评论区署名用这个名字。没有这个键 = 没开。
const String momentDivineKey = 'moment.divine';

/// 上次召唤过谁：评论区菜单里的「再叫一次 某某」用。没有这个键 = 没召唤过。
const String momentSummonKey = 'moment.summon';

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

Map<String, MomentAssets> momentAssetsFromExtras(Map<String, dynamic>? extras) {
  final raw = extras?[momentAssetsKey];
  if (raw is! Map) return const <String, MomentAssets>{};
  final out = <String, MomentAssets>{};
  raw.forEach((key, value) {
    final assets = MomentAssets.fromJson(value);
    if (assets != null) out[key.toString()] = assets;
  });
  return out;
}

Map<String, MomentAssets> momentAssetsOf(Conversation? conversation) =>
    momentAssetsFromExtras(conversation?.extras);

/// 现在开着天意的那个人。空字符串 = 没开。
String momentDivineFromExtras(Map<String, dynamic>? extras) =>
    (extras?[momentDivineKey] ?? '').toString().trim();

String momentDivineOf(Conversation? conversation) =>
    momentDivineFromExtras(conversation?.extras);

/// 上次召唤的人。空字符串 = 没召唤过。
String momentSummonFromExtras(Map<String, dynamic>? extras) =>
    (extras?[momentSummonKey] ?? '').toString().trim();

/// 找某个作者的两张图。作者名就是我自己时，用马甲那一份。
MomentAssets? momentAssetsForAuthor(
  Map<String, MomentAssets> assets,
  String author,
  String persona,
) {
  final name = author.trim();
  final me = persona.trim();
  if (me.isNotEmpty && name == me) {
    return assets[MomentAssets.personaKey];
  }
  return assets[name];
}

/// 最近 N 条帖子，按时间倒序（新的在前），刷新时拿去让模型补互动。
const int momentReactionWindow = 10;

/// 评论区一页显示多少条。超过这个数，界面上翻页看，数据一条都不丢。
const int momentCommentsPerPage = 10;

/// 朋友圈数据进出的唯一入口。
class MomentStore {
  MomentStore(this.chat);

  final ChatService chat;

  /// 找那条隐藏对话。
  ///
  /// 注意：会话列表那份是缓存过的旧对象，写入之后它不会自己更新，
  /// 所以这里一定要按 id 再取一次最新对象，否则页面会显示写之前的旧数据。
  Conversation? findConversation() {
    for (final conversation in chat.getAllConversations()) {
      if (!isMomentConversation(conversation)) continue;
      return chat.getConversation(conversation.id) ?? conversation;
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

  Map<String, MomentAssets> readAssets() => momentAssetsOf(findConversation());

  /// 跨场景记忆：扫朋友圈所有帖子，挑出 [name] 发过的动态和留过的评论，
  /// 返回 `朋友圈 · 内容` 的行，给社交上下文构建器用。
  /// [since] 是 [name] 的记忆水位线（毫秒）：这条时间之前发的动态/评论
  /// 不再当跨场景记忆喂给模型，让"删记录 = 角色忘了那一刻之前的事"生效。
  /// 评论没单独的时间戳，跟着所在动态走：动态早于水位线就整条跳过。
  /// 传 0（默认）不过滤。
  List<String> memoryLinesFor(String name, {int limit = 40, int since = 0}) {
    final posts = momentPostsOf(findConversation());
    final out = <String>[];
    for (final post in posts) {
      if (since > 0 &&
          post.createdAt.millisecondsSinceEpoch > 0 &&
          post.createdAt.millisecondsSinceEpoch < since) {
        continue;
      }
      if (!post.isMine && post.author.trim() == name && post.text.trim().isNotEmpty) {
        out.add('朋友圈：发了「${post.text}」');
        if (out.length >= limit) return out;
      }
      for (final comment in post.comments) {
        if (comment.author.trim() == name && comment.text.trim().isNotEmpty) {
          out.add('朋友圈：评论「${comment.text}」');
          if (out.length >= limit) return out;
        }
      }
    }
    return out;
  }

  /// 换掉某个角色（或马甲）的一张图；传 null 就是移除。
  Future<void> saveAssets(
    String key, {
    String? avatar,
    String? cover,
    bool clearAvatar = false,
    bool clearCover = false,
  }) async {
    final id = await ensureConversation();
    await chat.updateConversationExtras(id, (extras) {
      final current = momentAssetsFromExtras(extras);
      final existing = current[key] ?? const MomentAssets();
      final next = existing.copyWith(
        avatar: avatar,
        cover: cover,
        clearAvatar: clearAvatar,
        clearCover: clearCover,
      );
      final nextAssets = Map<String, MomentAssets>.from(current);
      if (next.avatar == null && next.cover == null) {
        nextAssets.remove(key);
      } else {
        nextAssets[key] = next;
      }
      final nextExtras = Map<String, dynamic>.from(extras);
      nextExtras[momentAssetsKey] = <String, dynamic>{
        for (final entry in nextAssets.entries) entry.key: entry.value.toJson(),
      };
      return nextExtras;
    });
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

  /// 开天意：传角色名。关天意：传 null。
  Future<void> setDivine(String? name) async {
    final clean = (name ?? '').trim();
    final id = await ensureConversation();
    await chat.updateConversationExtras(id, (extras) {
      final next = Map<String, dynamic>.from(extras);
      if (clean.isEmpty) {
        next.remove(momentDivineKey);
      } else {
        next[momentDivineKey] = clean;
      }
      return next;
    });
  }

  /// 上次召唤的人是谁，空 = 没召唤过。
  String summonName() => momentSummonFromExtras(findConversation()?.extras);

  /// 记一下这次召唤了谁，下次菜单里直接给「再叫一次」。
  Future<void> setSummon(String? name) async {
    final clean = (name ?? '').trim();
    final id = await ensureConversation();
    await chat.updateConversationExtras(id, (extras) {
      final next = Map<String, dynamic>.from(extras);
      if (clean.isEmpty) {
        next.remove(momentSummonKey);
      } else {
        next[momentSummonKey] = clean;
      }
      return next;
    });
  }

  /// 改帖子的统一入口：读出来、交给 [update]、整包写回去。
  Future<void> updatePosts(
    List<MomentPost> Function(List<MomentPost> posts) update,
  ) async {
    final id = await ensureConversation();
    await chat.updateConversationExtras(id, (extras) {
      final current = momentPostsFromExtras(extras);
      final nextPosts = update(current);
      final next = Map<String, dynamic>.from(extras);
      next[momentPostsKey] = nextPosts
          .map((p) => p.toJson())
          .toList(growable: false);
      return next;
    });
  }

  /// 一次刷新拿回来的整批：新帖追加，旧帖补互动，一次写完。
  Future<void> applyBatch(MomentBatch batch) async {
    if (batch.posts.isEmpty && batch.reactions.isEmpty) return;
    await updatePosts((posts) {
      final byId = <String, MomentPost>{
        for (final post in posts) post.id: post,
      };
      for (final reaction in batch.reactions) {
        final target = byId[reaction.postId];
        if (target == null) continue;
        final likes = <String>[...target.likes];
        for (final name in reaction.likes) {
          if (!likes.contains(name)) likes.add(name);
        }
        byId[reaction.postId] = target.copyWith(
          likes: likes,
          comments: <MomentComment>[...target.comments, ...reaction.comments],
        );
      }
      return <MomentPost>[
        for (final post in posts) byId[post.id] ?? post,
        ...batch.posts,
      ];
    });
  }

  /// 我自己发的一条。
  Future<void> addPost(MomentPost post) async {
    await updatePosts((posts) => <MomentPost>[...posts, post]);
  }

  /// 我点赞 / 取消点赞。
  Future<void> toggleLike(String postId, String personaName) async {
    final name = personaName.trim();
    if (name.isEmpty) return;
    await updatePosts((posts) {
      return <MomentPost>[
        for (final post in posts)
          if (post.id == postId)
            post.copyWith(
              likes: post.likes.contains(name)
                  ? (<String>[...post.likes]..remove(name))
                  : <String>[...post.likes, name],
            )
          else
            post,
      ];
    });
  }

  /// 我的评论（顺手挂上后面角色回我的那几条）。
  Future<void> addComments(String postId, List<MomentComment> comments) async {
    if (comments.isEmpty) return;
    await updatePosts((posts) {
      return <MomentPost>[
        for (final post in posts)
          if (post.id == postId)
            post.copyWith(
              comments: <MomentComment>[...post.comments, ...comments],
            )
          else
            post,
      ];
    });
  }

  /// 重写一条动态的正文，别的都不动。
  Future<void> updatePostText(String postId, String text) async {
    await updatePosts((posts) {
      return <MomentPost>[
        for (final post in posts)
          if (post.id == postId) post.copyWith(text: text) else post,
      ];
    });
  }

  Future<void> deletePost(String postId) async {
    await updatePosts(
      (posts) => <MomentPost>[
        for (final post in posts)
          if (post.id != postId) post,
      ],
    );
  }

  /// 重写某一条评论（按它在评论区里的位置定位）。
  Future<void> updateCommentText(String postId, int index, String text) async {
    await updatePosts((posts) {
      return <MomentPost>[
        for (final post in posts)
          if (post.id == postId)
            post.copyWith(comments: _replaceComment(post.comments, index, text))
          else
            post,
      ];
    });
  }

  Future<void> deleteComment(String postId, int index) async {
    await updatePosts((posts) {
      return <MomentPost>[
        for (final post in posts)
          if (post.id == postId)
            post.copyWith(
              comments: <MomentComment>[
                for (var i = 0; i < post.comments.length; i++)
                  if (i != index) post.comments[i],
              ],
            )
          else
            post,
      ];
    });
  }

  static List<MomentComment> _replaceComment(
    List<MomentComment> comments,
    int index,
    String text,
  ) {
    if (index < 0 || index >= comments.length) return comments;
    return <MomentComment>[
      for (var i = 0; i < comments.length; i++)
        if (i == index)
          MomentComment(
            author: comments[i].author,
            text: text,
            replyTo: comments[i].replyTo,
          )
        else
          comments[i],
    ];
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
