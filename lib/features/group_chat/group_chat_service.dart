import 'dart:math';

import '../../core/models/reasoning_request.dart';
import '../../core/models/world_book.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/world_book_provider.dart';
import '../../core/services/api/chat_api_service.dart';
import '../wechat/wechat_service.dart'
    show
        wechatFindEntry,
        wechatResolveModel,
        wechatSelectedBooks,
        wechatWorldText,
        wechatRequestTimeout;
import 'group_chat_models.dart';

/// 群聊的一次生成结果：谁说的 + 说了什么。
class GroupChatTurn {
  const GroupChatTurn({required this.member, required this.text});

  final GroupChatMember member;
  final String text;
}

/// 群聊调度器（助手「群聊模式」专用）。
///
/// 完全独立于小手机：只借用它的几个纯函数（找人设、挑模型、取世界背景），
/// 调度规则自己实现——轮流/随机挑人，每人各问一次 AI，回话里 @ 谁就叫谁接力。
class GroupChatService {
  GroupChatService({
    required this.settings,
    required this.worldBooks,
    required this.config,
    required this.assistantName,
    this.fallbackProviderKey,
    this.fallbackModelId,
  });

  final SettingsProvider settings;
  final WorldBookProvider worldBooks;
  final GroupChatConfig config;
  final String assistantName;

  /// 助手自己的模型，当成员没单独绑时的兜底。
  final String? fallbackProviderKey;
  final String? fallbackModelId;

  final Random _random = Random();

  /// 群里有几个能说话的人。
  bool get canChat => config.members.isNotEmpty;

  /// 选这一轮谁先开口。
  GroupChatMember? pickFirst({int? afterIndex}) {
    if (config.members.isEmpty) return null;
    if (config.mode == GroupChatMode.random) {
      return config.members[_random.nextInt(config.members.length)];
    }
    // 轮流：从上一次发言者的下一个开始。
    final start = afterIndex == null ? 0 : (afterIndex + 1) % config.members.length;
    return config.members[start];
  }

  /// 解析一句话里 @ 到的群成员（按顺序、去重）。
  List<GroupChatMember> mentionsIn(String text, GroupChatMember speaker) {
    final out = <GroupChatMember>[];
    final names = <String>{};
    for (final member in config.members) {
      if (member.name == speaker.name) continue;
      if (text.contains('@${member.name}') || text.contains('＠${member.name}')) {
        if (names.add(member.name)) out.add(member);
      }
    }
    return out;
  }

  /// 让 [speaker] 说一句。[history] 是已经发生过的发言（含用户那条）。
  /// [userText] 是本次用户发的话。抛 WechatServiceException 表示没模型/失败。
  Future<GroupChatTurn> speak(
    GroupChatMember speaker, {
    required String userText,
    required List<String> historyLines,
  }) async {
    final target = wechatResolveModel(
      settings,
      providerKey: speaker.providerKey,
      modelId: speaker.modelId,
      fallbackProviderKey: fallbackProviderKey,
      fallbackModelId: fallbackModelId,
    );

    final books = wechatSelectedBooks(worldBooks, config.bookIds);
    final system = _systemPrompt(speaker, books);
    final user = _userPrompt(speaker, userText, historyLines);

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
    return GroupChatTurn(member: speaker, text: _clean(result.text, speaker.name));
  }

  String _systemPrompt(GroupChatMember speaker, List<WorldBook> books) {
    final buffer = StringBuffer();
    buffer.writeln('你在模拟一场群聊里其中一个人说话。只输出「${speaker.name}」'
        '这一句要发的话，不要写名字前缀、不要旁白、不要解释。');
    buffer.writeln('【群聊的名字】$assistantName');

    final world = config.worldPrompt.trim();
    if (world.isNotEmpty) {
      buffer.writeln('【世界观（最高优先级·铁律）】');
      buffer.writeln(world);
      buffer.writeln('——上面是铁律，与任何设定冲突时以它为准。');
    }
    final group = config.groupPrompt.trim();
    if (group.isNotEmpty) {
      buffer.writeln('【本群设定】');
      buffer.writeln(group);
    }

    buffer.writeln('【群里的人】');
    final usedIds = <String>{};
    final usedNames = <String>{};
    for (final member in config.members) {
      final entry = wechatFindEntry(
        books,
        name: member.name,
        entryId: member.entryId,
        bookId: member.bookId,
      );
      buffer.writeln('### ${member.name}');
      buffer.writeln(
        (entry != null && entry.content.trim().isNotEmpty)
            ? entry.content.trim()
            : '（普通群成员，没有额外设定）',
      );
      usedIds.add(member.name);
      usedNames.add(member.name);
      if (member.entryId.isNotEmpty) usedIds.add(member.entryId);
    }

    final worldText = wechatWorldText(
      books,
      usedIds: usedIds,
      usedNames: usedNames,
    );
    if (worldText.isNotEmpty) {
      buffer.writeln('【世界背景】');
      buffer.writeln(worldText);
    }

    buffer.writeln('【规矩】');
    buffer.writeln('- 你现在只扮演「${speaker.name}」一个人，别替别人说话。');
    buffer.writeln('- 像真人在群里打字：短句、口语，一两句就够，别写大段独白。');
    buffer.writeln('- 不用 markdown，不要用括号写动作神态。');
    buffer.writeln('- 想让某个人接话，就在话里自然写 @对方的名字。被 @ 的人会接着说。');
    buffer.writeln('- 顺着最近的情绪往下演，别突然转成安排时间地点、记账这类事务。');
    buffer.writeln('- 真的没话说就回一句很短的，别硬凑。');
    buffer.writeln('- 只输出${speaker.name}这一句要发的内容。');
    return buffer.toString().trim();
  }

  String _userPrompt(
    GroupChatMember speaker,
    String userText,
    List<String> historyLines,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('主人说：$userText');
    if (historyLines.isNotEmpty) {
      buffer.writeln('【刚才群里的对话】');
      for (final line in historyLines) {
        buffer.writeln(line);
      }
    }
    buffer.writeln('现在轮到「${speaker.name}」回主人这一句。');
    return buffer.toString().trim();
  }

  String _clean(String raw, String speaker) {
    var text = raw.trim();
    // 去掉模型偶尔自带的名字前缀。
    final prefixes = <String>['$speaker：', '$speaker:', '「$speaker」'];
    for (final p in prefixes) {
      if (text.startsWith(p)) text = text.substring(p.length).trimLeft();
    }
    // 去掉包住整句的引号。
    if (text.length >= 2 &&
        ((text.startsWith('"') && text.endsWith('"')) ||
            (text.startsWith('“') && text.endsWith('”')))) {
      text = text.substring(1, text.length - 1).trim();
    }
    return text;
  }
}
