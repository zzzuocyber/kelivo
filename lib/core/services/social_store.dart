import 'dart:convert';

import '../models/conversation.dart';
import 'chat/chat_service.dart';
import 'social_affinity.dart';

// ---------------------------------------------------------------------------
// 社交共享状态。
//
// 朋友圈、微信群聊、微信私聊三个模块共用这一份数据：角色作息、话题指令、
// 自动回复开关、记忆喂法（摘要/完整）和 token 统计都挂这里。
// 三处生成提示词时都从同一个 store 读，所以同一时刻同一个角色的地点/
// 状态只有一份，不会出现「这边在公司那边在家」。
//
// 跟微信/朋友圈一样塞进一条隐藏对话的 extras，备份导出自动跟随。
// ---------------------------------------------------------------------------

const String socialHiddenKey = 'social.hidden';
const String socialSchedulesKey = 'social.schedules';
const String socialTopicsKey = 'social.topics';
const String socialAutoReplyKey = 'social.autoreply';
const String socialContextModeKey = 'social.contextmode';
const String socialDirectiveKey = 'social.directive';
const String socialTokensKey = 'social.tokens';
const String socialAffinityKey = 'social.affinity';
const String socialSeenKey = 'social.seen';
const String socialSummaryKey = 'social.summary';
const String socialCompressPromptKey = 'social.compressprompt';
const String socialPlotLogKey = 'social.plotlog';
const String socialWorldClockKey = 'social.worldclock';
const String socialHeartVoiceKey = 'social.heartvoice';
const String socialContainerTitle = '社交状态';

/// 故事世界的时间坐标。
///
/// 三场景（群聊/私聊/朋友圈）和离线补算都读这一个，不再各取手机的 DateTime.now()。
/// 存一对锚点：把某个真实时刻 [realAnchor] 对应到故事时刻 [storyAnchor]，于是
///   故事现在 = storyAnchor + (真实现在 − realAnchor)
/// 这样设定后时间照常往前流；[advance] 只需往前挪 storyAnchor。
/// 没有存过（老数据/未设置）时用 [followReal] = true，直接等于真实时间。
class SocialWorldClock {
  const SocialWorldClock({
    required this.followReal,
    required this.realAnchor,
    required this.storyAnchor,
  });

  /// true = 直接用手机真实时间；false = 用故事锚点推算。
  final bool followReal;
  final int realAnchor;
  final int storyAnchor;

  static SocialWorldClock real() => SocialWorldClock(
        followReal: true,
        realAnchor: 0,
        storyAnchor: 0,
      );

  /// 把真实时刻换算成故事时刻。
  DateTime at(DateTime real) {
    if (followReal) return real;
    final delta = real.millisecondsSinceEpoch - realAnchor;
    return DateTime.fromMillisecondsSinceEpoch(storyAnchor + delta);
  }

  /// 故事里的「现在」。
  DateTime now() => at(DateTime.now());

  /// 从真实时刻反推故事时刻（离线补算用：把过去的真实时间戳换算过去）。
  DateTime storyTimeFromRealMillis(int millis) =>
      at(DateTime.fromMillisecondsSinceEpoch(millis));

  Map<String, dynamic> toJson() => <String, dynamic>{
        'follow': followReal,
        'real': realAnchor,
        'story': storyAnchor,
      };

  static SocialWorldClock fromJson(Object? raw) {
    if (raw is! Map) return real();
    final follow = raw['follow'] != false;
    final realAnchor = _clockIntOr(raw['real'], 0);
    final storyAnchor = _clockIntOr(raw['story'], 0);
    if (follow || realAnchor <= 0 || storyAnchor <= 0) return real();
    return SocialWorldClock(
      followReal: false,
      realAnchor: realAnchor,
      storyAnchor: storyAnchor,
    );
  }

  static int _clockIntOr(Object? value, int fallback) {
    if (value is num) return value.round();
    return int.tryParse('$value') ?? fallback;
  }
}

/// 把故事时间写成一句给模型看的中文，明确到星期和上午/下午/晚上。
String socialTimeLine(DateTime storyNow) {
  const weeks = <String>['一', '二', '三', '四', '五', '六', '日'];
  final week = weeks[storyNow.weekday - 1];
  final hour = storyNow.hour;
  final String period;
  if (hour < 5) {
    period = '凌晨';
  } else if (hour < 12) {
    period = '上午';
  } else if (hour < 13) {
    period = '中午';
  } else if (hour < 18) {
    period = '下午';
  } else {
    period = '晚上';
  }
  final hh = hour.toString().padLeft(2, '0');
  final mm = storyNow.minute.toString().padLeft(2, '0');
  return '现在的故事时间：${storyNow.month}月${storyNow.day}日 '
      '星期$week $period$hh:$mm。';
}

/// 压缩词的预设内容：只作手写「剧情概括」时的填写参考，不喂给模型。
const String kDefaultCompressPrompt = '写一份剧情概括，供群聊/私聊/朋友圈共用：\n'
    '1. 现在最重要的事/冲突是什么；\n'
    '2. 谁和谁是什么关系、最近发生了什么；\n'
    '3. 各自的性格和说话方式要点；\n'
    '4. 还在进行、没结掉的事。\n'
    '只写要点，别写成流水账。';

/// 一周里的某一天，跟 DateTime.weekday 一致：1=周一 … 7=周日。
const List<int> kSocialAllDays = <int>[1, 2, 3, 4, 5, 6, 7];

/// 一条作息规则：每周的 [days] 里，从 [startHour] 到 [endHour] 这个时段，
/// 角色在 [location] 做 [activity]，[available] 表示这时候方不方便聊天。
///
/// [endHour] 可以小于 [startHour] 表示跨过午夜（例如 22 点到次日 7 点睡觉）。
class SocialTimeSlot {
  const SocialTimeSlot({
    required this.days,
    required this.startHour,
    required this.endHour,
    required this.location,
    required this.activity,
    this.available = true,
  });

  final List<int> days;
  final int startHour;
  final int endHour;
  final String location;
  final String activity;
  final bool available;

  bool matches(DateTime now) {
    if (!days.contains(now.weekday)) return false;
    final hour = now.hour;
    if (startHour == endHour) return true;
    if (startHour < endHour) {
      return hour >= startHour && hour < endHour;
    }
    // 跨午夜：22~7 命中 hour>=22 或 hour<7。
    return hour >= startHour || hour < endHour;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'days': days,
        'start': startHour,
        'end': endHour,
        'loc': location,
        'act': activity,
        'avail': available,
      };

  static SocialTimeSlot? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final daysRaw = raw['days'];
    final days = <int>[];
    if (daysRaw is List) {
      for (final value in daysRaw) {
        final day = value is num ? value.round() : int.tryParse('$value');
        if (day != null && day >= 1 && day <= 7 && !days.contains(day)) {
          days.add(day);
        }
      }
    }
    if (days.isEmpty) days.addAll(kSocialAllDays);
    final start = _hourOr(raw['start'], 9);
    final end = _hourOr(raw['end'], 18);
    return SocialTimeSlot(
      days: days,
      startHour: start,
      endHour: end,
      location: (raw['loc'] ?? '').toString(),
      activity: (raw['act'] ?? '').toString(),
      available: raw['avail'] != false,
    );
  }

  static int _hourOr(Object? value, int fallback) {
    final hour = value is num ? value.round() : int.tryParse('$value');
    if (hour == null || hour < 0 || hour > 24) return fallback;
    return hour;
  }
}

/// 某个角色此刻的去向，注入提示词让三个场景保持一致。
class SocialWhereabouts {
  const SocialWhereabouts({
    required this.name,
    required this.location,
    required this.activity,
    required this.available,
    required this.fromSchedule,
  });

  final String name;
  final String location;
  final String activity;
  final bool available;
  final bool fromSchedule;

  /// 给模型看的一句话。没有作息设定时也明说，免得模型脑补出固定地点。
  String get promptLine {
    if (!fromSchedule) {
      return '$name现在没有固定的去向设定，按你们正在聊的事自行判断他在哪、在做什么。';
    }
    final where = location.trim().isEmpty ? '某个地方' : location.trim();
    final doing = activity.trim().isEmpty ? '没什么特别的事' : activity.trim();
    final state = available ? '这时候有空聊天' : '这时候通常不方便聊天';
    return '$name这会儿在$where，$doing。$state。';
  }
}

/// 话题状态。三个作用域：群 `group:<id>`、私聊 `dm:<名字>`、朋友圈 `moment`。
class SocialTopicState {
  const SocialTopicState({
    this.topic = '',
    this.active = false,
    this.cooldownUntil = 0,
  });

  final String topic;
  final bool active;
  final int cooldownUntil;

  bool get isCoolingDown =>
      cooldownUntil > 0 &&
      DateTime.now().millisecondsSinceEpoch < cooldownUntil;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'topic': topic,
        'active': active,
        'until': cooldownUntil,
      };

  static SocialTopicState? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return SocialTopicState(
      topic: (raw['topic'] ?? '').toString(),
      active: raw['active'] == true,
      cooldownUntil: raw['until'] is num
          ? (raw['until'] as num).round()
          : int.tryParse('${raw['until']}') ?? 0,
    );
  }
}

/// 一次性天意指令：写进去后，下一次生成时取走并清掉。
/// [kind] 是 summon / switch_topic / end_topic / cooldown / none；
/// [who] 是召唤时指定的角色，其他指令留空。
/// [text] 是「控制剧情走向」时我手写的剧情文字，只有 plot 这类指令用。
class SocialDirective {
  const SocialDirective({this.kind = 'none', this.who = '', this.text = ''});

  final String kind;
  final String who;
  final String text;

  bool get isNone => kind.isEmpty || kind == 'none';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': kind,
        'who': who,
        'text': text,
      };

  static SocialDirective? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return SocialDirective(
      kind: (raw['kind'] ?? 'none').toString(),
      who: (raw['who'] ?? '').toString(),
      text: (raw['text'] ?? '').toString(),
    );
  }

  static const SocialDirective none = SocialDirective();
}

/// 记忆喂给模型的方式：完整原文，或者摘要。
enum SocialContextMode { full, summary }

extension SocialContextModeX on SocialContextMode {
  String get wire => this == SocialContextMode.summary ? 'summary' : 'full';
  bool get isSummary => this == SocialContextMode.summary;

  static SocialContextMode parse(Object? raw) =>
      raw == 'summary' ? SocialContextMode.summary : SocialContextMode.full;
}

class SocialTokenStats {
  const SocialTokenStats({
    this.moment = 0,
    this.group = 0,
    this.dm = 0,
  });

  final int moment;
  final int group;
  final int dm;

  int get total => moment + group + dm;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'moment': moment,
        'group': group,
        'dm': dm,
      };

  static SocialTokenStats fromJson(Object? raw) {
    if (raw is! Map) return const SocialTokenStats();
    return SocialTokenStats(
      moment: _intOr(raw['moment']),
      group: _intOr(raw['group']),
      dm: _intOr(raw['dm']),
    );
  }

  static int _intOr(Object? value) =>
      value is num ? value.round() : int.tryParse('$value') ?? 0;
}

String socialGroupScope(String groupId) => 'group:$groupId';
String socialDmScope(String name) => 'dm:${name.trim()}';
const String socialMomentScope = 'moment';

/// 三个场景的读写口子。方法都是 async，直接对着隐藏对话的 extras 操作。
class SocialStore {
  SocialStore(this.chat);

  final ChatService chat;

  Conversation? findConversation() {
    final all = chat.getAllConversations();
    for (final conversation in all) {
      if (conversation.extras[socialHiddenKey] == true) {
        return chat.getConversation(conversation.id) ?? conversation;
      }
    }
    for (final conversation in all) {
      final extras = conversation.extras;
      final looksLikeOurs = extras.containsKey(socialSchedulesKey) ||
          extras.containsKey(socialTopicsKey) ||
          extras.containsKey(socialTokensKey) ||
          extras.containsKey(socialDirectiveKey) ||
          extras.containsKey(socialContextModeKey) ||
          extras.containsKey(socialAffinityKey) ||
          extras.containsKey(socialSeenKey) ||
          extras.containsKey(socialSummaryKey) ||
          extras.containsKey(socialCompressPromptKey) ||
          extras.containsKey(socialPlotLogKey) ||
          extras.containsKey(socialWorldClockKey) ||
          extras.containsKey(socialHeartVoiceKey);
      if (!looksLikeOurs) continue;
      return chat.getConversation(conversation.id) ?? conversation;
    }
    return null;
  }

  Future<String> ensureConversation() async {
    final existing = findConversation();
    if (existing != null) {
      if (conversationIsSocial(existing)) return existing.id;
      try {
        await chat.updateConversationExtras(existing.id, (extras) {
          final next = Map<String, dynamic>.from(extras);
          next[socialHiddenKey] = true;
          return next;
        });
      } catch (_) {
        // 补标失败也还能用。
      }
      return existing.id;
    }
    final created = await chat.createConversation(
      title: socialContainerTitle,
      activate: false,
    );
    await chat.updateConversationExtras(created.id, (extras) {
      final next = Map<String, dynamic>.from(extras);
      next[socialHiddenKey] = true;
      return next;
    });
    return created.id;
  }

  Future<void> _update(
      Map<String, dynamic> Function(Map<String, dynamic> extras) update) async {
    final id = await ensureConversation();
    await chat.updateConversationExtras(id, update);
  }

  Map<String, dynamic> get _extras => findConversation()?.extras ?? {};

  // ---------------- 作息表 ----------------

  Map<String, List<SocialTimeSlot>> schedules() {
    final raw = _extras[socialSchedulesKey];
    final out = <String, List<SocialTimeSlot>>{};
    if (raw is! Map) return out;
    raw.forEach((key, value) {
      final name = key.toString();
      final slots = <SocialTimeSlot>[];
      if (value is List) {
        for (final item in value) {
          final slot = SocialTimeSlot.fromJson(item);
          if (slot != null) slots.add(slot);
        }
      }
      out[name] = slots;
    });
    return out;
  }

  List<SocialTimeSlot> scheduleFor(String name) =>
      schedules()[name.trim()] ?? const <SocialTimeSlot>[];

  Future<void> setSchedule(String name, List<SocialTimeSlot> slots) async {
    final key = name.trim();
    if (key.isEmpty) return;
    await _update((extras) {
      final next = Map<String, dynamic>.from(extras);
      final raw = Map<String, dynamic>.from(
        next[socialSchedulesKey] is Map ? next[socialSchedulesKey] as Map : {},
      );
      if (slots.isEmpty) {
        raw.remove(key);
      } else {
        raw[key] = slots.map((slot) => slot.toJson()).toList(growable: false);
      }
      next[socialSchedulesKey] = raw;
      return next;
    });
  }

  /// 取某角色此刻的去向。按表的顺序匹配第一条命中的规则。
  /// 默认用故事时间坐标，不再取手机真实时间——三场景因此始终对得上。
  SocialWhereabouts whereabouts(String name, {DateTime? now}) {
    final moment = now ?? storyNow();
    final slots = scheduleFor(name);
    for (final slot in slots) {
      if (slot.matches(moment)) {
        return SocialWhereabouts(
          name: name,
          location: slot.location,
          activity: slot.activity,
          available: slot.available,
          fromSchedule: true,
        );
      }
    }
    return SocialWhereabouts(
      name: name,
      location: '',
      activity: '',
      available: true,
      fromSchedule: false,
    );
  }

  /// 这段时间该角色方不方便被召唤。没设定就当作有空。
  bool isAvailable(String name, {DateTime? now}) =>
      whereabouts(name, now: now).available;

  // ---------------- 话题 ----------------

  Map<String, SocialTopicState> topics() {
    final raw = _extras[socialTopicsKey];
    final out = <String, SocialTopicState>{};
    if (raw is! Map) return out;
    raw.forEach((key, value) {
      final state = SocialTopicState.fromJson(value);
      if (state != null) out[key.toString()] = state;
    });
    return out;
  }

  SocialTopicState topic(String scope) =>
      topics()[scope] ?? const SocialTopicState();

  Future<void> setTopic(String scope, String topic, {Duration cool = Duration.zero}) async {
    await _update((extras) {
      final next = Map<String, dynamic>.from(extras);
      final raw = Map<String, dynamic>.from(
        next[socialTopicsKey] is Map ? next[socialTopicsKey] as Map : {},
      );
      raw[scope] = SocialTopicState(
        topic: topic.trim(),
        active: true,
        cooldownUntil: cool > Duration.zero
            ? DateTime.now().add(cool).millisecondsSinceEpoch
            : 0,
      ).toJson();
      next[socialTopicsKey] = raw;
      return next;
    });
  }

  /// 结束话题：清掉主题，但不设冷场（冷场是单独的动作）。
  Future<void> endTopic(String scope) async {
    await _update((extras) {
      final next = Map<String, dynamic>.from(extras);
      final raw = Map<String, dynamic>.from(
        next[socialTopicsKey] is Map ? next[socialTopicsKey] as Map : {},
      );
      raw[scope] = SocialTopicState(
        cooldownUntil: (SocialTopicState.fromJson(raw[scope])?.cooldownUntil) ?? 0,
      ).toJson();
      next[socialTopicsKey] = raw;
      return next;
    });
  }

  /// 冷场：一段时间内不要主动发言。
  Future<void> setCooldown(String scope, Duration duration) async {
    await _update((extras) {
      final next = Map<String, dynamic>.from(extras);
      final raw = Map<String, dynamic>.from(
        next[socialTopicsKey] is Map ? next[socialTopicsKey] as Map : {},
      );
      final previous = SocialTopicState.fromJson(raw[scope]) ?? const SocialTopicState();
      raw[scope] = SocialTopicState(
        topic: previous.topic,
        active: previous.active,
        cooldownUntil: DateTime.now().add(duration).millisecondsSinceEpoch,
      ).toJson();
      next[socialTopicsKey] = raw;
      return next;
    });
  }

  /// 结束冷场：立刻清掉冷却，恢复主动发言。
  /// 「结束冷场」按钮、召唤、夺舍回复都会走这里。
  Future<void> clearCooldown(String scope) async {
    await _update((extras) {
      final next = Map<String, dynamic>.from(extras);
      final raw = Map<String, dynamic>.from(
        next[socialTopicsKey] is Map ? next[socialTopicsKey] as Map : {},
      );
      final previous = SocialTopicState.fromJson(raw[scope]) ?? const SocialTopicState();
      raw[scope] = SocialTopicState(
        topic: previous.topic,
        active: previous.active,
        cooldownUntil: 0,
      ).toJson();
      next[socialTopicsKey] = raw;
      return next;
    });
  }

  // ---------------- 自动回复（按群，单群生效） ----------------

  Map<String, bool> autoReplyMap() {
    final raw = _extras[socialAutoReplyKey];
    final out = <String, bool>{};
    if (raw is! Map) return out;
    raw.forEach((key, value) => out[key.toString()] = value == true);
    return out;
  }

  /// 没单独关过的群默认开启自动回复。
  bool autoReply(String groupId) => autoReplyMap()[groupId] ?? true;

  Future<void> setAutoReply(String groupId, bool enabled) async {
    await _update((extras) {
      final next = Map<String, dynamic>.from(extras);
      final raw = Map<String, dynamic>.from(
        next[socialAutoReplyKey] is Map ? next[socialAutoReplyKey] as Map : {},
      );
      raw[groupId] = enabled;
      next[socialAutoReplyKey] = raw;
      return next;
    });
  }

  // ---------------- 记忆喂法 ----------------

  Map<String, SocialContextMode> contextModes() {
    final raw = _extras[socialContextModeKey];
    final out = <String, SocialContextMode>{};
    if (raw is! Map) return out;
    raw.forEach((key, value) {
      out[key.toString()] = SocialContextModeX.parse(value);
    });
    return out;
  }

  SocialContextMode contextMode(String scene) =>
      contextModes()[scene] ?? SocialContextMode.full;

  Future<void> setContextMode(String scene, SocialContextMode mode) async {
    await _update((extras) {
      final next = Map<String, dynamic>.from(extras);
      final raw = Map<String, dynamic>.from(
        next[socialContextModeKey] is Map ? next[socialContextModeKey] as Map : {},
      );
      raw[scene] = mode.wire;
      next[socialContextModeKey] = raw;
      return next;
    });
  }

  // ---------------- 一次性天意指令 ----------------

  SocialDirective directive(String scope) =>
      SocialDirective.fromJson(_extras[socialDirectiveKey] is Map
          ? (_extras[socialDirectiveKey] as Map)[scope]
          : null) ??
      SocialDirective.none;

  /// 写入一条一次性指令，等下一次生成取走。
  /// [text] 只有「控制剧情走向」(plot) 用，传我手写的剧情文字。
  Future<void> setDirective(
    String scope,
    String kind, {
    String who = '',
    String text = '',
  }) async {
    await _update((extras) {
      final next = Map<String, dynamic>.from(extras);
      final raw = Map<String, dynamic>.from(
        next[socialDirectiveKey] is Map ? next[socialDirectiveKey] as Map : {},
      );
      raw[scope] = SocialDirective(kind: kind, who: who, text: text).toJson();
      next[socialDirectiveKey] = raw;
      return next;
    });
  }

  /// 取走并清掉指令。生成前调用，保证只生效一次。
  Future<SocialDirective> takeDirective(String scope) async {
    final value = directive(scope);
    if (value.isNone) return value;
    await _update((extras) {
      final next = Map<String, dynamic>.from(extras);
      final raw = Map<String, dynamic>.from(
        next[socialDirectiveKey] is Map ? next[socialDirectiveKey] as Map : {},
      );
      raw.remove(scope);
      next[socialDirectiveKey] = raw;
      return next;
    });
    return value;
  }

  // ---------------- token 统计 ----------------

  SocialTokenStats tokenStats() =>
      SocialTokenStats.fromJson(_extras[socialTokensKey]);

  /// [scene] 传 moment / group / dm。累计每次实际喂给模型的上下文 token。
  Future<void> addTokens(String scene, int count) async {
    if (count <= 0) return;
    await _update((extras) {
      final next = Map<String, dynamic>.from(extras);
      final current = SocialTokenStats.fromJson(next[socialTokensKey]);
      final updated = SocialTokenStats(
        moment: current.moment + (scene == 'moment' ? count : 0),
        group: current.group + (scene == 'group' ? count : 0),
        dm: current.dm + (scene == 'dm' ? count : 0),
      );
      next[socialTokensKey] = updated.toJson();
      return next;
    });
  }

  Future<void> resetTokens() async {
    await _update((extras) {
      final next = Map<String, dynamic>.from(extras);
      next[socialTokensKey] = const SocialTokenStats().toJson();
      return next;
    });
  }

  // ---------------- 好感度（单向：角色 → 我） ----------------

  Map<String, SocialAffinity> affinities() {
    final raw = _extras[socialAffinityKey];
    final out = <String, SocialAffinity>{};
    if (raw is! Map) return out;
    for (final entry in raw.entries) {
      final affinity = SocialAffinity.fromJson(entry.value);
      if (affinity != null) out[entry.key.toString()] = affinity;
    }
    return out;
  }

  /// 没有档案时给一份默认值（分数 0、颜值 4、状态平淡），不改存储。
  SocialAffinity affinity(String name) =>
      affinities()[name.trim()] ??
      SocialAffinity(name: name.trim());

  Future<void> setAffinity(SocialAffinity value) async {
    final key = value.name.trim();
    if (key.isEmpty) return;
    await _update((extras) {
      final next = Map<String, dynamic>.from(extras);
      final raw = Map<String, dynamic>.from(
        next[socialAffinityKey] is Map
            ? next[socialAffinityKey] as Map
            : <String, dynamic>{},
      );
      raw[key] = value.toJson();
      next[socialAffinityKey] = raw;
      return next;
    });
  }

  /// 给某角色记一次好感度事件（读当前档案 → 套公式 → 写回）。
  /// 同一时刻多次调用会串读同一份档案，UI 层串行 await 即可。
  Future<SocialAffinity> applyAffinityEvent(
    String name,
    AffinityEvent event, {
    String? reason,
  }) async {
    final key = name.trim();
    final current = affinity(key);
    final updated = current.apply(event, reason: reason);
    await setAffinity(updated);
    return updated;
  }

  // ---------------- 心声偷看（按角色，全场景共用一份开关） ----------------

  /// 开了心声的角色名集合。存一份全局名单，群聊/私聊/朋友圈读同一份，
  /// 所以给某角色开了，三个场景到处都带心声；没开的到处都没有。默认全关。
  Set<String> heartVoiceNames() {
    final raw = _extras[socialHeartVoiceKey];
    final out = <String>{};
    if (raw is! List) return out;
    for (final value in raw) {
      final name = value.toString().trim();
      if (name.isNotEmpty) out.add(name);
    }
    return out;
  }

  /// 这个角色开心声了吗。默认关。
  bool heartVoiceOn(String name) => heartVoiceNames().contains(name.trim());

  Future<void> setHeartVoice(String name, bool enabled) async {
    final key = name.trim();
    if (key.isEmpty) return;
    await _update((extras) {
      final next = Map<String, dynamic>.from(extras);
      final names = <String>[];
      final raw = next[socialHeartVoiceKey];
      if (raw is List) {
        for (final value in raw) {
          final n = value.toString().trim();
          if (n.isNotEmpty && n != key) names.add(n);
        }
      }
      if (enabled) names.add(key);
      next[socialHeartVoiceKey] = names;
      return next;
    });
  }

  // ---------------- 会话最后活跃时间（离线补算用） ----------------

  /// 每个会话关键过的时刻（毫秒）。键跟消息键一致：群 id 或 `dm:名字`。
  Map<String, int> seenMap() {
    final raw = _extras[socialSeenKey];
    final out = <String, int>{};
    if (raw is! Map) return out;
    for (final entry in raw.entries) {
      out[entry.key.toString()] = socialInt(entry.value);
    }
    return out;
  }

  int lastSeen(String key) => seenMap()[key] ?? 0;

  /// 打开某个会话 / 离开时打点。给的是"这一刻算活跃过"。
  Future<void> markSeen(String key, {int? at}) async {
    if (key.trim().isEmpty) return;
    final stamp = at ?? DateTime.now().millisecondsSinceEpoch;
    await _update((extras) {
      final next = Map<String, dynamic>.from(extras);
      final raw = Map<String, dynamic>.from(
        next[socialSeenKey] is Map
            ? next[socialSeenKey] as Map
            : <String, dynamic>{},
      );
      // 只往前推，不因迟到的打点把时间往回改。
      final previous = socialInt(raw[key]);
      if (stamp > previous) raw[key] = stamp;
      next[socialSeenKey] = raw;
      return next;
    });
  }

  // ---------------- 故事时间坐标（三场景 + 离线补算共用） ----------------

  SocialWorldClock get worldClock =>
      SocialWorldClock.fromJson(_extras[socialWorldClockKey]);

  /// 故事里的「现在」。所有场景都该用它，而不是 DateTime.now()。
  DateTime storyNow() => worldClock.now();

  /// 给模型看的一句故事时间。
  String get storyTimeLine => socialTimeLine(storyNow());

  /// 把真实的毫秒时间戳换算成故事时刻（离线补算按消息时间查作息用）。
  DateTime storyTimeFromRealMillis(int millis) =>
      worldClock.storyTimeFromRealMillis(millis);

  /// 切回跟随手机真实时间（清掉锚点）。
  Future<void> setWorldClockFollowReal() async {
    await _update((extras) {
      final next = Map<String, dynamic>.from(extras);
      next.remove(socialWorldClockKey);
      return next;
    });
  }

  /// 手动把故事时间锁定到 [storyAt]，之后照常往前流。
  /// 例如传「2026-11-20 20:00」，故事就从周三晚八点开始走。
  Future<void> setWorldClockTo(DateTime storyAt) async {
    final realNow = DateTime.now().millisecondsSinceEpoch;
    await _update((extras) {
      final next = Map<String, dynamic>.from(extras);
      next[socialWorldClockKey] = SocialWorldClock(
        followReal: false,
        realAnchor: realNow,
        storyAnchor: storyAt.millisecondsSinceEpoch,
      ).toJson();
      return next;
    });
  }

  /// 把故事时间往前推 [by]（可为负表示回拨）：在当前锚点基础上平移。
  Future<void> advanceWorldClock(Duration by) async {
    final clock = worldClock;
    if (clock.followReal) {
      // 当前跟随真实时间：先把「现在」定住，再平移。
      await setWorldClockTo(DateTime.now().add(by));
      return;
    }
    await _update((extras) {
      final next = Map<String, dynamic>.from(extras);
      next[socialWorldClockKey] = SocialWorldClock(
        followReal: false,
        realAnchor: clock.realAnchor,
        storyAnchor: clock.storyAnchor + by.inMilliseconds,
      ).toJson();
      return next;
    });
  }

  // ---------------- 手写剧情概括（三场景共用一份） ----------------

  /// 我手写的「剧情概括」。摘要模式下三场景都读这一份，不再规则压缩。
  String get plotSummary => (_extras[socialSummaryKey] ?? '').toString();

  Future<void> setPlotSummary(String text) async {
    await _update((extras) {
      final next = Map<String, dynamic>.from(extras);
      next[socialSummaryKey] = text;
      return next;
    });
  }

  // ---------------- 压缩词（填写参考，可清空/恢复预设） ----------------

  /// 压缩词模板：null 表示「当前是预设」（没单独存过）。
  /// 存空串表示「我清空了」；存别的串表示「我改过」。
  String? get compressPromptOverride {
    if (!_extras.containsKey(socialCompressPromptKey)) return null;
    return (_extras[socialCompressPromptKey] ?? '').toString();
  }

  /// 当前生效的压缩词：没清也没改就用预设。
  String get compressPrompt {
    final override = compressPromptOverride;
    return override ?? kDefaultCompressPrompt;
  }

  Future<void> setCompressPrompt(String text) async {
    await _update((extras) {
      final next = Map<String, dynamic>.from(extras);
      next[socialCompressPromptKey] = text;
      return next;
    });
  }

  /// 恢复预设：把这项从 extras 里删掉，回到「没改过」的状态。
  Future<void> resetCompressPrompt() async {
    await _update((extras) {
      final next = Map<String, dynamic>.from(extras);
      next.remove(socialCompressPromptKey);
      return next;
    });
  }

  // ---------------- 剧情控制记录 ----------------

  /// 每次「控制剧情走向」写下的文字，新的在前。
  List<PlotLogEntry> plotLogs() {
    final raw = _extras[socialPlotLogKey];
    if (raw is! List) return const <PlotLogEntry>[];
    final out = <PlotLogEntry>[];
    for (final item in raw) {
      final entry = PlotLogEntry.fromJson(item);
      if (entry != null) out.add(entry);
    }
    out.sort((a, b) => b.at.compareTo(a.at));
    return out;
  }

  Future<void> addPlotLog(String text, {String scene = 'group'}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final entry = PlotLogEntry(
      text: trimmed,
      scene: scene,
      at: DateTime.now().millisecondsSinceEpoch,
    );
    await _update((extras) {
      final next = Map<String, dynamic>.from(extras);
      final raw = next[socialPlotLogKey] is List
          ? List<dynamic>.from(next[socialPlotLogKey] as List)
          : <dynamic>[];
      raw.insert(0, entry.toJson());
      // 只留最近 200 条，别无限涨。
      final trimmedList = raw.length > 200 ? raw.sublist(0, 200) : raw;
      next[socialPlotLogKey] = trimmedList;
      return next;
    });
  }

  Future<void> clearPlotLogs() async {
    await _update((extras) {
      final next = Map<String, dynamic>.from(extras);
      next.remove(socialPlotLogKey);
      return next;
    });
  }
}

/// 一条「控制剧情走向」的记录。
class PlotLogEntry {
  const PlotLogEntry({
    required this.text,
    required this.scene,
    required this.at,
  });

  final String text;
  final String scene;
  final int at;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'text': text,
        'scene': scene,
        'at': at,
      };

  static PlotLogEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final text = (raw['text'] ?? '').toString();
    if (text.isEmpty) return null;
    return PlotLogEntry(
      text: text,
      scene: (raw['scene'] ?? 'group').toString(),
      at: socialInt(raw['at']),
    );
  }
}

bool conversationIsSocial(Conversation conversation) =>
    conversation.extras[socialHiddenKey] == true;

/// 把一段上下文压成摘要。规则式压缩，不额外调模型：保留每行的说话人和
/// 前 [perLine] 个字，重复的连续发言合并。够让模型知道「聊过什么」。
String socialSummarize(List<String> lines, {int perLine = 40}) {
  final out = <String>[];
  String? lastPrefix;
  int repeat = 0;
  void flushRepeat() {
    if (repeat > 0) {
      out.add('（同上$repeat条）');
      repeat = 0;
    }
  }

  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final short = trimmed.length > perLine
        ? '${trimmed.substring(0, perLine)}…'
        : trimmed;
    if (short == lastPrefix) {
      repeat++;
      continue;
    }
    flushRepeat();
    out.add(short);
    lastPrefix = short;
  }
  flushRepeat();
  return out.join('\n');
}

/// 把任意对象安全转成字符串，供 JSON 读取用。
String socialString(Object? value) => value == null ? '' : value.toString();

int socialInt(Object? value, [int fallback = 0]) =>
    value is num ? value.round() : int.tryParse('$value') ?? fallback;

/// 供 UI 展示用的 JSON 编解码（作息导入导出走它）。
String encodeSocialJson(Map<String, dynamic> value) => jsonEncode(value);

Map<String, dynamic>? decodeSocialJson(String raw) {
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}
