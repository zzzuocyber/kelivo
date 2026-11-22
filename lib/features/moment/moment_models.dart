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
    this.heartVoice = '',
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

  /// 这条动态生成时一并存下的心声。空 = 没有（角色没开心声或是我发的）。
  final String heartVoice;

  MomentPost copyWith({
    String? id,
    String? author,
    DateTime? createdAt,
    String? text,
    bool? hasImage,
    bool? isMine,
    List<String>? likes,
    List<MomentComment>? comments,
    String? heartVoice,
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
      heartVoice: heartVoice ?? this.heartVoice,
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
    if (heartVoice.isNotEmpty) 'heart': heartVoice,
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
      heartVoice: (raw['heart'] ?? '').toString(),
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

/// 一个角色（或我的马甲）的两张图：头像 + 背景。
/// 只存文件路径，图本身放在 Kelivo 的 avatars 目录，
/// 也就是图片页里的「头像与背景」分类，删图后这里会读不到文件自动退回。
class MomentAssets {
  const MomentAssets({this.avatar, this.cover});

  /// 马甲用这个键，角色用角色名。
  static const String personaKey = '@me';

  final String? avatar;
  final String? cover;

  MomentAssets copyWith({
    String? avatar,
    String? cover,
    bool clearAvatar = false,
    bool clearCover = false,
  }) {
    return MomentAssets(
      avatar: clearAvatar ? null : (avatar ?? this.avatar),
      cover: clearCover ? null : (cover ?? this.cover),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (avatar != null && avatar!.isNotEmpty) 'avatar': avatar,
    if (cover != null && cover!.isNotEmpty) 'cover': cover,
  };

  static MomentAssets? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final avatar = (raw['avatar'] ?? '').toString().trim();
    final cover = (raw['cover'] ?? '').toString().trim();
    if (avatar.isEmpty && cover.isEmpty) return null;
    return MomentAssets(
      avatar: avatar.isEmpty ? null : avatar,
      cover: cover.isEmpty ? null : cover,
    );
  }
}
