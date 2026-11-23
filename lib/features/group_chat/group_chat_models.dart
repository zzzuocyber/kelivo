import '../../core/models/conversation.dart';

/// 群聊功能的数据模型（090）。
///
/// 配置存对话自己的 extras（`groupChat.config` key），每个对话独立，
/// 不碰全局助手、不碰数据库 schema。角色头像存本地文件路径，没有头像
/// 时 UI 用名字首字圆标。

/// 群聊里的一名角色。人设 = 绑定的世界书条目正文。
class GroupChatRole {
  const GroupChatRole({
    required this.id,
    required this.name,
    this.entryId = '',
    this.bookId = '',
    this.avatar = '',
    this.folderId = '',
    this.modelProviderKey = '',
    this.modelId = '',
    this.reasoningLevel = '',
    this.reasoningBudget = 0,
  });

  final String id;

  /// 显示名，也是消息「谁说的」标识。默认取条目名，可改。
  final String name;

  /// 世界书条目 id（人设正文来源）。空 = 没有特殊人设。
  final String entryId;

  /// 人设来自哪本世界书。
  final String bookId;

  /// 角色头像（本地文件路径，落在 群聊头像 图库）。空 = 首字圆标。
  final String avatar;

  /// 全局角色库里属于哪个文件夹（空 = 未分类）。一层，不嵌套。
  final String folderId;

  /// 角色单独的模型；留空 = 跟随对话当前模型（098）。
  final String modelProviderKey;
  final String modelId;

  /// 深度思考档位（ReasoningLevel 的名字）；空 = 自动。
  final String reasoningLevel;

  /// 自定义预算 token，0 = 不用预算。
  final int reasoningBudget;

  GroupChatRole copyWith({
    String? name,
    String? entryId,
    String? bookId,
    String? avatar,
    String? folderId,
    String? modelProviderKey,
    String? modelId,
    String? reasoningLevel,
    int? reasoningBudget,
    bool clearAvatar = false,
    bool clearModel = false,
    bool clearReasoning = false,
  }) {
    return GroupChatRole(
      id: id,
      name: name ?? this.name,
      entryId: entryId ?? this.entryId,
      bookId: bookId ?? this.bookId,
      avatar: clearAvatar ? '' : (avatar ?? this.avatar),
      folderId: folderId ?? this.folderId,
      modelProviderKey: clearModel
          ? ''
          : (modelProviderKey ?? this.modelProviderKey),
      modelId: clearModel ? '' : (modelId ?? this.modelId),
      reasoningLevel: clearReasoning
          ? ''
          : (reasoningLevel ?? this.reasoningLevel),
      reasoningBudget: clearReasoning
          ? 0
          : (reasoningBudget ?? this.reasoningBudget),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'entry': entryId,
    'book': bookId,
    'avatar': avatar,
    'folder': folderId,
    'modelProvider': modelProviderKey,
    'model': modelId,
    'reasoning': reasoningLevel,
    'reasoningBudget': reasoningBudget,
  };

  static GroupChatRole fromJson(Map<String, dynamic> json) => GroupChatRole(
    id: (json['id'] ?? '').toString(),
    name: (json['name'] ?? '').toString(),
    entryId: (json['entry'] ?? '').toString(),
    bookId: (json['book'] ?? '').toString(),
    avatar: (json['avatar'] ?? '').toString(),
    folderId: (json['folder'] ?? '').toString(),
    modelProviderKey: (json['modelProvider'] ?? '').toString(),
    modelId: (json['model'] ?? '').toString(),
    reasoningLevel: (json['reasoning'] ?? '').toString(),
    reasoningBudget: switch (json['reasoningBudget']) {
      final num value => value.toInt(),
      final String value => int.tryParse(value) ?? 0,
      _ => 0,
    },
  );
}

/// 角色库里的文件夹（一层，不嵌套）。
class GroupChatRoleFolder {
  const GroupChatRoleFolder({required this.id, required this.name});

  final String id;
  final String name;

  GroupChatRoleFolder copyWith({String? name}) =>
      GroupChatRoleFolder(id: id, name: name ?? this.name);

  Map<String, dynamic> toJson() => <String, dynamic>{'id': id, 'name': name};

  static GroupChatRoleFolder fromJson(Map<String, dynamic> json) =>
      GroupChatRoleFolder(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
      );
}

/// 一个对话的整套群聊配置（存 Conversation.extras）。
/// 群聊接力怎么挑下一个发言人（096）。
enum GroupChatRelayMode {
  /// 排队轮流：按角色列表顺序，A → B → C → A（默认，老数据都走这个）。
  rotation,

  /// 随机挑人：每轮把角色打乱再轮流，不连着同一个人说。
  random,
}

class GroupChatConfig {
  static const extrasKey = 'groupChat.config';

  static const defaultMessageFormat = '【{角色名}】：{内容}';
  static const defaultMaxTurns = 20;
  static const maxTurnsLimit = 100;

  const GroupChatConfig({
    this.enabled = false,
    this.maxTurns = defaultMaxTurns,
    this.relayMode = GroupChatRelayMode.rotation,
    this.roles = const <GroupChatRole>[],
    this.roleIds = const <String>[],
    this.messageFormat = defaultMessageFormat,
    this.topic = '',
    this.rules = '',
    this.worldPrompt = '',
    this.worldEntryIds = const <String>[],
  });

  /// 群聊总开关。关了 = 普通对话，一切照旧。
  final bool enabled;

  /// 一次接力最多几条角色发言（用户手输，1~100，默认 20）。
  final int maxTurns;

  /// 接力挑人方式：排队轮流 / 随机挑人。
  final GroupChatRelayMode relayMode;

  /// 本对话的角色快照（老数据/兜底用；新数据以 [roleIds] 为准）。
  final List<GroupChatRole> roles;

  /// 本对话从全局角色库里选了谁（按顺序轮换，098）。
  final List<String> roleIds;

  /// 消息格式模板，支持 {角色名} {内容} 占位符。用于喂给模型的上下文。
  final String messageFormat;

  /// 当前正在聊的主题（随时可改）。
  final String topic;

  /// 群聊规则（怎么聊的约束）。
  final String rules;

  /// 手写的世界观正文。
  final String worldPrompt;

  /// 世界观绑定的世界书条目 id（大段世界观在世界书里养着）。
  final List<String> worldEntryIds;

  /// 有没有配角色（新数据看 roleIds，老数据看快照）。
  bool get hasRoles => roleIds.isNotEmpty || roles.isNotEmpty;

  /// 群聊模式总开关（1xx 起为废案）：false = 任何时候都不跑群聊，
  /// 哪怕某个对话上次开着也当普通聊天用。想重启改回 true 即可，
  /// 配置、角色库、历史消息都还在。
  static const bool featureEnabled = false;

  bool get canRun => featureEnabled && enabled && hasRoles;

  String formatLine(String name, String content) {
    final template = messageFormat.trim().isEmpty
        ? defaultMessageFormat
        : messageFormat;
    return template
        .replaceAll('{角色名}', name)
        .replaceAll('{内容}', content);
  }

  GroupChatConfig copyWith({
    bool? enabled,
    int? maxTurns,
    GroupChatRelayMode? relayMode,
    List<GroupChatRole>? roles,
    List<String>? roleIds,
    String? messageFormat,
    String? topic,
    String? rules,
    String? worldPrompt,
    List<String>? worldEntryIds,
  }) {
    return GroupChatConfig(
      enabled: enabled ?? this.enabled,
      maxTurns: maxTurns ?? this.maxTurns,
      relayMode: relayMode ?? this.relayMode,
      roles: roles ?? this.roles,
      roleIds: roleIds ?? this.roleIds,
      messageFormat: messageFormat ?? this.messageFormat,
      topic: topic ?? this.topic,
      rules: rules ?? this.rules,
      worldPrompt: worldPrompt ?? this.worldPrompt,
      worldEntryIds: worldEntryIds ?? this.worldEntryIds,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'enabled': enabled,
    'maxTurns': maxTurns,
    'relayMode': relayMode.name,
    'roles': [for (final role in roles) role.toJson()],
    'roleIds': roleIds,
    'messageFormat': messageFormat,
    'topic': topic,
    'rules': rules,
    'worldPrompt': worldPrompt,
    'worldEntryIds': worldEntryIds,
  };

  static GroupChatConfig fromConversation(Conversation? conversation) {
    final raw = conversation?.extras[extrasKey];
    if (raw is! Map) return const GroupChatConfig();
    final map = raw.cast<String, dynamic>();
    final roles = map['roles'];
    final roleIds = map['roleIds'];
    final worldEntries = map['worldEntryIds'];
    final turns = map['maxTurns'];
    return GroupChatConfig(
      enabled: map['enabled'] as bool? ?? false,
      relayMode: GroupChatRelayMode.values.firstWhere(
        (mode) => mode.name == map['relayMode'],
        orElse: () => GroupChatRelayMode.rotation,
      ),
      maxTurns: turns is num
          ? turns.toInt().clamp(1, maxTurnsLimit)
          : defaultMaxTurns,
      roles: roles is List
          ? roles
              .whereType<Map>()
              .map((e) => GroupChatRole.fromJson(e.cast<String, dynamic>()))
              .toList()
          : const <GroupChatRole>[],
      roleIds: roleIds is List
          ? <String>[for (final id in roleIds) id.toString()]
          : const <String>[],
      messageFormat: (map['messageFormat'] ?? '').toString(),
      topic: (map['topic'] ?? '').toString(),
      rules: (map['rules'] ?? '').toString(),
      worldPrompt: (map['worldPrompt'] ?? '').toString(),
      worldEntryIds: worldEntries is List
          ? worldEntries.map((e) => e.toString()).toList()
          : const <String>[],
    );
  }
}

/// 群聊消息的发言人快照（随消息落库，角色改名/删除后历史仍显示原样）。
class GroupChatSpeaker {
  static const extrasKey = 'groupChat.speaker';

  const GroupChatSpeaker({required this.id, required this.name, this.avatar = ''});

  /// 角色 id（对应 GroupChatRole.id）。
  final String id;

  /// 发言时的角色名。
  final String name;

  /// 发言时的角色头像路径（快照）。空 = 首字圆标。
  final String avatar;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'avatar': avatar,
  };

  static GroupChatSpeaker? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.cast<String, dynamic>();
    final name = (map['name'] ?? '').toString();
    if (name.isEmpty) return null;
    return GroupChatSpeaker(
      id: (map['id'] ?? '').toString(),
      name: name,
      avatar: (map['avatar'] ?? '').toString(),
    );
  }
}
