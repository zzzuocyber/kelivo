import 'dart:math';

/// 朋友圈里「加进去」的一个角色。
///
/// 只记名字和它对应的世界书条目 id，人设正文在生成时才去世界书里现取，
/// 所以改了世界书的内容马上生效，不用重新加一遍。
class MomentCharacter {
  const MomentCharacter({required this.name, required this.entryId});

  final String name;
  final String entryId;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'entryId': entryId,
  };

  static MomentCharacter? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final name = (raw['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;
    return MomentCharacter(
      name: name,
      entryId: (raw['entryId'] ?? '').toString(),
    );
  }
}

class MomentComment {
  const MomentComment({required this.author, required this.text, this.replyTo});

  final String author;
  final String text;

  /// 这条是「回谁」的。角色回我的评论时填我的马甲名。
  final String? replyTo;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'author': author,
    'text': text,
    if (replyTo != null && replyTo!.isNotEmpty) 'replyTo': replyTo,
  };

  static MomentComment? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final author = (raw['author'] ?? '').toString().trim();
    final text = (raw['text'] ?? '').toString().trim();
    if (author.isEmpty || text.isEmpty) return null;
    final replyTo = (raw['replyTo'] ?? '').toString().trim();
    return MomentComment(
      author: author,
      text: text,
      replyTo: replyTo.isEmpty ? null : replyTo,
    );
  }
}

class MomentPost {
  const MomentPost({
    required this.id,
    required this.author,
    required this.createdAt,
    required this.text,
    this.hasImage = false,
    this.isMine = false,
    this.likes = const <String>[],
    this.comments = const <MomentComment>[],
  });

  final String id;
  final String author;
  final DateTime createdAt;
  final String text;

  /// 这条是不是「带图」的。图先不接生图接口，显示占位图。
  final bool hasImage;

  /// 我自己发的（马甲），跟角色区分开。
  final bool isMine;
  final List<String> likes;
  final List<MomentComment> comments;

  MomentPost copyWith({
    String? id,
    String? author,
    DateTime? createdAt,
    String? text,
    bool? hasImage,
    bool? isMine,
    List<String>? likes,
    List<MomentComment>? comments,
  }) {
    return MomentPost(
      id: id ?? this.id,
      author: author ?? this.author,
      createdAt: createdAt ?? this.createdAt,
      text: text ?? this.text,
      hasImage: hasImage ?? this.hasImage,
      isMine: isMine ?? this.isMine,
      likes: likes ?? this.likes,
      comments: comments ?? this.comments,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'author': author,
    'at': createdAt.microsecondsSinceEpoch,
    'text': text,
    'image': hasImage,
    'mine': isMine,
    'likes': likes,
    'comments': comments.map((c) => c.toJson()).toList(growable: false),
  };

  static MomentPost? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final author = (raw['author'] ?? '').toString().trim();
    final text = (raw['text'] ?? '').toString().trim();
    if (author.isEmpty || text.isEmpty) return null;
    final at = raw['at'];
    final createdAt = at is int
        ? DateTime.fromMicrosecondsSinceEpoch(at)
        : DateTime.now();
    final rawLikes = raw['likes'];
    final likes = rawLikes is List
        ? rawLikes
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    final rawComments = raw['comments'];
    final comments = rawComments is List
        ? rawComments
              .map(MomentComment.fromJson)
              .whereType<MomentComment>()
              .toList(growable: false)
        : const <MomentComment>[];
    return MomentPost(
      id: (raw['id'] ?? '').toString(),
      author: author,
      createdAt: createdAt,
      text: text,
      hasImage: raw['image'] == true,
      isMine: raw['mine'] == true,
      likes: likes,
      comments: comments,
    );
  }
}

/// 模型给某条旧帖补的互动。
class MomentReaction {
  const MomentReaction({
    required this.postId,
    this.likes = const <String>[],
    this.comments = const <MomentComment>[],
  });

  final String postId;
  final List<String> likes;
  final List<MomentComment> comments;
}

/// 一次刷新拿回来的整批东西：新帖 + 给旧帖补的互动。
class MomentBatch {
  const MomentBatch({
    this.posts = const <MomentPost>[],
    this.reactions = const <MomentReaction>[],
  });

  final List<MomentPost> posts;
  final List<MomentReaction> reactions;
}

/// 帖子 id 只要页面内不撞车就行，不上数据库也不用保证全局唯一。
String newMomentPostId() {
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final salt = Random().nextInt(1 << 20);
  return '$stamp-$salt';
}
