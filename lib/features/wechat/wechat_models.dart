import 'dart:convert';
import 'dart:math';

/// 微信的全部数据挂在一条隐藏对话的 extras 里。键都带 wechat. 前缀，
/// 不会被拼进任何提示词。
const String wechatHiddenKey = 'wechat.hidden';
const String wechatGroupsKey = 'wechat.groups';
const String wechatMessagesKey = 'wechat.messages';
const String wechatContactsKey = 'wechat.contacts';

/// 每个会话读到哪了（毫秒时间戳），键跟 [wechatMessagesKey] 一致。
const String wechatReadsKey = 'wechat.reads';

/// 私聊会话窗口名单（联系人名字），跟消息是否为空解耦。
/// 删聊天记录只删消息，窗口靠这份名单留在首页；长按「移除会话」才从这里删。
const String wechatDmSessionsKey = 'wechat.dmsessions';

/// 私聊记录在 [wechatMessagesKey] 里的键：群用群 id，私聊用 dm:名字。
String wechatDmKey(String name) => 'dm:${name.trim()}';

/// 隐藏对话的标题，只在备份/导出里看得见。
const String wechatContainerTitle = '微信';

/// 发图标记：想给这条消息配图，就在文字末尾带上这两个字。
///
/// 跟朋友圈一样**不接生图接口**——图是按这句话里的词挑 emoji 拼出来的。
/// 标记在存进消息前会被剥掉，只在「模型 ↔ App」之间当作暗号。
const String wechatImageMark = '[图]';

/// 剥掉行尾的发图标记，返回正文 + 是否带图。
///
/// 模型可能在 `[图]` 前后留空格，也可能写全角括号，这里都认。
({String text, bool withImage}) wechatStripImageMark(String raw) {
  var text = raw.trim();
  var marked = false;
  final variants = <String>[wechatImageMark, '[图]', '［图］', '[图片]', '（图）'];
  for (final mark in variants) {
    if (text.endsWith(mark)) {
      text = text.substring(0, text.length - mark.length).trimRight();
      marked = true;
      break;
    }
  }
  return (text: text, withImage: marked);
}

/// 私聊「已读不回」暗号：模型决定这轮不搭理时，只输出这个标记。
/// 它在建消息之前就被认出来并整轮丢掉，绝不写进聊天记录。
const String wechatNoReplyMark = '[[不回]]';

bool wechatHasNoReplyMark(String raw) {
  final text = raw.trimLeft();
  const variants = <String>[
    wechatNoReplyMark,
    '［［不回］］',
    '[[不理]]',
    '[[不搭理]]',
    '[[沉默]]',
  ];
  for (final mark in variants) {
    if (text.startsWith(mark)) return true;
  }
  return false;
}

/// 私聊不搭理人的强度。全局默认开，每个角色可在角色管理里单独关。
enum WechatNoReplyStrength { low, mid, high }

extension WechatNoReplyStrengthX on WechatNoReplyStrength {
  String get label => switch (this) {
    WechatNoReplyStrength.low => '偶尔',
    WechatNoReplyStrength.mid => '看心情',
    WechatNoReplyStrength.high => '经常',
  };

  String get hint => switch (this) {
    WechatNoReplyStrength.low => '大部分时候都会回',
    WechatNoReplyStrength.mid => '烦了、忙了就可能不回',
    WechatNoReplyStrength.high => '懒得搭理的时候很多',
  };

  /// 概率直接拍板「这一轮不回」的基础概率。
  double get chance => switch (this) {
    WechatNoReplyStrength.low => 0.15,
    WechatNoReplyStrength.mid => 0.35,
    WechatNoReplyStrength.high => 0.6,
  };

  static WechatNoReplyStrength parse(Object? raw) {
    final value = (raw ?? '').toString();
    for (final item in WechatNoReplyStrength.values) {
      if (item.name == value) return item;
    }
    return WechatNoReplyStrength.low;
  }
}

/// 通讯录里的一个人。**手动添加**，不会自己从世界书灌进来。
///
/// 人设正文还是去世界书取（entryId + bookId 定位）；
/// 头像不在这里存，直接读朋友圈那份（`moment.assets`，键是同名），
/// 所以两边改头像天然同步，不用额外对账。
class WechatContact {
  const WechatContact({
    required this.name,
    this.entryId = '',
    this.bookId = '',
    this.providerKey,
    this.modelId,
    this.intervalPreset = WechatIntervalPreset.follow,
    this.customMinSeconds = 2,
    this.customMaxSeconds = 12,
    this.noReplyEnabled = true,
    this.noReplyStrength = WechatNoReplyStrength.low,
    this.addedAt = 0,
  });

  /// 唯一键，也是消息里的“谁说的”。
  final String name;

  /// 世界书条目的 id + 来源书，用来取人设正文。
  final String entryId;
  final String bookId;

  /// 这个角色自己的模型；空 = 跟随当前场景（群的默认 / 全局）。
  final String? providerKey;
  final String? modelId;

  /// 私聊里他回你一句要磨多久。跟群聊的间隔是分开的两套。
  final WechatIntervalPreset intervalPreset;
  final int customMinSeconds;
  final int customMaxSeconds;

  /// 私聊时这个人会不会偶尔已读不回。默认开；显式存了 false 才是关。
  final bool noReplyEnabled;
  final WechatNoReplyStrength noReplyStrength;

  final int addedAt;

  WechatContact copyWith({
    String? name,
    String? entryId,
    String? bookId,
    String? providerKey,
    String? modelId,
    WechatIntervalPreset? intervalPreset,
    int? customMinSeconds,
    int? customMaxSeconds,
    bool? noReplyEnabled,
    WechatNoReplyStrength? noReplyStrength,
    bool clearModel = false,
  }) {
    return WechatContact(
      name: name ?? this.name,
      entryId: entryId ?? this.entryId,
      bookId: bookId ?? this.bookId,
      providerKey: clearModel ? null : (providerKey ?? this.providerKey),
      modelId: clearModel ? null : (modelId ?? this.modelId),
      intervalPreset: intervalPreset ?? this.intervalPreset,
      customMinSeconds: customMinSeconds ?? this.customMinSeconds,
      customMaxSeconds: customMaxSeconds ?? this.customMaxSeconds,
      noReplyEnabled: noReplyEnabled ?? this.noReplyEnabled,
      noReplyStrength: noReplyStrength ?? this.noReplyStrength,
      addedAt: addedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    if (entryId.isNotEmpty) 'entry': entryId,
    if (bookId.isNotEmpty) 'book': bookId,
    if (providerKey != null) 'provider': providerKey,
    if (modelId != null) 'model': modelId,
    'interval': intervalPreset.name,
    'min': customMinSeconds,
    'max': customMaxSeconds,
    // 总是写死当前值：默认开，关掉要存 false，老数据缺字段时按开处理。
    'noReply': noReplyEnabled,
    'noReplyStrength': noReplyStrength.name,
    'at': addedAt,
  };

  static WechatContact? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = (raw['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;
    final provider = raw['provider'];
    final model = raw['model'];
    return WechatContact(
      name: name,
      entryId: (raw['entry'] ?? '').toString(),
      bookId: (raw['book'] ?? '').toString(),
      providerKey: provider is String && provider.isNotEmpty ? provider : null,
      modelId: model is String && model.isNotEmpty ? model : null,
      intervalPreset: WechatIntervalPresetX.parse(raw['interval']),
      customMinSeconds: _intOr(raw['min'], 2),
      customMaxSeconds: _intOr(raw['max'], 12),
      // 只有显式存了 false 才是关；老数据缺字段一律按「开」处理。
      noReplyEnabled: raw['noReply'] != false,
      noReplyStrength: WechatNoReplyStrengthX.parse(raw['noReplyStrength']),
      addedAt: _intOr(raw['at'], 0),
    );
  }

  /// 群成员也能当联系人用（迁移和查模型时省一次转换）。
  WechatMember toMember() => WechatMember(
    name: name,
    entryId: entryId,
    bookId: bookId,
    providerKey: providerKey,
    modelId: modelId,
  );

  static WechatContact ofMember(WechatMember member) => WechatContact(
    name: member.name,
    entryId: member.entryId,
    bookId: member.bookId,
    providerKey: member.providerKey,
    modelId: member.modelId,
  );
}

List<WechatContact> wechatContactsFromExtras(Map<String, dynamic>? extras) {
  final raw = extras?[wechatContactsKey];
  if (raw is! List) return const <WechatContact>[];
  final out = <WechatContact>[];
  for (final item in raw) {
    final contact = WechatContact.fromJson(item);
    if (contact != null) out.add(contact);
  }
  return out;
}

const String wechatSettingsKey = 'wechat.settings';

/// 微信自己的全局设置（跟「设置 → 默认模型」那套无关）。
///
/// 放四样：通讯录/私聊用哪几本世界书、我的马甲名、**世界观**（手写的系统提示）、
/// 以及新建群继承的那份默认发言间隔。
class WechatSettings {
  const WechatSettings({
    this.bookIds = const <String>[],
    this.persona = '',
    this.worldPrompt = '',
    // 全局自己这份不能是 follow（会自己指自己），只能是具体档位。
    this.intervalPreset = WechatIntervalPreset.normal,
    this.customMinSeconds = 4,
    this.customMaxSeconds = 30,
    this.burstPreset = WechatBurstPreset.natural,
  });

  /// 通讯录添加人、私聊生成都用这几本世界书（群聊各有自己的一份）。
  final List<String> bookIds;

  /// 我在微信里的名字。空 = 叫「我」。
  final String persona;

  /// 世界观：手写的设定，往群聊和私聊的系统提示里都塞一段。
  /// 跟世界书是两条路——世界书按条目给，这里是想写什么写什么。
  final String worldPrompt;

  /// 新建群的默认发言间隔。群建好后仍可在群设置里单独改。
  final WechatIntervalPreset intervalPreset;
  final int customMinSeconds;
  final int customMaxSeconds;

  /// 一次回几条的概率档。群聊和私聊共用。
  final WechatBurstPreset burstPreset;

  String get effectivePersona {
    final value = persona.trim();
    return value.isEmpty ? '我' : value;
  }

  WechatSettings copyWith({
    List<String>? bookIds,
    String? persona,
    String? worldPrompt,
    WechatIntervalPreset? intervalPreset,
    int? customMinSeconds,
    int? customMaxSeconds,
    WechatBurstPreset? burstPreset,
  }) {
    return WechatSettings(
      bookIds: bookIds ?? this.bookIds,
      persona: persona ?? this.persona,
      worldPrompt: worldPrompt ?? this.worldPrompt,
      intervalPreset: intervalPreset ?? this.intervalPreset,
      customMinSeconds: customMinSeconds ?? this.customMinSeconds,
      customMaxSeconds: customMaxSeconds ?? this.customMaxSeconds,
      burstPreset: burstPreset ?? this.burstPreset,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'books': bookIds,
    'persona': persona,
    'world': worldPrompt,
    'interval': intervalPreset.name,
    'min': customMinSeconds,
    'max': customMaxSeconds,
    'burst': burstPreset.name,
  };

  static WechatSettings fromJson(Object? raw) {
    if (raw is! Map) return const WechatSettings();
    final booksRaw = raw['books'];
    final books = <String>[];
    if (booksRaw is List) {
      for (final item in booksRaw) {
        final value = item.toString().trim();
        if (value.isNotEmpty) books.add(value);
      }
    }
    return WechatSettings(
      bookIds: books,
      persona: (raw['persona'] ?? '').toString(),
      worldPrompt: (raw['world'] ?? '').toString(),
      intervalPreset: WechatIntervalPresetX.parse(raw['interval']),
      customMinSeconds: _intOr(raw['min'], 4),
      customMaxSeconds: _intOr(raw['max'], 30),
      burstPreset: WechatBurstPresetX.parse(raw['burst']),
    );
  }
}

WechatSettings wechatSettingsFromExtras(Map<String, dynamic>? extras) =>
    WechatSettings.fromJson(extras?[wechatSettingsKey]);

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

/// 消息落地前短暂亮一下「正在输入」的时长。
///
/// 等待间隔和模型生成期间都不亮，只在消息马上要出现时亮这一下，
/// 免得气泡一直挂着三个点、看着像秒回或者一直在生成。
const Duration wechatTypingCue = Duration(milliseconds: 1100);

/// 一次回几条的概率档。
///
/// 不管哪档，一条都是最多的；档位只决定连发越往后的条数有多罕见。
enum WechatBurstPreset { quiet, natural, lively }

extension WechatBurstPresetX on WechatBurstPreset {
  String get label => switch (this) {
    WechatBurstPreset.quiet => '偏单条',
    WechatBurstPreset.natural => '自然',
    WechatBurstPreset.lively => '爱连发',
  };

  String get hint => switch (this) {
    WechatBurstPreset.quiet => '一条为主，偶尔两条',
    WechatBurstPreset.natural => '一条最多，两三条偶尔',
    WechatBurstPreset.lively => '一条仍最多，能连到六七条',
  };

  /// 1~7 条的权重，按概率抽。
  List<double> get weights => switch (this) {
    WechatBurstPreset.quiet => <double>[82, 13, 3.5, 1, 0.5, 0, 0],
    WechatBurstPreset.natural => <double>[58, 24, 11, 5, 1.5, 0.5, 0],
    WechatBurstPreset.lively => <double>[40, 29, 17, 8, 3.5, 1.5, 1],
  };

  static WechatBurstPreset parse(Object? raw) {
    final value = (raw ?? '').toString();
    for (final item in WechatBurstPreset.values) {
      if (item.name == value) return item;
    }
    return WechatBurstPreset.natural;
  }
}

/// 从档位里抽这次要发几条，返回 1~7。
int wechatBurstCount(WechatBurstPreset preset, Random random) {
  final weights = preset.weights;
  var total = 0.0;
  for (final weight in weights) {
    total += weight;
  }
  if (total <= 0) return 1;
  var roll = random.nextDouble() * total;
  for (var i = 0; i < weights.length; i++) {
    roll -= weights[i];
    if (roll <= 0) return i + 1;
  }
  return weights.length;
}

/// 发言间隔的预设。
enum WechatIntervalPreset { follow, fast, normal, slow, random, custom }

extension WechatIntervalPresetX on WechatIntervalPreset {
  /// 只有群 / 私聊能选「跟随全局」；全局自己那份不列这个档。
  static const List<WechatIntervalPreset> own = <WechatIntervalPreset>[
    WechatIntervalPreset.fast,
    WechatIntervalPreset.normal,
    WechatIntervalPreset.slow,
    WechatIntervalPreset.random,
    WechatIntervalPreset.custom,
  ];

  String get label => switch (this) {
    WechatIntervalPreset.follow => '跟随全局',
    WechatIntervalPreset.fast => '秒回',
    WechatIntervalPreset.normal => '正常',
    WechatIntervalPreset.slow => '慢',
    WechatIntervalPreset.random => '完全随机',
    WechatIntervalPreset.custom => '自定义',
  };

  String get hint => switch (this) {
    WechatIntervalPreset.follow => '用设置里那份',
    WechatIntervalPreset.fast => '0.5 ~ 3 秒',
    WechatIntervalPreset.normal => '4 ~ 30 秒',
    WechatIntervalPreset.slow => '40 秒 ~ 4 分钟',
    WechatIntervalPreset.random => '1 秒 ~ 5 分钟',
    WechatIntervalPreset.custom => '自己填上下限',
  };

  /// 实际落到的秒数区间。
  ///
  /// `follow` 在这里没意义（真正算之前会被换掉），给 normal 兜底，
  /// 万一哪处忘了换也不至于崩。
  ({int min, int max}) get range => switch (this) {
    WechatIntervalPreset.follow => (min: 4, max: 30),
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

/// 真正拿来用的间隔：选了「跟随全局」就换成全局那份。
///
/// 群 / 私聊都可能选 follow，算延迟和显示文字之前都先过一遍这里，
/// 免得两处各写一遍判断、改一处忘一处。
({WechatIntervalPreset preset, int min, int max}) wechatEffectiveInterval(
  WechatIntervalPreset preset, {
  int customMinSeconds = 3,
  int customMaxSeconds = 30,
  WechatSettings? settings,
}) {
  if (preset == WechatIntervalPreset.follow) {
    if (settings == null) {
      return (
        preset: WechatIntervalPreset.normal,
        min: customMinSeconds,
        max: customMaxSeconds,
      );
    }
    return (
      preset: settings.intervalPreset,
      min: settings.customMinSeconds,
      max: settings.customMaxSeconds,
    );
  }
  return (preset: preset, min: customMinSeconds, max: customMaxSeconds);
}

/// 一个间隔预设算出来的等待时间。
///
/// 群聊（全局 / 单群）和私聊（单角色）共用一个算法，
/// 免得三处各写一遍、改一处忘两处。
Duration wechatDelayOf(
  WechatIntervalPreset preset, {
  int customMinSeconds = 3,
  int customMaxSeconds = 30,
  required Random random,
}) {
  final range = preset.range;
  var lo = range.min;
  var hi = range.max;
  if (preset == WechatIntervalPreset.custom) {
    lo = customMinSeconds.clamp(0, 3600);
    hi = customMaxSeconds.clamp(lo, 3600);
  }
  if (hi <= lo) return Duration(seconds: lo);
  // 不均等分布：多数落在前段，偶尔拖很久，比死板均匀更像真人。
  final span = hi - lo;
  final skewed = pow(random.nextDouble(), 1.7).toDouble();
  return Duration(seconds: lo + (skewed * span).round());
}

/// 设置行右边显示的那句话：「正常 · 4~30 秒」。
String wechatIntervalLabel(
  WechatIntervalPreset preset, {
  int customMinSeconds = 3,
  int customMaxSeconds = 30,
  WechatSettings? settings,
}) {
  if (preset == WechatIntervalPreset.follow) {
    final effective = wechatEffectiveInterval(
      preset,
      customMinSeconds: customMinSeconds,
      customMaxSeconds: customMaxSeconds,
      settings: settings,
    );
    final inner = wechatIntervalLabel(
      effective.preset,
      customMinSeconds: effective.min,
      customMaxSeconds: effective.max,
    );
    return '跟随全局 · $inner';
  }
  if (preset != WechatIntervalPreset.custom) return preset.label;
  final lo = customMinSeconds.clamp(0, 3600);
  final hi = customMaxSeconds.clamp(lo, 3600);
  return '自定义 · $lo~$hi 秒';
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
    this.owner = '',
    this.groupPrompt = '',
    this.autoTopic = false,
    this.intervalPreset = WechatIntervalPreset.follow,
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

  /// 群主（成员名）。空 = 群主是我。建群时定，之后不改。
  /// 只是名义：拉人/踢人以他的名字发系统消息，我没有真的让出权限。
  final String owner;

  /// 这个群自己的提示词：定主题/风格（比如「要抓马、别聊家常」）。
  /// 生成群聊消息时注入 system，只对这个群生效。
  final String groupPrompt;

  /// 话题锚开关：开了就把当前话题一并注入，让角色围着这个话题聊、别岔回日常事务。
  final bool autoTopic;

  final WechatIntervalPreset intervalPreset;
  final int customMinSeconds;
  final int customMaxSeconds;

  /// 群默认模型；某个成员没单独绑就用这个。
  final String? providerKey;
  final String? modelId;

  final int createdAt;

  /// 这个间隔预设下，随机出来的一段时间。
  ///
  /// 选了「跟随全局」时要传 [settings]（微信那份全局设置），
  /// 不然拿不到全局的档位，只能按「正常」算。
  Duration nextDelay(Random random, {WechatSettings? settings}) {
    final effective = wechatEffectiveInterval(
      intervalPreset,
      customMinSeconds: customMinSeconds,
      customMaxSeconds: customMaxSeconds,
      settings: settings,
    );
    return wechatDelayOf(
      effective.preset,
      customMinSeconds: effective.min,
      customMaxSeconds: effective.max,
      random: random,
    );
  }

  /// 群里一共几个人。**含我自己**：界面上写「4 人」是三个人加我一个。
  int get memberCount => members.length + 1;

  String get effectivePersona {
    final value = persona.trim();
    return value.isEmpty ? '我' : value;
  }

  /// 群主显示名。空 = 我自己。
  String get effectiveOwner {
    final value = owner.trim();
    return value.isEmpty ? effectivePersona : value;
  }

  WechatGroup copyWith({
    String? name,
    List<WechatMember>? members,
    List<String>? bookIds,
    String? persona,
    String? divine,
    String? owner,
    String? groupPrompt,
    bool? autoTopic,
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
      owner: owner ?? this.owner,
      groupPrompt: groupPrompt ?? this.groupPrompt,
      autoTopic: autoTopic ?? this.autoTopic,
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
    'owner': owner,
    'groupPrompt': groupPrompt,
    'autoTopic': autoTopic,
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
      owner: (raw['owner'] ?? '').toString(),
      groupPrompt: (raw['groupPrompt'] ?? '').toString(),
      autoTopic: raw['autoTopic'] == true,
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
    this.recalled = false,
    this.withImage = false,
    this.plot = false,
    this.heartVoice = '',
    this.snapshot = '',
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

  /// 撤回过的。正文会一起清空（原文不留），只渲染成一句灰字。
  final bool recalled;

  /// 这条带图。图按 [text] 里的词拼 emoji——跟朋友圈一套逻辑。
  final bool withImage;

  /// 旧的「控制剧情走向」旁白标记，仅用于老数据仍能显示，现不再新写。
  final bool plot;

  /// 这条消息生成时一并存下的心声（口是心非的真实想法）。空 = 没有。
  /// 只有开了心声的角色、且是角色本人发的才有；我发的/夺舍替人说的没有。
  final String heartVoice;

  /// 转发的「模拟聊天截图」内容（JSON 字符串：来源 + 若干对话行）。
  /// 非空时这条消息渲染成一张聊天截图卡片，AI 上下文里标明这是转发的截图。
  final String snapshot;

  WechatMessage copyWith({
    String? sender,
    String? text,
    int? at,
    bool? recalled,
    bool? withImage,
    String? heartVoice,
  }) {
    return WechatMessage(
      id: id,
      sender: sender ?? this.sender,
      text: text ?? this.text,
      at: at ?? this.at,
      system: system,
      mine: mine,
      divine: divine,
      recalled: recalled ?? this.recalled,
      withImage: withImage ?? this.withImage,
      plot: plot,
      heartVoice: heartVoice ?? this.heartVoice,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'sender': sender,
    'text': text,
    'at': at,
    if (system) 'sys': true,
    if (mine) 'mine': true,
    if (divine) 'divine': true,
    if (recalled) 'recalled': true,
    if (withImage) 'img': true,
    if (plot) 'plot': true,
    if (heartVoice.isNotEmpty) 'heart': heartVoice,
    if (snapshot.isNotEmpty) 'snap': snapshot,
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
      recalled: raw['recalled'] == true,
      withImage: raw['img'] == true,
      plot: raw['plot'] == true,
      heartVoice: (raw['heart'] ?? '').toString(),
      snapshot: (raw['snap'] ?? '').toString(),
    );
  }
}

/// 一条转发的模拟聊天截图内容。
/// [from] 是来源标注（例：转自「相亲群」/ 转自「张三」），[lines] 是画面里的对话行。
class WechatSnapshot {
  const WechatSnapshot({required this.from, required this.lines});

  final String from;
  final List<String> lines;

  String encode() => jsonEncode(<String, dynamic>{
        'from': from,
        'lines': lines,
      });

  static WechatSnapshot? decode(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final lines = <String>[];
      final rawLines = decoded['lines'];
      if (rawLines is List) {
        for (final line in rawLines) {
          final text = line.toString();
          if (text.trim().isNotEmpty) lines.add(text);
        }
      }
      if (lines.isEmpty) return null;
      return WechatSnapshot(
        from: (decoded['from'] ?? '').toString(),
        lines: lines,
      );
    } catch (_) {
      return null;
    }
  }

  /// 给模型看的那一句：明确这是转发的截图，不是当场说的话。
  String toPromptLine() {
    final source = from.trim().isEmpty ? '' : '（$from）';
    return '发来一张聊天截图$source，截图里是：${lines.join(' / ')}';
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
