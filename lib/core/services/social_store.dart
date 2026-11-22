import 'dart:convert';

import '../models/conversation.dart';
import 'chat/chat_service.dart';

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
const String socialContainerTitle = '社交状态';

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
          extras.containsKey(socialContextModeKey);
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
  SocialWhereabouts whereabouts(String name, {DateTime? now}) {
    final moment = now ?? DateTime.now();
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
