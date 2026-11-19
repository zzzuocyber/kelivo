import 'dart:math';

/// 微信的全部数据挂在一条隐藏对话的 extras 里。键都带 wechat. 前缀，
/// 不会被拼进任何提示词。
const String wechatHiddenKey = 'wechat.hidden';
const String wechatGroupsKey = 'wechat.groups';
const String wechatMessagesKey = 'wechat.messages';

/// 隐藏对话的标题，只在备份/导出里看得见。
const String wechatContainerTitle = '微信';

/// 微信模块的数据模型。
///
/// 所有东西都挂在一条隐藏对话的 extras 里（跟朋友圈一个路子），
/// 不动数据库结构。读写集中在 [WechatStore]，以后要换成真消息表只改那一个类。

/// 一条群成员。
class WechatMember {
  const WechatMember({
    required this.name,
    this.entryId = '',
    this.bookId = '',
    this.providerKey,
    this.modelId,
  });

  /// 显示名，同时也是消息里的“谁说的”。
  final String name;

  /// 世界书条目的 id，用来取人设正文。
  final String entryId;

  /// 这条人设来自哪本世界书（多本世界书时用来区分同名条目）。
  final String bookId;

  /// 单独绑的模型；两个都为空就跟随群设置 / 全局默认。
  final String? providerKey;
  final String? modelId;

  WechatMember copyWith({
    String? name,
    String? entryId,
    String? bookId,
    String? providerKey,
    String? modelId,
    bool clearModel = false,
  }) {
    return WechatMember(
      name: name ?? this.name,
      entryId: entryId ?? this.entryId,
      bookId: bookId ?? this.bookId,
      providerKey: clearModel ? null : (providerKey ?? this.providerKey),
      modelId: clearModel ? null : (modelId ?? this.modelId),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    if (entryId.isNotEmpty) 'entry': entryId,
    if (bookId.isNotEmpty) 'book': bookId,
    if (providerKey != null) 'provider': providerKey,
    if (modelId != null) 'model': modelId,
  };

  static WechatMember? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = (raw['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;
    final provider = raw['provider'];
    final model = raw['model'];
    return WechatMember(
      name: name,
      entryId: (raw['entry'] ?? '').toString(),
      bookId: (raw['book'] ?? '').toString(),
      providerKey: provider is String && provider.isNotEmpty ? provider : null,
      modelId: model is String && model.isNotEmpty ? model : null,
    );
  }
}

/// 发言间隔的预设。
enum WechatIntervalPreset { fast, normal, slow, random, custom }

extension WechatIntervalPresetX on WechatIntervalPreset {
  String get label => switch (this) {
    WechatIntervalPreset.fast => '秒回',
    WechatIntervalPreset.normal => '正常',
    WechatIntervalPreset.slow => '慢',
    WechatIntervalPreset.random => '完全随机',
    WechatIntervalPreset.custom => '自定义',
  };

  String get hint => switch (this) {
    WechatIntervalPreset.fast => '0.5 ~ 3 秒',
    WechatIntervalPreset.normal => '4 ~ 30 秒',
    WechatIntervalPreset.slow => '40 秒 ~ 4 分钟',
    WechatIntervalPreset.random => '1 秒 ~ 5 分钟',
    WechatIntervalPreset.custom => '自己填上下限',
  };

  /// 实际落到的秒数区间。
  ({int min, int max}) get range => switch (this) {
    WechatIntervalPreset.fast => (min: 0, max: 3),
    WechatIntervalPreset.normal => (min: 4, max: 30),
    WechatIntervalPreset.slow => (min: 40, max: 240),
    WechatIntervalPreset.random => (min: 1, max: 300),
    WechatIntervalPreset.custom => (min: 3, max: 30),
  };

  static WechatIntervalPreset parse(Object? raw) {
    final value = (raw ?? '').toString();
    for (final item in WechatIntervalPreset.values) {
      if (item.name == value) return item;
    }
    return WechatIntervalPreset.normal;
  }
}

/// 一个群。
class WechatGroup {
  const WechatGroup({
    required this.id,
    required this.name,
    this.members = const <WechatMember>[],
    this.bookIds = const <String>[],
    this.persona = '',
    this.divine = '',
    this.intervalPreset = WechatIntervalPreset.normal,
    this.customMinSeconds = 3,
    this.customMaxSeconds = 30,
    this.providerKey,
    this.modelId,
    this.createdAt = 0,
  });

  final String id;
  final String name;
  final List<WechatMember> members;

  /// 选中的世界书，可以多本。
  final List<String> bookIds;

  /// 我自己在这个群里的名字。
  final String persona;

  /// 天意：现在顶替谁说话。空 = 是我自己。
  final String divine;

  final WechatIntervalPreset intervalPreset;
  final int customMinSeconds;
  final int customMaxSeconds;

  /// 群默认模型；某个成员没单独绑就用这个。
  final String? providerKey;
  final String? modelId;

  final int createdAt;

  /// 这个间隔预设下，随机出来的一段时间。
  Duration nextDelay(Random random) {
    final range = intervalPreset.range;
    var lo = range.min;
    var hi = range.max;
    if (intervalPreset == WechatIntervalPreset.custom) {
      lo = customMinSeconds.clamp(0, 3600);
      hi = customMaxSeconds.clamp(lo, 3600);
    }
    if (hi <= lo) return Duration(seconds: lo);
    // 不均等分布：多数落在前段，偶尔拖很久，比死板均匀更像真人。
    final span = hi - lo;
    final skewed = pow(random.nextDouble(), 1.7).toDouble();
    return Duration(seconds: lo + (skewed * span).round());
  }

  String get effectivePersona {
    final value = persona.trim();
    return value.isEmpty ? '我' : value;
  }

  WechatGroup copyWith({
    String? name,
    List<WechatMember>? members,
    List<String>? bookIds,
    String? persona,
    String? divine,
    WechatIntervalPreset? intervalPreset,
    int? customMinSeconds,
    int? customMaxSeconds,
    String? providerKey,
    String? modelId,
    bool clearModel = false,
  }) {
    return WechatGroup(
      id: id,
      name: name ?? this.name,
      members: members ?? this.members,
      bookIds: bookIds ?? this.bookIds,
      persona: persona ?? this.persona,
      divine: divine ?? this.divine,
      intervalPreset: intervalPreset ?? this.intervalPreset,
      customMinSeconds: customMinSeconds ?? this.customMinSeconds,
      customMaxSeconds: customMaxSeconds ?? this.customMaxSeconds,
      providerKey: clearModel ? null : (providerKey ?? this.providerKey),
      modelId: clearModel ? null : (modelId ?? this.modelId),
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'members': members.map((m) => m.toJson()).toList(growable: false),
    'books': bookIds,
    'persona': persona,
    'divine': divine,
    'interval': intervalPreset.name,
    'min': customMinSeconds,
    'max': customMaxSeconds,
    if (providerKey != null) 'provider': providerKey,
    if (modelId != null) 'model': modelId,
    'at': createdAt,
  };

  static WechatGroup? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = (raw['id'] ?? '').toString();
    final name = (raw['name'] ?? '').toString().trim();
    if (id.isEmpty) return null;
    final membersRaw = raw['members'];
    final members = <WechatMember>[];
    if (membersRaw is List) {
      for (final item in membersRaw) {
        final member = WechatMember.fromJson(item);
        if (member != null) members.add(member);
      }
    }
    final booksRaw = raw['books'];
    final books = <String>[];
    if (booksRaw is List) {
      for (final item in booksRaw) {
        final value = item.toString().trim();
        if (value.isNotEmpty) books.add(value);
      }
    }
    final provider = raw['provider'];
    final model = raw['model'];
    return WechatGroup(
      id: id,
      name: name.isEmpty ? '未命名群聊' : name,
      members: members,
      bookIds: books,
      persona: (raw['persona'] ?? '').toString(),
      divine: (raw['divine'] ?? '').toString(),
      intervalPreset: WechatIntervalPresetX.parse(raw['interval']),
      customMinSeconds: _intOr(raw['min'], 3),
      customMaxSeconds: _intOr(raw['max'], 30),
      providerKey: provider is String && provider.isNotEmpty ? provider : null,
      modelId: model is String && model.isNotEmpty ? model : null,
      createdAt: _intOr(raw['at'], 0),
    );
  }
}

/// 一条聊天记录。
class WechatMessage {
  const WechatMessage({
    required this.id,
    required this.sender,
    required this.text,
    required this.at,
    this.system = false,
    this.mine = false,
    this.divine = false,
  });

  final String id;

  /// 谁说的。系统消息时为空。
  final String sender;

  final String text;
  final int at;

  /// 系统提示（“某某加入群聊”），不可编辑、参与上下文。
  final bool system;

  /// 是不是我发的（包括我夺舍说的，仍算“我这边发的”）。
  final bool mine;

  /// 这条是我开了天意替别人说的。平时不显示，长按查看时才标记。
  final bool divine;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'sender': sender,
    'text': text,
    'at': at,
    if (system) 'sys': true,
    if (mine) 'mine': true,
    if (divine) 'divine': true,
  };

  static WechatMessage? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = (raw['id'] ?? '').toString();
    if (id.isEmpty) return null;
    return WechatMessage(
      id: id,
      sender: (raw['sender'] ?? '').toString(),
      text: (raw['text'] ?? '').toString(),
      at: _intOr(raw['at'], 0),
      system: raw['sys'] == true,
      mine: raw['mine'] == true,
      divine: raw['divine'] == true,
    );
  }
}

int _intOr(Object? raw, int fallback) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw) ?? fallback;
  return fallback;
}

List<WechatGroup> wechatGroupsFromExtras(Map<String, dynamic>? extras) {
  final raw = extras?[wechatGroupsKey];
  if (raw is! List) return const <WechatGroup>[];
  final out = <WechatGroup>[];
  for (final item in raw) {
    final group = WechatGroup.fromJson(item);
    if (group != null) out.add(group);
  }
  return out;
}

List<WechatMessage> wechatMessagesFromExtras(
  Map<String, dynamic>? extras,
  String groupId,
) {
  final all = extras?[wechatMessagesKey];
  if (all is! Map) return const <WechatMessage>[];
  final raw = all[groupId];
  if (raw is! List) return const <WechatMessage>[];
  final out = <WechatMessage>[];
  for (final item in raw) {
    final message = WechatMessage.fromJson(item);
    if (message != null) out.add(message);
  }
  return out;
}
