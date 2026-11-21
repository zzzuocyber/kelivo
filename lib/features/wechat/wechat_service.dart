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

/// 模型这轮决定不回：不是错误，调用处静默丢掉整轮，不能弹提示。
class WechatNoReplyException implements Exception {
  const WechatNoReplyException();
}

// ============================================================
// 公用零件
// ============================================================

/// 把选中的世界书取出来，跳过已经被删掉的。
List<WorldBook> wechatSelectedBooks(
  WorldBookProvider provider,
  List<String> ids,
) {
  final out = <WorldBook>[];
  for (final id in ids) {
    final book = provider.getById(id);
    if (book != null) out.add(book);
  }
  return out;
}

/// 在世界书里找某个角色的条目：先按 entryId，找不到退回按名字。
WorldBookEntry? wechatFindEntry(
  List<WorldBook> books, {
  required String name,
  String entryId = '',
  String bookId = '',
}) {
  final targetName = name.trim();
  WorldBookEntry? byName;
  for (final book in books) {
    final bookMatched = bookId.isEmpty || book.id == bookId;
    for (final entry in book.entries) {
      if (entryId.isNotEmpty && bookMatched && entry.id == entryId) {
        return entry;
      }
      if (byName == null && entry.name.trim() == targetName) {
        byName = entry;
      }
    }
  }
  return byName;
}

/// 除角色条目以外的条目，当世界背景喂进去。
String wechatWorldText(
  List<WorldBook> books, {
  required Set<String> usedIds,
  required Set<String> usedNames,
  int budget = 6000,
}) {
  final parts = <String>[];
  var left = budget;
  for (final book in books) {
    for (final entry in book.entries) {
      if (!entry.enabled) continue;
      if (usedIds.contains(entry.id)) continue;
      if (usedNames.contains(entry.name.trim())) continue;
      final content = entry.content.trim();
      if (content.isEmpty) continue;
      if (left <= 0) break;
      final piece = content.length > left
          ? content.substring(0, left)
          : content;
      parts.add(piece);
      left -= piece.length;
    }
  }
  return parts.join('\n\n');
}

/// 按「自己 → 上一层 → 全局当前」挑一个能用的模型。
///
/// 每层都要确认服务商还在、模型没被禁用，否则继续往下退。
({ProviderConfig config, String modelId}) wechatResolveModel(
  SettingsProvider settings, {
  String? providerKey,
  String? modelId,
  String? fallbackProviderKey,
  String? fallbackModelId,
}) {
  final candidates = <({String? provider, String? model})>[
    (provider: providerKey, model: modelId),
    (provider: fallbackProviderKey, model: fallbackModelId),
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

/// 群里共用的说话规矩。
///
/// [burstCount] 是这次抽到的条数（1~7）：抽到几条就写几行，一行一条。
/// 这样条数分布由概率档决定，不再靠模型自己老老实实只写两条。
void _writeChatRules(
  StringBuffer buffer,
  String speakerName, {
  required int burstCount,
}) {
  buffer.writeln('- 你现在只扮演「$speakerName」这一个人，别的角色不要替他们说。');
  buffer.writeln('- 像真人在微信上打字：短句、口语，一两个短句就够，别写成大段独白。');
  buffer.writeln('- 不用 markdown、不用括号写动作神态、不要给自己加引号。');
  buffer.writeln('- 不要每句都感慨，不要客套，不要总结。');
  buffer.writeln('- 真的没什么可说，就发很短的一句，别硬凑内容。');
  if (burstCount <= 1) {
    buffer.writeln('- 这次只发一条消息，就写一行，不要换行，不要连发。');
  } else {
    buffer.writeln(
      '- 这次要连着发 $burstCount 条消息：用换行分开，一行就是一条，'
      '写满 $burstCount 行，不多不少。每条都短，像真人分几次发出去的。',
    );
  }
  buffer.writeln(
    '- 偶尔可以发图：想给哪条配图，就在那一行末尾加 [图] 两个字符（例：今天吃的火锅[图]）。'
    '不用描述图片内容，图会按你这句话自己画出来。不是每条都发，聊到具体的东西或场景时来一张就行。',
  );
  buffer.writeln('- 只输出$speakerName 这次要发出去的那段文字，别的什么都不要。');
}

/// 把一条历史消息写成给模型看的那行字。带图的补一句，让模型知道那是图。
String wechatHistoryLine(WechatMessage message, {required String who}) {
  final tail = message.withImage ? '（配了一张图）' : '';
  return '$who：${message.text}$tail';
}

// ============================================================
// 群聊
// ============================================================

/// 替某个群里的某个人写一句要发的话。
class WechatGenerator {
  const WechatGenerator({
    required this.settings,
    required this.worldBooks,
    required this.group,
    required this.history,
    this.contacts = const <String, WechatContact>{},
    this.worldPrompt = '',
  });

  final SettingsProvider settings;
  final WorldBookProvider worldBooks;
  final WechatGroup group;
  final List<WechatMessage> history;

  /// 通讯录，用来取角色级的模型绑定。群里没有这个人的时候退回群设置。
  final Map<String, WechatContact> contacts;

  /// 「我 → 设置 → 世界观」里手写的设定，全局生效。
  final String worldPrompt;

  /// 真正去要一句话。[speaker] 是这次轮到的人。
  ///
  /// [burstCount] 是这次抽到的连发条数（1~7），写进提示词让模型按行数回。
  Future<String> generateFor(WechatMember speaker, {int burstCount = 1}) async {
    final target = _resolveModel(speaker);
    final system = _systemPrompt(speaker, burstCount: burstCount);
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

  ({ProviderConfig config, String modelId}) _resolveModel(
    WechatMember speaker,
  ) {
    final contact = contacts[speaker.name];
    return wechatResolveModel(
      settings,
      // 通讯录里有人就以它为准（清了绑定就是真没绑，不退回旧值）
      providerKey: contact != null ? contact.providerKey : speaker.providerKey,
      modelId: contact != null ? contact.modelId : speaker.modelId,
      fallbackProviderKey: group.providerKey,
      fallbackModelId: group.modelId,
    );
  }

  String _systemPrompt(WechatMember speaker, {required int burstCount}) {
    final buffer = StringBuffer();
    buffer.writeln(
      '你在替一个微信群里的几个人模拟日常聊天。'
      '你不需要解释，不需要旁白，不需要写名字前缀。',
    );
    buffer.writeln();
    buffer.writeln('【群名】${group.name}');
    buffer.writeln('【我】这个群里主人叫「${group.effectivePersona}」');
    buffer.writeln();

    final books = wechatSelectedBooks(worldBooks, group.bookIds);
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

    final worldText = wechatWorldText(
      books,
      usedIds: <String>{
        for (final member in group.members)
          if (member.entryId.isNotEmpty) member.entryId,
      },
      usedNames: <String>{for (final member in group.members) member.name},
    );
    if (worldText.isNotEmpty) {
      buffer.writeln('【世界背景】');
      buffer.writeln(worldText);
      buffer.writeln();
    }

    final worldSetting = worldPrompt.trim();
    if (worldSetting.isNotEmpty) {
      buffer.writeln('【世界观】');
      buffer.writeln(worldSetting);
      buffer.writeln();
    }

    buffer.writeln('【这次的规矩】');
    _writeChatRules(buffer, speaker.name, burstCount: burstCount);
    buffer.writeln('- 群里有好几个人，说话可以接着上面某个人，但不是每次都非得接。');
    buffer.writeln('- 消息里带 @名字 的是专门叫那个人，被 @ 的人优先接这句。');
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
        buffer.writeln(wechatHistoryLine(message, who: who));
      }
      buffer.writeln();
    }
    buffer.writeln('现在轮到「${speaker.name}」说话。只输出${speaker.name}这一次要发的内容。');
    return buffer.toString().trim();
  }

  /// 每个成员的人设正文。按 entryId 找，找不到退回按名字找。
  Map<String, String> _profiles(List<WorldBook> books) {
    final out = <String, String>{};
    for (final member in group.members) {
      final entry = wechatFindEntry(
        books,
        name: member.name,
        entryId: member.entryId,
        bookId: member.bookId,
      );
      out[member.name] = entry?.content.trim() ?? '';
    }
    return out;
  }
}

// ============================================================
// 私聊
// ============================================================

/// 一对一私聊：只有「我」和对面这个人，没有调度器，你一句他一句。
class WechatDmGenerator {
  const WechatDmGenerator({
    required this.settings,
    required this.worldBooks,
    required this.contact,
    required this.bookIds,
    required this.persona,
    required this.history,
    this.worldPrompt = '',
    this.selfInitiated = false,
    this.allowNoReply = false,
  });

  final SettingsProvider settings;
  final WorldBookProvider worldBooks;

  /// 对面这个人（人设、模型都从他身上取）。
  final WechatContact contact;

  /// 私聊用哪几本世界书（微信全局那几本）。
  final List<String> bookIds;

  /// 我的马甲名。
  final String persona;

  /// 「我 → 设置 → 世界观」里手写的设定，全局生效。
  final String worldPrompt;

  final List<WechatMessage> history;

  /// 这次是你主动去找对方开口（召唤私聊），不是回应他。
  final bool selfInitiated;

  /// 只有开了「会不搭理人」且没被强制回复时才是 true。
  final bool allowNoReply;

  /// [burstCount] 是这次抽到的连发条数（1~7），写进提示词让模型按行数回。
  Future<String> generate({int burstCount = 1}) async {
    final target = wechatResolveModel(
      settings,
      providerKey: contact.providerKey,
      modelId: contact.modelId,
    );
    final system = _systemPrompt(burstCount: burstCount);
    final user = _userPrompt();
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
    // 暗号要在 cleanReply 之前认：cleanReply 会剥行首括号，别让标记被吃掉。
    if (allowNoReply && wechatHasNoReplyMark(result.text)) {
      throw const WechatNoReplyException();
    }
    final text = cleanReply(result.text, contact.name);
    if (text.isEmpty) {
      throw const WechatServiceException('empty');
    }
    return text;
  }

  String _systemPrompt({required int burstCount}) {
    final buffer = StringBuffer();
    buffer.writeln(
      '你在替一个人用微信私聊。'
      '你不需要解释，不需要旁白，不需要写名字前缀。',
    );
    buffer.writeln();
    buffer.writeln('【我】对面这个人叫「$persona」');
    buffer.writeln();
    buffer.writeln('【你是】');
    buffer.writeln('### ${contact.name}');

    final books = wechatSelectedBooks(worldBooks, bookIds);
    final entry = wechatFindEntry(
      books,
      name: contact.name,
      entryId: contact.entryId,
      bookId: contact.bookId,
    );
    final profile = entry?.content.trim() ?? '';
    if (profile.isEmpty) {
      buffer.writeln('（没有额外设定，就是一个普通人）');
    } else {
      buffer.writeln(profile);
    }
    buffer.writeln();

    final worldText = wechatWorldText(
      books,
      usedIds: <String>{if (contact.entryId.isNotEmpty) contact.entryId},
      usedNames: <String>{contact.name},
    );
    if (worldText.isNotEmpty) {
      buffer.writeln('【世界背景】');
      buffer.writeln(worldText);
      buffer.writeln();
    }

    final worldSetting = worldPrompt.trim();
    if (worldSetting.isNotEmpty) {
      buffer.writeln('【世界观】');
      buffer.writeln(worldSetting);
      buffer.writeln();
    }

    buffer.writeln('【这次的规矩】');
    _writeChatRules(buffer, contact.name, burstCount: burstCount);
    buffer.writeln('- 这是两个人的私聊，没有别人在场，说话可以更随意一点。');
    if (selfInitiated) {
      buffer.writeln(
        '- 这次是你自己突然想找「$persona」聊聊，主动给他发消息，'
        '没有任何人叫你、催你或召唤你。'
        '绝对不要提「召唤」「你叫我」「你找我」「是你让我来」这类话，'
        '也不要表现出是被谁指使的——就当你一念之间想跟他说两句。',
      );
    }
    if (allowNoReply) {
      buffer.writeln(
        '- 这一轮你**可以真的不回**：如果按你的人设此刻讨厌对方、正忙、'
        '只是同事懒得搭理，或者单纯不想开口，就只输出 $wechatNoReplyMark，'
        '一个字都别多写。',
      );
      buffer.writeln(
        '- 但对方明确命令、召唤你、或正在推进剧情关键内容时，必须正常回，'
        '不能用这个标记。',
      );
    }
    return buffer.toString().trim();
  }

  String _userPrompt() {
    final buffer = StringBuffer();
    if (history.isEmpty) {
      if (selfInitiated) {
        buffer.writeln('这是你主动找「$persona」开口的第一句，他还没回过你。');
      } else {
        buffer.writeln('你们还没聊过，这是第一句。');
      }
    } else {
      buffer.writeln('【最近的聊天】');
      for (final message in history) {
        // 撤回留下的那句系统提示（原文不会传进来）。
        if (message.system) {
          buffer.writeln('（系统）${message.text}');
          continue;
        }
        // 天意替他说的话，是“他说的”，不是“我说的”。
        final who = message.mine && !message.divine ? persona : contact.name;
        buffer.writeln(wechatHistoryLine(message, who: who));
      }
      buffer.writeln();
    }
    if (selfInitiated) {
      buffer.writeln(
        '现在由「${contact.name}」主动开口找「$persona」，只输出${contact.name}这一次要发的内容。',
      );
    } else {
      buffer.writeln('现在轮到「${contact.name}」说话。只输出${contact.name}这一次要发的内容。');
    }
    return buffer.toString().trim();
  }
}

// ============================================================
// 洗一遍模型吐出来的东西
// ============================================================

/// 模型偶尔会连发几条：按换行拆成多条消息。
///
/// 最多 [maxParts] 条；多出来的并进最后一条，避免一次刷一屏。
/// 默认 7 条（跟概率档的上限一致）；调用处知道这次抽到几条时传进来更准。
List<String> wechatSplitReply(String text, {int maxParts = 7}) {
  final parts = <String>[];
  for (final line in text.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    parts.add(trimmed);
  }
  if (parts.length <= 1) return parts;
  if (parts.length > maxParts) {
    final head = parts.take(maxParts - 1).toList();
    head.add(parts.skip(maxParts - 1).join(' '));
    return head;
  }
  return parts;
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
