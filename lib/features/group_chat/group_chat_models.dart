/// 助手「群聊模式」的数据模型。
///
/// 完全独立于小手机微信：数据存在助手自己的 JSON 里（Assistant.groupChat），
/// 不碰任何数据库表、不碰 ChatMessage、不碰主消息链路。删掉本目录 + 撤销
/// assistant.dart 里那一个字段即可干净回退。

/// 群聊里的一名角色。头像独立（不走朋友圈按名字映射），模型独立。
class GroupChatMember {
  const GroupChatMember({
    required this.name,
    this.entryId = '',
    this.bookId = '',
    this.avatar = '',
    this.providerKey,
    this.modelId,
  });

  /// 显示名，也是消息里「谁说的」。
  final String name;

  /// 世界书条目 id，用来取这条角色的人设正文。
  final String entryId;

  /// 人设来自哪本世界书。
  final String bookId;

  /// 这个角色在群聊里的独立头像（本地路径 / emoji / 空=显示首字）。
  final String avatar;

  /// 单独绑的模型；两个都为空就跟随助手/全局默认。
  final String? providerKey;
  final String? modelId;

  GroupChatMember copyWith({
    String? name,
    String? entryId,
    String? bookId,
    String? avatar,
    String? providerKey,
    String? modelId,
    bool clearModel = false,
    bool clearAvatar = false,
  }) {
    return GroupChatMember(
      name: name ?? this.name,
      entryId: entryId ?? this.entryId,
      bookId: bookId ?? this.bookId,
      avatar: clearAvatar ? '' : (avatar ?? this.avatar),
      providerKey: clearModel ? null : (providerKey ?? this.providerKey),
      modelId: clearModel ? null : (modelId ?? this.modelId),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'entry': entryId,
    'book': bookId,
    'avatar': avatar,
    if (providerKey != null) 'provider': providerKey,
    if (modelId != null) 'model': modelId,
  };

  static GroupChatMember fromJson(Map<String, dynamic> json) =>
      GroupChatMember(
        name: (json['name'] ?? '').toString(),
        entryId: (json['entry'] ?? '').toString(),
        bookId: (json['book'] ?? '').toString(),
        avatar: (json['avatar'] ?? '').toString(),
        providerKey: json['provider'] as String?,
        modelId: json['model'] as String?,
      );
}

/// 说话顺序：轮流圆桌 / 随机抢话。
enum GroupChatMode { round, random }

/// 一个助手的整套群聊配置。
class GroupChatConfig {
  const GroupChatConfig({
    this.enabled = false,
    this.mode = GroupChatMode.round,
    this.members = const <GroupChatMember>[],
    this.bookIds = const <String>[],
    this.worldPrompt = '',
    this.groupPrompt = '',
    this.maxRelay = 8,
  });

  /// 群聊模式总开关。默认关，老助手读不到就是关，绝不影响原聊天。
  final bool enabled;
  final GroupChatMode mode;
  final List<GroupChatMember> members;

  /// 群聊用哪几本世界书（取成员人设 + 世界背景）。
  final List<String> bookIds;

  /// 手写的世界观 / 本群设定（跟小手机那套用语一致）。
  final String worldPrompt;
  final String groupPrompt;

  /// @ 接力最多几轮，防止无限循环。
  final int maxRelay;

  GroupChatConfig copyWith({
    bool? enabled,
    GroupChatMode? mode,
    List<GroupChatMember>? members,
    List<String>? bookIds,
    String? worldPrompt,
    String? groupPrompt,
    int? maxRelay,
  }) {
    return GroupChatConfig(
      enabled: enabled ?? this.enabled,
      mode: mode ?? this.mode,
      members: members ?? this.members,
      bookIds: bookIds ?? this.bookIds,
      worldPrompt: worldPrompt ?? this.worldPrompt,
      groupPrompt: groupPrompt ?? this.groupPrompt,
      maxRelay: maxRelay ?? this.maxRelay,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'enabled': enabled,
    'mode': mode.name,
    'members': members.map((m) => m.toJson()).toList(),
    'bookIds': bookIds,
    'worldPrompt': worldPrompt,
    'groupPrompt': groupPrompt,
    'maxRelay': maxRelay,
  };

  static GroupChatConfig fromJson(Object? raw) {
    if (raw is! Map) return const GroupChatConfig();
    final map = raw.cast<String, dynamic>();
    final mode = GroupChatMode.values
        .where((m) => m.name == map['mode'])
        .firstOrNull ?? GroupChatMode.round;
    final members = map['members'];
    final books = map['bookIds'];
    final relay = map['maxRelay'];
    return GroupChatConfig(
      enabled: map['enabled'] as bool? ?? false,
      mode: mode,
      members: members is List
          ? members
              .whereType<Map>()
              .map((e) => GroupChatMember.fromJson(e.cast<String, dynamic>()))
              .toList()
          : const <GroupChatMember>[],
      bookIds: books is List
          ? books.map((e) => e.toString()).toList()
          : const <String>[],
      worldPrompt: (map['worldPrompt'] ?? '').toString(),
      groupPrompt: (map['groupPrompt'] ?? '').toString(),
      maxRelay: relay is num ? relay.toInt().clamp(1, 30) : 8,
    );
  }
}
