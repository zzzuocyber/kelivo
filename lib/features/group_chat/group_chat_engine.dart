import 'dart:math';

import '../../core/models/model_spec.dart';
import '../../core/models/reasoning_request.dart';
import '../../core/models/world_book.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/world_book_provider.dart';
import '../../core/services/api/chat_api_service.dart';
import 'group_chat_models.dart';

/// 群聊的一次生成结果：谁说的 + 说了什么。
class GroupChatTurn {
  const GroupChatTurn({required this.role, required this.text});

  final GroupChatRole role;
  final String text;
}

/// 群聊编排引擎（090，按对话独立）。
///
/// 「谁来说、什么时候说」由这里编排，模型只演自己那个角色。每次发言都是
/// 一次真实的一次性调用（不流式，消息完整后才落库，天然没有半截话）。
/// 请求里只带群聊自己的东西：世界观/主题/规则/格式/名册/角色人设，
/// 助手原本的世界书、指令注入、系统提示一律不进（启用群聊即失效）。
class GroupChatEngine {
  GroupChatEngine({
    required this.settings,
    required this.worldBooks,
    required this.config,
    required this.fallbackProviderKey,
    required this.fallbackModelId,
    List<GroupChatRole>? roles,
  }) : roles = roles ?? config.roles;

  final SettingsProvider settings;
  final WorldBookProvider worldBooks;
  final GroupChatConfig config;

  /// 这场群聊实际参与的角色（098：来自全局角色库，按配置的 id 顺序）。
  final List<GroupChatRole> roles;

  /// 对话当前用的模型（角色没单独绑模型时全员跟它走）。
  final String fallbackProviderKey;
  final String fallbackModelId;

  static const silenceMarker = '[沉默]';

  final Random _random = Random();

  /// 轮到 [role] 发言。[userText] 是触发本轮的用户消息，
  /// [historyLines] 是按格式模板拼好的历史对话行。
  Future<GroupChatTurn> speak(
    GroupChatRole role, {
    required String userText,
    required List<String> historyLines,
  }) async {
    final system = _systemPrompt(role);
    final user = _userPrompt(role, userText, historyLines);

    // 角色单独绑了模型就用它（098），没绑就跟对话走。
    final roleHasModel =
        role.modelProviderKey.isNotEmpty &&
        role.modelId.isNotEmpty &&
        settings.providerConfigs.containsKey(role.modelProviderKey);
    final providerKey = roleHasModel
        ? role.modelProviderKey
        : fallbackProviderKey;
    final modelId = roleHasModel ? role.modelId : fallbackModelId;
    final result = await ChatApiService.generateMessage(
      config: settings.getProviderConfig(providerKey),
      modelId: modelId,
      messages: <Map<String, dynamic>>[
        <String, dynamic>{'role': 'system', 'content': system},
        <String, dynamic>{'role': 'user', 'content': user},
      ],
      builtInToolMode: BuiltInToolMode.none,
      skipImageParsing: true,
      allowImagesApiRouting: false,
      textOnly: true,
      reasoning: _reasoningFor(role),
      requestTimeout: const Duration(minutes: 5),
    );
    return GroupChatTurn(role: role, text: _clean(result.text, role.name));
  }

  /// 角色的深度思考档位：存的只是档位名（不含 token 细节），
  /// 真请求时按当前模型换算由 ChatApiService 处理；空 = 自动。
  ReasoningRequest _reasoningFor(GroupChatRole role) {
    final name = role.reasoningLevel.trim();
    if (name.isEmpty) return ReasoningRequest.auto;
    for (final level in ReasoningLevel.values) {
      if (level.name == name) {
        return ReasoningRequest(
          level,
          budgetTokens: role.reasoningBudget > 0 ? role.reasoningBudget : null,
        );
      }
    }
    return ReasoningRequest.auto;
  }

  /// 解析一句话里 @ 到的群成员（长名优先防误伤，按出现顺序、去重）。
  List<GroupChatRole> mentionsIn(String text, GroupChatRole speaker) {
    final normalized = text.replaceAll('＠', '@');
    final candidates = roles
        .where((role) => role.id != speaker.id && role.name.trim().isNotEmpty)
        .toList()
      ..sort((a, b) => b.name.length.compareTo(a.name.length));
    final out = <GroupChatRole>[];
    final seen = <String>{};
    for (final role in candidates) {
      if (normalized.contains('@${role.name}') && seen.add(role.id)) {
        out.add(role);
      }
    }
    // 还原成发言顺序（candidates 被长度排序打乱了）。
    return [
      for (final role in roles)
        if (out.any((hit) => hit.id == role.id)) role,
    ];
  }

  /// 没话说返回 [沉默] 哨兵，编排层收走不显示。
  static bool isSilence(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return true;
    final bare = trimmed
        .replaceAll('［', '[')
        .replaceAll('］', ']')
        .replaceAll('：', ':')
        .replaceAll('（', '(')
        .replaceAll('）', ')');
    return bare == silenceMarker || bare.startsWith('$silenceMarker:');
  }

  /// 发言之间的错峰延迟（抄北极星三档：开局 / 接话 / 隔阵）。
  Duration delayFor(int completedTurns) {
    if (completedTurns == 0) return Duration.zero;
    final ms = completedTurns == 1
        ? 180 + _random.nextInt(521)
        : 760 + _random.nextInt(1241);
    return Duration(milliseconds: ms);
  }

  WorldBookEntry? _findEntry(GroupChatRole role) {
    for (final book in worldBooks.books) {
      if (role.bookId.isNotEmpty && book.id != role.bookId) continue;
      for (final entry in book.entries) {
        if (entry.id == role.entryId) return entry;
      }
    }
    // 按条目 id 没找到，退回按名字找。
    for (final book in worldBooks.books) {
      for (final entry in book.entries) {
        if (entry.name.trim() == role.name.trim()) return entry;
      }
    }
    return null;
  }

  /// 世界观 = 手写正文 + 绑定的世界书条目内容。
  String _worldviewText() {
    final parts = <String>[];
    final handwritten = config.worldPrompt.trim();
    if (handwritten.isNotEmpty) parts.add(handwritten);
    final wanted = config.worldEntryIds.toSet();
    if (wanted.isNotEmpty) {
      for (final book in worldBooks.books) {
        for (final entry in book.entries) {
          if (!wanted.contains(entry.id)) continue;
          final text = entry.content.trim();
          if (text.isNotEmpty) parts.add(text);
        }
      }
    }
    return parts.join('\n\n');
  }

  String _systemPrompt(GroupChatRole speaker) {
    final buffer = StringBuffer();
    buffer
      ..writeln('你在参与一场群聊。只输出「${speaker.name}」这一句要发的话，'
          '不要写名字前缀、不要旁白、不要解释。')
      ..writeln('【消息格式】群里的消息按「${config.messageFormat}」的样式展示，'
          '你只需要输出内容本身。');

    final world = _worldviewText();
    if (world.isNotEmpty) {
      buffer
        ..writeln('【世界观（最高优先级·铁律）】')
        ..writeln(world)
        ..writeln('——上面是铁律，与任何设定冲突时以它为准。');
    }

    final topic = config.topic.trim();
    if (topic.isNotEmpty) {
      buffer
        ..writeln('【当前话题】')
        ..writeln(topic)
        ..writeln('发言围绕话题展开。');
    }

    final rules = config.rules.trim();
    if (rules.isNotEmpty) {
      buffer
        ..writeln('【群聊规则】')
        ..writeln(rules);
    }

    buffer.writeln('【群里的人】');
    for (final role in roles) {
      buffer.writeln('### ${role.name}');
      final entry = _findEntry(role);
      buffer.writeln(
        (entry != null && entry.content.trim().isNotEmpty)
            ? entry.content.trim()
            : '（普通群成员，没有额外设定）',
      );
    }

    buffer
      ..writeln('【规矩】')
      ..writeln('- 你现在只扮演「${speaker.name}」一个人，别替别人说话。')
      ..writeln('- 像真人在群里打字：短句、口语，别写大段独白。')
      ..writeln('- 不用 markdown，不要用括号写动作神态。')
      ..writeln('- 想让某个人接话，就在话里自然写 @对方的名字。被 @ 的人会接着说。')
      ..writeln('- 顺着最近的对话往下演。')
      ..writeln('- 真的没话说就只回 $silenceMarker，别硬凑。')
      ..writeln('- 只输出${speaker.name}这一句要发的内容。');
    return buffer.toString().trim();
  }

  String _userPrompt(
    GroupChatRole speaker,
    String userText,
    List<String> historyLines,
  ) {
    final buffer = StringBuffer();
    if (userText.isNotEmpty) {
      buffer.writeln('主人说：$userText');
    }
    if (historyLines.isNotEmpty) {
      buffer
        ..writeln('【刚才群里的对话】')
        ..writeAll(historyLines.map((line) => '$line\n'));
    }
    buffer.write('现在轮到「${speaker.name}」发言。');
    return buffer.toString().trim();
  }

  String _clean(String raw, String speaker) {
    var text = raw.trim();
    final prefixes = <String>['$speaker：', '$speaker:', '「$speaker」'];
    for (final prefix in prefixes) {
      if (text.startsWith(prefix)) text = text.substring(prefix.length).trimLeft();
    }
    if (text.length >= 2 &&
        ((text.startsWith('"') && text.endsWith('"')) ||
            (text.startsWith('“') && text.endsWith('”')))) {
      text = text.substring(1, text.length - 1).trim();
    }
    return text;
  }
}
