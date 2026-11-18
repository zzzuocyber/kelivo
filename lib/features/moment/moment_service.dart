import 'dart:convert';
import 'dart:math';

import '../../core/models/world_book.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/world_book_provider.dart';
import '../../core/services/api/chat_api_service.dart';
import 'moment_models.dart';
import 'moment_service_exception.dart';

export 'moment_service_exception.dart';

/// 一次刷新生成的帖子条数。
const int momentBatchSize = 5;

/// 默认系统提示词，用户可以在朋友圈设置里改。
const String defaultMomentSystemPrompt = '''你在替一组虚构角色经营他们的朋友圈。
你要按照每个角色自己的人设和世界观，假装他们是真人，随手发一条生活动态，并让其他角色点赞、评论。
语气、用词、关心的东西都要贴合各自的身份，不要写成小说旁白，不要解释设定，不要提你是模型。
只输出要求的 JSON，不要任何多余的话。''';

/// 生成一条朋友圈需要的一整套东西。
class MomentGenerator {
  const MomentGenerator({
    required this.settings,
    required this.worldBooks,
    required this.bookId,
    required this.characters,
    this.batchSize = momentBatchSize,
  });

  final SettingsProvider settings;
  final WorldBookProvider worldBooks;
  final String bookId;
  final List<MomentCharacter> characters;
  final int batchSize;

  Future<List<MomentPost>> generate() async {
    if (characters.isEmpty) {
      throw const MomentServiceException('no_characters');
    }
    final book = worldBooks.getById(bookId);
    if (book == null) {
      throw const MomentServiceException('no_book');
    }
    final names = <String>[for (final c in characters) c.name];
    final profiles = _collectProfiles(book, characters);
    final model = _resolveModel();
    final system = _systemText();
    final prompt = buildUserPrompt(
      profiles: profiles,
      names: names,
      count: batchSize,
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
          allowImagesApiRouting: false,
          textOnly: true,
        );
        final posts = parsePosts(result.text, names: names, limit: batchSize);
        if (posts.isEmpty) {
          lastError = const MomentServiceException('parse_failed');
          continue;
        }
        return _stamp(posts);
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

  ({ProviderConfig config, String modelId}) _resolveModel() {
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

  String _systemText() {
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

  static Map<String, String> _collectProfiles(
    WorldBook book,
    List<MomentCharacter> characters,
  ) {
    final out = <String, String>{};
    for (final character in characters) {
      final entry = _findEntry(book, character);
      out[character.name] = entry == null ? '' : entry.content.trim();
    }
    return out;
  }

  static WorldBookEntry? _findEntry(WorldBook book, MomentCharacter character) {
    WorldBookEntry? byName;
    for (final entry in book.entries) {
      if (character.entryId.isNotEmpty && entry.id == character.entryId) {
        return entry;
      }
      if (byName == null && entry.name.trim() == character.name) {
        byName = entry;
      }
    }
    return byName;
  }

  /// 把模型吐出来的文本当成 JSON 数组解析，坏格式就原样丢掉。
  static List<MomentPost> parsePosts(
    String raw, {
    required List<String> names,
    required int limit,
  }) {
    final start = raw.indexOf('[');
    final end = raw.lastIndexOf(']');
    if (start < 0 || end <= start) return const <MomentPost>[];
    Object? decoded;
    try {
      decoded = jsonDecode(raw.substring(start, end + 1));
    } catch (_) {
      return const <MomentPost>[];
    }
    if (decoded is! List) return const <MomentPost>[];
    final known = names.toSet();
    final out = <MomentPost>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final author = (item['author'] ?? '').toString().trim();
      final text = (item['text'] ?? '').toString().trim();
      if (!known.contains(author) || text.isEmpty) continue;
      final likes = <String>[];
      final rawLikes = item['likes'];
      if (rawLikes is List) {
        for (final like in rawLikes) {
          final name = like.toString().trim();
          if (known.contains(name) && name != author && !likes.contains(name)) {
            likes.add(name);
          }
        }
      }
      final comments = <MomentComment>[];
      final rawComments = item['comments'];
      if (rawComments is List) {
        for (final comment in rawComments) {
          if (comment is! Map) continue;
          final who = (comment['author'] ?? '').toString().trim();
          final what = (comment['text'] ?? '').toString().trim();
          if (!known.contains(who) || who == author || what.isEmpty) continue;
          comments.add(MomentComment(author: who, text: what));
        }
      }
      final withImage = item['withImage'] == true || item['image'] == true;
      out.add(
        MomentPost(
          id: newMomentPostId(),
          author: author,
          createdAt: DateTime.now(),
          text: text,
          hasImage: withImage,
          likes: likes,
          comments: comments,
        ),
      );
      if (out.length >= limit) break;
    }
    return out;
  }

  /// 按现实时间给这一批排个先后：最新的一条是现在，
  /// 往前的每条比后一条早几分钟，看起来像一小时内陆续发的。
  static List<MomentPost> _stamp(List<MomentPost> posts) {
    final random = Random();
    final now = DateTime.now();
    final out = <MomentPost>[];
    var cursor = now;
    for (final post in posts) {
      out.add(post.copyWith(createdAt: cursor));
      cursor = cursor.subtract(Duration(minutes: 3 + random.nextInt(22)));
    }
    return out;
  }

  static String buildUserPrompt({
    required Map<String, String> profiles,
    required List<String> names,
    required int count,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('【角色】');
    for (final name in names) {
      final profile = profiles[name] ?? '';
      buffer.writeln('角色名：$name');
      if (profile.isNotEmpty) {
        buffer.writeln(profile);
      }
      buffer.writeln('---');
    }
    buffer.writeln();
    buffer.writeln('【要求】');
    buffer.writeln('从上面的角色里随机挑 $count 个（每次都不一样），每人发一条朋友圈。');
    buffer.writeln(
      '每条 1~3 句，写他此刻真实会发的日常：心情、见闻、牢骚、小事都行。'
      '口气必须像这个人自己说的话，贴合他的人设和世界观，'
      '不要复述设定，不要写旁白，不要出现「作为一个人设」之类的解释。',
    );
    buffer.writeln('大约每三条里有一条带图：带图的那条 withImage 写 true，其余写 false。');
    buffer.writeln(
      '点赞和评论只能来自【角色】名单里的人：每条点赞 0~4 个，'
      '评论 0~2 条，评论只写一句话。',
    );
    buffer.writeln();
    buffer.writeln('【输出】');
    buffer.writeln('只输出一个 JSON 数组，不要代码块标记，不要任何多余文字，格式如下：');
    buffer.writeln('[');
    buffer.writeln(
      '  {"author": "角色名", "text": "动态正文", "withImage": true, '
      '"likes": ["角色名"], "comments": [{"author": "角色名", "text": "评论"}]}',
    );
    buffer.writeln(']');
    return buffer.toString();
  }
}
