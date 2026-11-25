import 'dart:convert';
import 'dart:math';

import '../../core/models/model_spec.dart';
import '../../core/models/reasoning_request.dart';
import '../../core/models/world_book.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/world_book_provider.dart';
import '../../core/services/api/chat_api_service.dart';
import 'moment_models.dart';
import 'moment_service_exception.dart';

export 'moment_service_exception.dart';

/// 一次刷新生成的帖子条数。
const int momentBatchSize = 5;

/// 把选中的多本世界书取出来，跳过已经被删掉的。
List<WorldBook> momentBooks(WorldBookProvider provider, List<String> ids) {
  final out = <WorldBook>[];
  for (final id in ids) {
    final book = provider.getById(id);
    if (book != null) out.add(book);
  }
  return out;
}

/// 一次生成最多等多久。卡住就报错，不让刷新按钮无限挂着。
const Duration momentRequestTimeout = Duration(seconds: 150);

/// 让人回我一句时最多等多久。
const Duration momentReplyTimeout = Duration(seconds: 60);

/// 默认系统提示词，用户可以在朋友圈设置里改。
const String defaultMomentSystemPrompt = '''你在替一组虚构角色经营他们的朋友圈。
你要按照每个角色自己的人设和世界观，假装他们是真人，随手发一条生活动态，并让其他角色点赞、评论。
语气、用词、关心的东西都要贴合各自的身份，不要写成小说旁白，不要解释设定，不要提你是模型。
朋友圈本来就是不均匀的：有的帖子热闹，有的没人理；有的只有一句话，有的写得很长。
只输出要求的 JSON，不要任何多余的话。''';

/// 一次刷新要干的两件事：发新帖，顺带给旧帖补点赞评论。
class MomentGenerator {
  const MomentGenerator({
    required this.settings,
    required this.worldBooks,
    required this.bookIds,
    required this.characters,
    required this.personaName,
    required this.recentPosts,
    this.contextCharLimit = 0,
    this.batchSize = momentBatchSize,
    this.socialContext = '',
  });

  final SettingsProvider settings;
  final WorldBookProvider worldBooks;
  final List<String> bookIds;
  final List<MomentCharacter> characters;

  /// 我的马甲名，只用来在提示词里点明「这是我」。
  final String personaName;

  /// 旧帖，用来让模型给它们补互动。
  final List<MomentPost> recentPosts;

  /// 喂多少字的旧帖内容。0 = 不限制，全给。
  final int contextCharLimit;
  final int batchSize;

  /// 跨场景记忆 + 此刻处境，注入到 system 末尾。
  final String socialContext;

  Future<MomentBatch> generate() async {
    if (characters.isEmpty) {
      throw const MomentServiceException('no_characters');
    }
    final books = momentBooks(worldBooks, bookIds);
    if (books.isEmpty) {
      throw const MomentServiceException('no_book');
    }
    final names = <String>[for (final c in characters) c.name];
    final profiles = _collectProfiles(books, characters);
    final model = _resolveModel(settings);
    var system = _systemText(settings);
    final extra = socialContext.trim();
    if (extra.isNotEmpty) {
      system = '$system\n\n【此刻的处境与别处记忆】\n$extra';
    }
    final prompt = buildUserPrompt(
      profiles: profiles,
      names: names,
      personaName: personaName,
      oldPosts: recentPosts,
      count: batchSize,
      charLimit: contextCharLimit,
    );

    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final result = await ChatApiService.generateMessage(
          config: model.config,
          modelId: model.modelId,
          messages: <Map<String, dynamic>>[
            <String, dynamic>{'role': 'system', 'content': system},
            <String, dynamic>{'role': 'user', 'content': prompt},
          ],
          // 只取文字，不折腾识图、不跑内置工具。
          builtInToolMode: BuiltInToolMode.none,
          skipImageParsing: true,
          textOnly: true,
          reasoning: ReasoningRequest(settings.momentReasoning),
          requestTimeout: momentRequestTimeout,
        );
        final batch = parseBatch(
          result.text,
          names: names,
          limit: batchSize,
          oldPosts: recentPosts,
        );
        if (batch.posts.isEmpty) {
          lastError = const MomentServiceException('parse_failed');
          continue;
        }
        return MomentBatch(
          posts: _stamp(_shapeInteractions(batch.posts)),
          reactions: batch.reactions,
        );
      } catch (error) {
        lastError = error;
      }
    }
    if (lastError is MomentServiceException) throw lastError;
    throw MomentServiceException(
      'request_failed',
      detail: lastError?.toString(),
    );
  }

  /// 把模型吐出来的文本解析成一批。
  static MomentBatch parseBatch(
    String raw, {
    required List<String> names,
    required int limit,
    required List<MomentPost> oldPosts,
  }) {
    final decoded = _decodePayload(raw);
    if (decoded is List) {
      return MomentBatch(
        posts: _parsePosts(decoded, names: names, limit: limit),
      );
    }
    if (decoded is! Map) return const MomentBatch();
    final rawPosts = decoded['posts'];
    final posts = _parsePosts(rawPosts, names: names, limit: limit);
    final reactions = <MomentReaction>[];
    final rawReactions = decoded['reactions'];
    if (rawReactions is List) {
      for (final item in rawReactions) {
        if (item is! Map) continue;
        final index = item['index'];
        final position = index is int ? index : int.tryParse(index.toString());
        if (position == null || position < 1 || position > oldPosts.length) {
          continue;
        }
        final target = oldPosts[position - 1];
        final reaction = _parseReaction(item, names, target);
        if (reaction != null) reactions.add(reaction);
      }
    }
    return MomentBatch(posts: posts, reactions: reactions);
  }

  /// 评论链：一条条可以接着上面的人聊，也可以谁都不指、直接评帖子。
  /// replyTo 只能指向名单里的人、帖子作者，或者外面另外允许的名字。
  static List<MomentComment> _parseCommentChain({
    required dynamic rawComments,
    required Set<String> known,
    required String fallbackReplyTo,
    required int limit,
  }) {
    final out = <MomentComment>[];
    if (rawComments is! List) return out;
    for (final item in rawComments) {
      if (item is! Map) continue;
      final author = (item['author'] ?? '').toString().trim();
      final text = (item['text'] ?? '').toString().trim();
      if (!known.contains(author) || text.isEmpty) continue;
      final rawReplyTo = (item['replyTo'] ?? '').toString().trim();
      String? replyTo;
      if (rawReplyTo.isNotEmpty &&
          rawReplyTo != author &&
          (known.contains(rawReplyTo) || rawReplyTo == fallbackReplyTo)) {
        replyTo = rawReplyTo;
      } else if (fallbackReplyTo != author) {
        replyTo = fallbackReplyTo;
      }
      out.add(MomentComment(author: author, text: text, replyTo: replyTo));
      if (out.length >= limit) break;
    }
    return out;
  }

  static MomentReaction? _parseReaction(
    Map item,
    List<String> names,
    MomentPost target,
  ) {
    final known = names.toSet();
    final likes = <String>[];
    final rawLikes = item['likes'];
    if (rawLikes is List) {
      for (final like in rawLikes) {
        final name = like.toString().trim();
        if (!known.contains(name)) continue;
        if (name == target.author) continue;
        if (likes.contains(name)) continue;
        likes.add(name);
        if (likes.length >= 4) break;
      }
    }
    final comments = _parseCommentChain(
      rawComments: item['comments'],
      known: known,
      fallbackReplyTo: target.author,
      limit: 3,
    );
    if (likes.isEmpty && comments.isEmpty) return null;
    return MomentReaction(postId: target.id, likes: likes, comments: comments);
  }

  static dynamic _decodePayload(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    // 去掉 ``` 代码块标记，模型偶尔会自己加。
    if (text.contains('```')) {
      text = text
          .split('\n')
          .where((line) => !line.trim().startsWith('```'))
          .join('\n')
          .trim();
    }
    final objectStart = text.indexOf('{');
    final objectEnd = text.lastIndexOf('}');
    final arrayStart = text.indexOf('[');
    final arrayEnd = text.lastIndexOf(']');
    final candidates = <String>[
      if (objectStart >= 0 && objectEnd > objectStart)
        text.substring(objectStart, objectEnd + 1),
      if (arrayStart >= 0 && arrayEnd > arrayStart)
        text.substring(arrayStart, arrayEnd + 1),
    ];
    for (final candidate in candidates) {
      try {
        return jsonDecode(candidate);
      } catch (_) {
        // 换个形状再试一次。
      }
    }
    return null;
  }

  static List<MomentPost> _parsePosts(
    dynamic rawList, {
    required List<String> names,
    required int limit,
  }) {
    if (rawList is! List) return const <MomentPost>[];
    final known = names.toSet();
    final out = <MomentPost>[];
    for (final item in rawList) {
      if (item is! Map) continue;
      final author = (item['author'] ?? '').toString().trim();
      final text = (item['text'] ?? '').toString().trim();
      if (!known.contains(author) || text.isEmpty) continue;
      final likes = <String>[];
      final rawLikes = item['likes'];
      if (rawLikes is List) {
        for (final like in rawLikes) {
          final name = like.toString().trim();
          if (!known.contains(name) || name == author) continue;
          if (likes.contains(name)) continue;
          likes.add(name);
          if (likes.length >= 4) break;
        }
      }
      final comments = _parseCommentChain(
        rawComments: item['comments'],
        known: known,
        fallbackReplyTo: author,
        limit: 3,
      );
      out.add(
        MomentPost(
          id: newMomentPostId(),
          author: author,
          createdAt: DateTime.now(),
          text: text,
          hasImage: item['withImage'] == true || item['image'] == true,
          likes: likes,
          comments: comments,
        ),
      );
      if (out.length >= limit) break;
    }
    return out;
  }

  /// 互动在代码里强制不均匀，不靠模型自觉：
  /// 约三成帖子没人理，两成只有赞没有评论，其余正常。
  static List<MomentPost> _shapeInteractions(List<MomentPost> posts) {
    final random = Random();
    final out = <MomentPost>[];
    for (final post in posts) {
      final roll = random.nextInt(10);
      if (roll < 3) {
        out.add(
          post.copyWith(
            likes: const <String>[],
            comments: const <MomentComment>[],
          ),
        );
      } else if (roll < 5) {
        out.add(post.copyWith(comments: const <MomentComment>[]));
      } else {
        out.add(post);
      }
    }
    return out;
  }

  /// 按现实时间给这一批排个先后：最新的一条是现在，
  /// 往前的每条比后一条早几分钟，看起来像一小时内陆续发的。
  static List<MomentPost> _stamp(List<MomentPost> posts) {
    final random = Random();
    final cursor0 = DateTime.now();
    var cursor = cursor0;
    final out = <MomentPost>[];
    for (final post in posts) {
      out.add(post.copyWith(createdAt: cursor));
      cursor = cursor.subtract(Duration(minutes: 3 + random.nextInt(22)));
    }
    return out;
  }

  static Map<String, String> _collectProfiles(
    List<WorldBook> books,
    List<MomentCharacter> characters,
  ) {
    final out = <String, String>{};
    for (final character in characters) {
      final entry = _findEntry(books, character);
      out[character.name] = entry == null ? '' : entry.content.trim();
    }
    return out;
  }

  static WorldBookEntry? _findEntry(
    List<WorldBook> books,
    MomentCharacter character,
  ) {
    WorldBookEntry? byName;
    for (final book in books) {
      for (final entry in book.entries) {
        if (character.entryId.isNotEmpty && entry.id == character.entryId) {
          return entry;
        }
        if (byName == null && entry.name.trim() == character.name) {
          byName = entry;
        }
      }
    }
    return byName;
  }

  static ({ProviderConfig config, String modelId}) _resolveModel(
    SettingsProvider settings,
  ) {
    final providerKey =
        settings.momentModelProvider ?? settings.currentModelProvider;
    final modelId = settings.momentModelId ?? settings.currentModelId;
    if (providerKey == null || modelId == null) {
      throw const MomentServiceException('model_missing');
    }
    final config = settings.getProviderConfig(providerKey);
    if (!config.enabled || !config.isModelEnabled(modelId)) {
      throw const MomentServiceException('model_missing');
    }
    return (config: config, modelId: modelId);
  }

  static String _systemText(SettingsProvider settings) {
    final buffer = StringBuffer();
    final base = settings.momentSystemPrompt.trim();
    buffer.write(base.isEmpty ? defaultMomentSystemPrompt : base);
    final extra = settings.momentExtraInstruction.trim();
    if (extra.isNotEmpty) {
      buffer.write('\n\n');
      buffer.write(extra);
    }
    return buffer.toString();
  }

  static String buildUserPrompt({
    required Map<String, String> profiles,
    required List<String> names,
    required String personaName,
    required List<MomentPost> oldPosts,
    required int count,
    int charLimit = 0,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('【角色】');
    for (final name in names) {
      final profile = profiles[name] ?? '';
      buffer.writeln('角色名：$name');
      if (profile.isNotEmpty) buffer.writeln(profile);
      buffer.writeln('---');
    }
    if (oldPosts.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('【最近的旧帖】后面可以给它们补新的互动，编号从 1 开始');
      var index = 1;
      var used = 0;
      for (final post in oldPosts) {
        final body = post.text.replaceAll(RegExp(r'\s+'), ' ');
        final commentsText = post.comments
            .map(
              (c) => c.replyTo == null || c.replyTo!.isEmpty
                  ? '${c.author}：${c.text}'
                  : '${c.author} 回复 ${c.replyTo}：${c.text}',
            )
            .join(' / ');
        final chunkLength = body.length + commentsText.length;
        // 0 = 不限制；否则装到字数上限为止，更老的不再带。
        if (charLimit > 0 && used + chunkLength > charLimit) break;
        used += chunkLength;
        // 带图的帖子里，图是按正文画的——明说一句，AI 才知道这条有配图。
        buffer.writeln(
          '$index. ${post.author}：$body${post.hasImage ? '（配了一张图）' : ''}',
        );
        if (commentsText.isNotEmpty) {
          buffer.writeln('   评论区：$commentsText');
        }
        index++;
      }
    }
    buffer.writeln();
    buffer.writeln('【要求】');
    buffer.writeln('从上面的角色里随机挑 $count 个（每次都不一样），每人发一条朋友圈。');
    buffer.writeln(
      '写他此刻真实会发的日常：心情、见闻、牢骚、小事都行。'
      '口气必须像这个人自己说的话，贴合他的人设和世界观，'
      '不要复述设定，不要写旁白，不要出现「作为一个人设」之类的解释。',
    );
    buffer.writeln(
      '长度必须长短不一：这批里至少一条只有一句短话、不超过 12 个字；'
      '至少一条能写到 60 个字以上；其余的随便，别全挤在同一个长度。',
    );
    buffer.write(
      '互动也要不均匀：这 $count 条里要有 1~2 条完全没有点赞也没有评论，'
      '有 1 条只点赞不评论，剩下的正常。点赞最多 4 个，评论最多 3 条。',
    );
    if (personaName.trim().isNotEmpty) {
      buffer.writeln();
      buffer.writeln(
        '名单里的「${personaName.trim()}」是我本人，不算角色，'
        '不要替我发帖，也不要替我在评论区说话。',
      );
    }
    buffer.writeln(
      '大约每三条里有一条带图：带图的那条 withImage 写 true，其余写 false。'
      '图不用你描述内容，会按你写的正文自动画出来；带图时正文里最好提到具体的东西或场景。'
      '历史帖子里标了「（配了一张图）」的就是带图的。',
    );
    buffer.writeln();
    buffer.writeln('【输出】');
    buffer.writeln('只输出一个 JSON 对象，不要代码块标记，不要任何多余文字，格式如下：');
    buffer.writeln('{');
    buffer.writeln('  "posts": [');
    buffer.writeln(
      '    {"author": "角色名", "text": "动态正文", "withImage": true, '
      '"likes": ["角色名"], "comments": [{"author": "角色名", "text": "评论", '
      '"replyTo": "角色名"}]}',
    );
    buffer.writeln('  ],');
    buffer.writeln('  "reactions": [');
    buffer.writeln('    {"index": 2, "likes": ["角色名"], "comments": [');
    buffer.writeln('      {"author": "角色名", "text": "新评论", "replyTo": "回谁"}');
    buffer.writeln('    ]}');
    buffer.writeln('  ]');
    buffer.writeln('}');
    buffer.writeln(
      'reactions 挑 0~3 条旧帖，index 用上面【最近的旧帖】里的编号，每条补 1~3 条评论。'
      '评论要像真的在聊：后面的人可以回帖子作者，也可以回上一条评论的人'
      '（名字写进 replyTo），彼此接得上；也可以各说各的、谁也不指。'
      '这次是整批刷新，不用守「一次一句」：如果我发过动态或评论，'
      '可以让两三个人来理我，回我的评论、在我的动态下留言、点赞都行。'
      '没有要补的就输出空数组。',
    );
    return buffer.toString();
  }
}

/// 我在某条帖子下评论后，让一两个角色回我一句。
class MomentReplyComposer {
  const MomentReplyComposer({
    required this.settings,
    required this.worldBooks,
    required this.bookIds,
    required this.characters,
    required this.personaName,
    required this.post,
    required this.myText,
    required this.replyTo,
    this.recentPosts = const <MomentPost>[],
  });

  final SettingsProvider settings;
  final WorldBookProvider worldBooks;
  final List<String> bookIds;
  final List<MomentCharacter> characters;
  final String personaName;
  final MomentPost post;
  final String myText;

  /// 我这条评论回的是谁，可能是帖主，也可能是评论区里的某个人。
  final String replyTo;

  /// 最近的动态，给模型一点上下文，免得它凭空编剧情。
  final List<MomentPost> recentPosts;

  Future<List<MomentComment>> compose() async {
    final me = personaName.trim();
    if (me.isEmpty) return const <MomentComment>[];
    if (characters.isEmpty) return const <MomentComment>[];
    final books = momentBooks(worldBooks, bookIds);
    if (books.isEmpty) return const <MomentComment>[];
    final names = <String>[for (final c in characters) c.name];
    final profiles = MomentGenerator._collectProfiles(books, characters);
    final model = MomentGenerator._resolveModel(settings);
    final system = MomentGenerator._systemText(settings);
    final prompt = buildPrompt(
      profiles: profiles,
      names: names,
      post: post,
      me: me,
      myText: myText,
      replyTo: replyTo,
      recentPosts: recentPosts,
    );

    try {
      final result = await ChatApiService.generateMessage(
        config: model.config,
        modelId: model.modelId,
        messages: <Map<String, dynamic>>[
          <String, dynamic>{'role': 'system', 'content': system},
          <String, dynamic>{'role': 'user', 'content': prompt},
        ],
        builtInToolMode: BuiltInToolMode.none,
        skipImageParsing: true,
        textOnly: true,
        reasoning: ReasoningRequest(settings.momentReasoning),
        requestTimeout: momentReplyTimeout,
      );
      return parseReplies(result.text, names: names, me: me);
    } catch (_) {
      return const <MomentComment>[];
    }
  }

  static List<MomentComment> parseReplies(
    String raw, {
    required List<String> names,
    required String me,
  }) {
    final decoded = MomentGenerator._decodePayload(raw);
    List<dynamic> items;
    if (decoded is Map) {
      final rawReplies = decoded['replies'];
      items = rawReplies is List ? rawReplies : const <dynamic>[];
    } else if (decoded is List) {
      items = decoded;
    } else {
      return const <MomentComment>[];
    }
    final known = <String>{...names, me};
    // 一次只收一条：谁说的都行（被回复的人，或者插话的别人）。
    for (final item in items) {
      if (item is! Map) continue;
      final who = (item['author'] ?? '').toString().trim();
      final text = (item['text'] ?? '').toString().trim();
      if (text.isEmpty) continue;
      if (!known.contains(who) || who == me) continue;
      return <MomentComment>[
        MomentComment(author: who, text: text, replyTo: me),
      ];
    }
    return const <MomentComment>[];
  }

  static String buildPrompt({
    required Map<String, String> profiles,
    required List<String> names,
    required MomentPost post,
    required String me,
    required String myText,
    required String replyTo,
    List<MomentPost> recentPosts = const <MomentPost>[],
  }) {
    final buffer = StringBuffer();
    buffer.writeln('【角色】');
    for (final name in names) {
      final profile = profiles[name] ?? '';
      buffer.writeln('角色名：$name');
      if (profile.isNotEmpty) buffer.writeln(profile);
      buffer.writeln('---');
    }
    if (recentPosts.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('【最近的动态】只是让你知道这群人最近在聊什么，别拿来编新剧情');
      var count = 0;
      for (final other in recentPosts) {
        if (other.id == post.id) continue;
        buffer.writeln(
          '${other.author}：${other.text.replaceAll(RegExp(r'\s+'), ' ')}'
          '${other.hasImage ? '（配了一张图）' : ''}',
        );
        count++;
        if (count >= 8) break;
      }
    }
    buffer.writeln();
    buffer.writeln('【这条帖子】');
    buffer.writeln('作者：${post.author}');
    buffer.writeln(post.text);
    if (post.comments.isNotEmpty) {
      buffer.writeln('评论区已有的留言：');
      for (final comment in post.comments) {
        final who = comment.replyTo == null || comment.replyTo!.isEmpty
            ? comment.author
            : '${comment.author} 回复 ${comment.replyTo}';
        buffer.writeln('$who：${comment.text}');
      }
    }
    buffer.writeln();
    buffer.writeln('【我刚发的评论】');
    buffer.writeln(
      replyTo == me || replyTo.isEmpty
          ? '$me：$myText'
          : '$me 回复 $replyTo：$myText',
    );
    buffer.writeln();
    buffer.writeln('【要求】');
    buffer.writeln('只让一个人回我，就一句话到两句话，别让第二个人开口，也别让角色之间自己聊起来。');
    buffer.writeln(
      '说话的人通常是「$replyTo」，但也允许名单里某个人插一句：'
      '像是看到我们在聊，忍不住搭一句。大约五次里有一次是他们插话就行，'
      '谁插话挑跟这条帖子和这个人最搭的那个，不要每次都是同一个人。',
    );
    buffer.writeln(
      '内容只能围绕这条帖子和我说的话：可以接我的梗、吐槽、不耐烦、装傻，'
      '但不许提到我没说过的事，不许编造新的剧情、人物或设定。',
    );
    buffer.writeln(
      '口气像熟人随口一接：不要客套，不要讲道理，不要总结，'
      '也不要解释你为什么这么想。',
    );
    buffer.writeln();
    buffer.writeln('【输出】');
    buffer.writeln('只输出一个 JSON 对象，不要代码块标记，不要多余文字：');
    buffer.writeln('{"replies": [{"author": "角色名", "text": "说的话"}]}');
    return buffer.toString();
  }
}

/// 我在评论里 @ 了谁，就让谁回我一句。
/// 一个人单独要一次，保证人被点到就一定到场；这次没让他开口，就再要一次。
class MomentMentionReplies {
  const MomentMentionReplies({
    required this.settings,
    required this.worldBooks,
    required this.bookIds,
    required this.characters,
    required this.personaName,
    required this.post,
    required this.myText,
    required this.mentioned,
    this.replyTarget,
    this.recentPosts = const <MomentPost>[],
  });

  final SettingsProvider settings;
  final WorldBookProvider worldBooks;
  final List<String> bookIds;
  final List<MomentCharacter> characters;

  /// 我这条评论的署名（开了天意就是那个角色的名字）。
  final String personaName;
  final MomentPost post;
  final String myText;

  /// 被 @ 到的名字，已经排掉了我的马甲和现在穿着的角色。
  final List<String> mentioned;

  /// 「召唤」用：要回的是哪条评论的作者。
  /// 空 = 老模式（我发评论 @ 了人）；有值 = 让 who 去回这个人的评论。
  final String? replyTarget;

  final List<MomentPost> recentPosts;

  Future<List<MomentComment>> compose() async {
    final me = personaName.trim();
    if (me.isEmpty) return const <MomentComment>[];
    if (characters.isEmpty) return const <MomentComment>[];
    final targets = <String>[
      for (final name in mentioned)
        if (name.trim().isNotEmpty && name.trim() != me) name.trim(),
    ];
    if (targets.isEmpty) return const <MomentComment>[];
    final books = momentBooks(worldBooks, bookIds);
    if (books.isEmpty) return const <MomentComment>[];
    final names = <String>[for (final c in characters) c.name];
    final profiles = MomentGenerator._collectProfiles(books, characters);
    final results = await Future.wait(<Future<MomentComment?>>[
      for (final target in targets) _askOne(target, me, names, profiles),
    ]);
    return <MomentComment>[
      for (final reply in results)
        if (reply != null) reply,
    ];
  }

  Future<MomentComment?> _askOne(
    String who,
    String me,
    List<String> names,
    Map<String, String> profiles,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final model = MomentGenerator._resolveModel(settings);
        final system = MomentGenerator._systemText(settings);
        final prompt = buildPrompt(
          profiles: profiles,
          names: names,
          post: post,
          me: me,
          myText: myText,
          who: who,
          replyTarget: replyTarget,
          recentPosts: recentPosts,
          strict: attempt > 0,
        );
        final result = await ChatApiService.generateMessage(
          config: model.config,
          modelId: model.modelId,
          messages: <Map<String, dynamic>>[
            <String, dynamic>{'role': 'system', 'content': system},
            <String, dynamic>{'role': 'user', 'content': prompt},
          ],
          builtInToolMode: BuiltInToolMode.none,
          skipImageParsing: true,
          textOnly: true,
          reasoning: ReasoningRequest(settings.momentReasoning),
          requestTimeout: momentReplyTimeout,
        );
        final replies = MomentReplyComposer.parseReplies(
          result.text,
          names: names,
          me: me,
        );
        for (final reply in replies) {
          if (reply.author.trim() == who) {
            final target = (replyTarget ?? '').trim();
            return MomentComment(
              author: who,
              text: reply.text,
              replyTo: target.isEmpty ? me : target,
            );
          }
        }
      } catch (_) {
        // 这次没成，下一轮再要。
      }
    }
    return null;
  }

  static String buildPrompt({
    required Map<String, String> profiles,
    required List<String> names,
    required MomentPost post,
    required String me,
    required String myText,
    required String who,
    String? replyTarget,
    List<MomentPost> recentPosts = const <MomentPost>[],
    bool strict = false,
  }) {
    final target = (replyTarget ?? '').trim();
    final summon = target.isNotEmpty;
    final buffer = StringBuffer();
    buffer.writeln('【角色】');
    for (final name in names) {
      final profile = profiles[name] ?? '';
      buffer.writeln('角色名：$name');
      if (profile.isNotEmpty) buffer.writeln(profile);
      buffer.writeln('---');
    }
    if (recentPosts.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('【最近的动态】只是让你知道这群人最近在聊什么，别拿来编新剧情');
      var count = 0;
      for (final other in recentPosts) {
        if (other.id == post.id) continue;
        buffer.writeln(
          '${other.author}：${other.text.replaceAll(RegExp(r'\s+'), ' ')}'
          '${other.hasImage ? '（配了一张图）' : ''}',
        );
        count++;
        if (count >= 6) break;
      }
    }
    buffer.writeln();
    buffer.writeln('【这条帖子】');
    buffer.writeln('作者：${post.author}');
    buffer.writeln(post.text);
    if (post.comments.isNotEmpty) {
      buffer.writeln('评论区已有的留言：');
      for (final comment in post.comments) {
        final label = comment.replyTo == null || comment.replyTo!.isEmpty
            ? comment.author
            : '${comment.author} 回复 ${comment.replyTo}';
        buffer.writeln('$label：${comment.text}');
      }
    }
    buffer.writeln();
    if (summon) {
      buffer.writeln('【要回的那条评论】');
      buffer.writeln('$target：$myText');
    } else {
      buffer.writeln('【我刚发的评论】');
      buffer.writeln('$me：$myText');
    }
    buffer.writeln();
    buffer.writeln('【要求】');
    if (summon) {
      buffer.writeln('这次只有「$who」开口：他回 $target 这一句，一到两句话。');
    } else {
      buffer.writeln('我这条评论 @ 了「$who」，这次只有 $who 开口：他回我一句，一到两句话。');
    }
    buffer.writeln(
      '别让名单里的其他人说话，也别让 $who 替别人转述；'
      '内容只围绕这条帖子和我说的话，可以接梗、吐槽、装傻、不耐烦，'
      '不许提到我没说过的事，不许编造新的剧情、人物或设定。',
    );
    buffer.writeln('口气像熟人随口一接：不要客套，不要讲道理，不要解释为什么这么想。');
    if (strict) {
      buffer.writeln('这次必须是「$who」说的，别人说的不算。');
    }
    buffer.writeln();
    buffer.writeln('【输出】');
    buffer.writeln('只输出一个 JSON 对象，不要代码块标记，不要多余文字：');
    buffer.writeln('{"replies": [{"author": "$who", "text": "说的话"}]}');
    return buffer.toString();
  }
}

/// 长按之后「刷新」那一项：让模型重写一条动态或一条评论。
/// 只换文字，点赞、评论、时间都不动。
class MomentRewriter {
  const MomentRewriter({
    required this.settings,
    required this.worldBooks,
    required this.bookIds,
    required this.characters,
    required this.personaName,
    required this.recentPosts,
  });

  final SettingsProvider settings;
  final WorldBookProvider worldBooks;
  final List<String> bookIds;
  final List<MomentCharacter> characters;
  final String personaName;
  final List<MomentPost> recentPosts;

  Future<String?> rewritePost(MomentPost post) {
    final author = post.author.trim();
    if (author == personaName.trim()) return Future<String?>.value();
    return _run(author: author, body: _postPrompt(post));
  }

  Future<String?> rewriteComment(MomentPost post, MomentComment comment) async {
    final author = comment.author.trim();
    if (author == personaName.trim()) return null;
    return _run(author: author, body: _commentPrompt(post, comment));
  }

  String _postPrompt(MomentPost post) {
    final buffer = StringBuffer();
    buffer.writeln('【人物】');
    buffer.writeln(_profileOf(post.author));
    buffer.writeln();
    buffer.writeln('【他最近的动态】别拿来编新剧情，只是让你知道他最近在讲什么');
    var count = 0;
    for (final other in recentPosts) {
      if (other.id == post.id || other.author != post.author) continue;
      buffer.writeln(other.text.replaceAll(RegExp(r'\s+'), ' '));
      count++;
      if (count >= 4) break;
    }
    if (count > 0) buffer.writeln();
    buffer.writeln('【要重写的那一条】');
    buffer.writeln(post.text);
    buffer.writeln();
    buffer.writeln('【要求】');
    buffer.writeln(
      '按上面这个人的性格重写这一条，主题别换，长度跟原来接近，'
      '不要写成旁白，不要提设定，不要突然深情，也不许编造新的事情。',
    );
    buffer.writeln();
    buffer.writeln('只输出 JSON，不要多余文字：{"text": "重写后的正文"}');
    return buffer.toString();
  }

  String _commentPrompt(MomentPost post, MomentComment comment) {
    final buffer = StringBuffer();
    buffer.writeln('【人物】');
    buffer.writeln(_profileOf(comment.author));
    buffer.writeln();
    buffer.writeln('【这条帖子】');
    buffer.writeln('作者：${post.author}');
    buffer.writeln(post.text);
    buffer.writeln();
    buffer.writeln('【评论区现状】');
    for (var i = 0; i < post.comments.length; i++) {
      final other = post.comments[i];
      final who = other.replyTo == null || other.replyTo!.isEmpty
          ? other.author
          : '${other.author} 回复 ${other.replyTo}';
      final mark =
          (other.author == comment.author &&
              other.text == comment.text &&
              other.replyTo == comment.replyTo)
          ? '（这条要重写）'
          : '';
      buffer.writeln('$who：${other.text}$mark');
      if (i >= 8) break;
    }
    buffer.writeln();
    buffer.writeln('【要求】');
    buffer.writeln(
      '只重写那条标着「这条要重写」的评论，作者还是 ${comment.author}，'
      '回的还应该是 ${comment.replyTo ?? post.author}。一句话就够，'
      '贴他这个人的口气，不许编新剧情，不许把别人说过的话换个说法再说一遍。',
    );
    buffer.writeln();
    buffer.writeln('只输出 JSON，不要多余文字：{"text": "重写后的那一句"}');
    return buffer.toString();
  }

  String _profileOf(String name) {
    final books = momentBooks(worldBooks, bookIds);
    if (books.isEmpty) return '角色名：$name';
    for (final character in characters) {
      if (character.name != name) continue;
      final entry = MomentGenerator._findEntry(books, character);
      final content = entry?.content.trim() ?? '';
      return content.isEmpty ? '角色名：$name' : '角色名：$name\n$content';
    }
    return '角色名：$name';
  }

  Future<String?> _run({required String author, required String body}) async {
    try {
      final model = MomentGenerator._resolveModel(settings);
      final system = MomentGenerator._systemText(settings);
      final result = await ChatApiService.generateMessage(
        config: model.config,
        modelId: model.modelId,
        messages: <Map<String, dynamic>>[
          <String, dynamic>{'role': 'system', 'content': system},
          <String, dynamic>{'role': 'user', 'content': body},
        ],
        builtInToolMode: BuiltInToolMode.none,
        skipImageParsing: true,
        textOnly: true,
        reasoning: ReasoningRequest(settings.momentReasoning),
        requestTimeout: momentReplyTimeout,
      );
      final decoded = MomentGenerator._decodePayload(result.text);
      if (decoded is Map) {
        final text = (decoded['text'] ?? '').toString().trim();
        if (text.isNotEmpty) return text;
      }
      final raw = result.text.trim();
      return raw.isEmpty ? null : raw;
    } catch (_) {
      return null;
    }
  }
}
