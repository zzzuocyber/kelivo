import 'conversation.dart';

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

  GroupChatRole copyWith({
    String? name,
    String? entryId,
    String? bookId,
    String? avatar,
    bool clearAvatar = false,
  }) {
    return GroupChatRole(
      id: id,
      name: name ?? this.name,
      entryId: entryId ?? this.entryId,
      bookId: bookId ?? this.bookId,
      avatar: clearAvatar ? '' : (avatar ?? this.avatar),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'entry': entryId,
    'book': bookId,
    'avatar': avatar,
  };

  static GroupChatRole fromJson(Map<String, dynamic> json) => GroupChatRole(
    id: (json['id'] ?? '').toString(),
    name: (json['name'] ?? '').toString(),
    entryId: (json['entry'] ?? '').toString(),
    bookId: (json['book'] ?? '').toString(),
    avatar: (json['avatar'] ?? '').toString(),
  );
}

/// 一个对话的整套群聊配置（存 Conversation.extras）。
class GroupChatConfig {
  static const extrasKey = 'groupChat.config';

  static const defaultMessageFormat = '【{角色名}】：{内容}';
  static const defaultMaxTurns = 20;
  static const maxTurnsLimit = 100;

  const GroupChatConfig({
    this.enabled = false,
    this.maxTurns = defaultMaxTurns,
    this.roles = const <GroupChatRole>[],
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

  /// 本对话的角色（按列表顺序轮换）。
  final List<GroupChatRole> roles;

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

  bool get canRun => enabled && roles.isNotEmpty;

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
    List<GroupChatRole>? roles,
    String? messageFormat,
    String? topic,
    String? rules,
    String? worldPrompt,
    List<String>? worldEntryIds,
  }) {
    return GroupChatConfig(
      enabled: enabled ?? this.enabled,
      maxTurns: maxTurns ?? this.maxTurns,
      roles: roles ?? this.roles,
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
    'roles': [for (final role in roles) role.toJson()],
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
    final worldEntries = map['worldEntryIds'];
    final turns = map['maxTurns'];
    return GroupChatConfig(
      enabled: map['enabled'] as bool? ?? false,
      maxTurns: turns is num
          ? turns.toInt().clamp(1, maxTurnsLimit)
          : defaultMaxTurns,
      roles: roles is List
          ? roles
              .whereType<Map>()
              .map((e) => GroupChatRole.fromJson(e.cast<String, dynamic>()))
              .toList()
          : const <GroupChatRole>[],
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
