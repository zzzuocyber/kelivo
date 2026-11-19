import '../../core/models/reasoning_request.dart';
import '../../core/models/world_book.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/world_book_provider.dart';
import '../../core/services/api/chat_api_service.dart';
import 'wechat_models.dart';

/// 一次生成最多等多久。卡住就报错，不让界面无限挂着。
const Duration wechatRequestTimeout = Duration(seconds: 120);

/// 群聊生成/配置出了问题，带一个能被界面翻译成中文的码。
class WechatServiceException implements Exception {
  const WechatServiceException(this.code, {this.detail});

  final String code;
  final Object? detail;

  @override
  String toString() => 'WechatServiceException($code)';
}

/// 替某个群里的某个人写一句要发的话。
class WechatGenerator {
  const WechatGenerator({
    required this.settings,
    required this.worldBooks,
    required this.group,
    required this.history,
  });

  final SettingsProvider settings;
  final WorldBookProvider worldBooks;
  final WechatGroup group;
  final List<WechatMessage> history;

  /// 真正去要一句话。[speaker] 是这次轮到的人。
  Future<String> generateFor(WechatMember speaker) async {
    final target = _resolveModel(speaker);
    final system = _systemPrompt(speaker);
    final user = _userPrompt(speaker);
    final result = await ChatApiService.generateMessage(
      config: target.config,
      modelId: target.modelId,
      messages: <Map<String, dynamic>>[
        <String, dynamic>{'role': 'system', 'content': system},
        <String, dynamic>{'role': 'user', 'content': user},
      ],
      builtInToolMode: BuiltInToolMode.none,
      skipImageParsing: true,
      allowImagesApiRouting: false,
      textOnly: true,
      reasoning: ReasoningRequest.auto,
      requestTimeout: wechatRequestTimeout,
    );
    final text = cleanReply(result.text, speaker.name);
    if (text.isEmpty) {
      throw const WechatServiceException('empty');
    }
    return text;
  }

  // ---------------- 模型 ----------------

  ({ProviderConfig config, String modelId}) _resolveModel(
    WechatMember speaker,
  ) {
    final candidates = <({String? provider, String? model})>[
      (provider: speaker.providerKey, model: speaker.modelId),
      (provider: group.providerKey, model: group.modelId),
      (provider: settings.currentModelProvider, model: settings.currentModelId),
    ];
    for (final item in candidates) {
      final provider = item.provider;
      final model = item.model;
      if (provider == null || model == null) continue;
      final config = settings.getProviderConfig(provider);
      if (!config.enabled || !config.isModelEnabled(model)) continue;
      return (config: config, modelId: model);
    }
    throw const WechatServiceException('model_missing');
  }

  // ---------------- 提示词 ----------------

  String _systemPrompt(WechatMember speaker) {
    final buffer = StringBuffer();
    buffer.writeln(
      '你在替一个微信群里的几个人模拟日常聊天。'
      '你不需要解释，不需要旁白，不需要写名字前缀。',
    );
    buffer.writeln();
    buffer.writeln('【群名】${group.name}');
    buffer.writeln('【我】这个群里主人叫「${group.effectivePersona}」');
    buffer.writeln();

    final books = _selectedBooks();
    final profiles = _profiles(books);

    buffer.writeln('【群里的人】');
    for (final member in group.members) {
      final profile = profiles[member.name];
      buffer.writeln('### ${member.name}');
      if (profile != null && profile.isNotEmpty) {
        buffer.writeln(profile);
      } else {
        buffer.writeln('（没有额外设定，就是一个普通人群里的常客）');
      }
      buffer.writeln();
    }

    final worldText = _worldText(books, profiles);
    if (worldText.isNotEmpty) {
      buffer.writeln('【世界背景】');
      buffer.writeln(worldText);
      buffer.writeln();
    }

    buffer.writeln('【这次的规矩】');
    buffer.writeln('- 你现在只扮演「${speaker.name}」这一个人，别的角色不要替他们说。');
    buffer.writeln('- 像真人在微信上打字：短句、口语，一两个短句就够，别写成大段独白。');
    buffer.writeln('- 不用 markdown、不用括号写动作神态、不要给自己加引号。');
    buffer.writeln('- 不要每句都感慨，不要客套，不要总结。');
    buffer.writeln('- 群里有好几个人，说话可以接着上面某个人，但不是每次都非得接。');
    buffer.writeln('- 真的没什么可说，就发很短的一句，别硬凑内容。');
    buffer.writeln('- 只输出${speaker.name}这次要发出去的那段文字，别的什么都不要。');
    return buffer.toString().trim();
  }

  String _userPrompt(WechatMember speaker) {
    final buffer = StringBuffer();
    if (history.isEmpty) {
      buffer.writeln('群里还没有人说话。');
    } else {
      buffer.writeln('【最近的聊天】');
      for (final message in history) {
        if (message.system) {
          buffer.writeln('（系统）${message.text}');
          continue;
        }
        final who = message.sender.trim().isEmpty
            ? group.effectivePersona
            : message.sender;
        buffer.writeln('$who：${message.text}');
      }
      buffer.writeln();
    }
    buffer.writeln('现在轮到「${speaker.name}」说话。只输出${speaker.name}这一次要发的内容。');
    return buffer.toString().trim();
  }

  List<WorldBook> _selectedBooks() {
    final out = <WorldBook>[];
    for (final id in group.bookIds) {
      final book = worldBooks.getById(id);
      if (book != null) out.add(book);
    }
    return out;
  }

  /// 每个成员的人设正文。按 entryId 找，找不到退回按名字找。
  Map<String, String> _profiles(List<WorldBook> books) {
    final out = <String, String>{};
    for (final member in group.members) {
      final entry = _findEntry(books, member);
      out[member.name] = entry?.content.trim() ?? '';
    }
    return out;
  }

  WorldBookEntry? _findEntry(List<WorldBook> books, WechatMember member) {
    WorldBookEntry? byName;
    for (final book in books) {
      final bookMatched = member.bookId.isEmpty || book.id == member.bookId;
      for (final entry in book.entries) {
        if (member.entryId.isNotEmpty &&
            bookMatched &&
            entry.id == member.entryId) {
          return entry;
        }
        if (byName == null && entry.name.trim() == member.name.trim()) {
          byName = entry;
        }
      }
    }
    return byName;
  }

  /// 除角色条目以外的条目，当世界背景喂进去。
  String _worldText(List<WorldBook> books, Map<String, String> profiles) {
    final usedIds = <String>{
      for (final member in group.members)
        if (member.entryId.isNotEmpty) member.entryId,
    };
    final usedNames = <String>{for (final member in group.members) member.name};
    final parts = <String>[];
    var budget = 6000;
    for (final book in books) {
      for (final entry in book.entries) {
        if (!entry.enabled) continue;
        if (usedIds.contains(entry.id)) continue;
        if (usedNames.contains(entry.name.trim())) continue;
        final content = entry.content.trim();
        if (content.isEmpty) continue;
        if (budget <= 0) break;
        final piece = content.length > budget
            ? content.substring(0, budget)
            : content;
        parts.add(piece);
        budget -= piece.length;
      }
    }
    return parts.join('\n\n');
  }
}

/// 把模型吐出来的东西收拾成一条能直接发的微信消息。
String cleanReply(String raw, String speaker) {
  var text = raw.trim();
  if (text.isEmpty) return '';

  // 去掉「沈砚：」「沈砚:」这种自己加的前缀
  final escaped = RegExp.escape(speaker);
  text = text.replaceFirst(RegExp('^\\s*$escaped\\s*[:：]\\s*'), '');

  // 去掉整段被引号包住的情况
  if (text.length > 1) {
    final first = text[0];
    final last = text[text.length - 1];
    const quotes = <String>['"', "'", '“', '”', '「', '」'];
    if (quotes.contains(first) && quotes.contains(last)) {
      text = text.substring(1, text.length - 1).trim();
    }
  }

  // 去掉markdown 的粗体和斜体标记，微信里没人这么打字
  text = text.replaceAll(RegExp(r'\*\*|__'), '');
  text = text.replaceAll(RegExp(r'^\s*[-*]\s+', multiLine: true), '');

  // 掐掉“（沈砚沉默了一下）”这种动作描写
  text = text.replaceAll(RegExp(r'^\s*[（(][^）)]{0,30}[）)]\s*'), '');

  return text.trim();
}
