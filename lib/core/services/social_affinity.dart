import 'dart:math';

// ---------------------------------------------------------------------------
// 好感度系统（单向：角色 → 我）。
//
// 只存「某个角色对我」的一份好感度，不存「我 → 角色」；角色与角色之间
// 也互不记录。分数驱动两件事：私聊/群聊生成时的粘人语气，以及离线补算
// 时「他会不会主动来找你」的概率。
//
// 这里只放纯数据 + 纯算法，不碰任何 store / UI，方便单独校验和以后单测。
// 面板那一大堆折叠 UI 规则不在这里——微信里不显示面板，只显示分数和状态。
// ---------------------------------------------------------------------------

/// 颜值加成对照表：1 → -1，4 → 0，10 → +1。
/// 范围 1~10（用户拍板，没有 0）。越界按最近的端点取。
double beautyBonus(int beauty) {
  final b = beauty.clamp(1, 10);
  const table = <double>[
    -1,     // 1
    -0.67,  // 2
    -0.33,  // 3
    0,      // 4（普通）
    0.17,   // 5
    0.33,   // 6
    0.5,    // 7
    0.67,   // 8
    0.83,   // 9
    1,      // 10
  ];
  return table[b - 1];
}

/// 一次好感度变动的基础分档位。用户给的固定档：0.5/1/2/5/10/20/30。
class AffinityEvent {
  const AffinityEvent({
    required this.base,
    required this.positive,
    required this.label,
  });

  final double base;
  final bool positive;
  final String label;

  static const AffinityEvent meToThem = AffinityEvent(
    base: 2,
    positive: true,
    label: '我主动找他',
  );
  static const AffinityEvent themToMe = AffinityEvent(
    base: 1,
    positive: true,
    label: '他主动找我',
  );
  static const AffinityEvent momentTouch = AffinityEvent(
    base: 1,
    positive: true,
    label: '朋友圈互动',
  );
  static const AffinityEvent longNeglect = AffinityEvent(
    base: 5,
    positive: false,
    label: '长期不理',
  );
  static const AffinityEvent leftOnRead = AffinityEvent(
    base: 2,
    positive: false,
    label: '已读不回',
  );
}

/// 算一次变动后的新分数。
///
/// 新 = 旧 + 基础分×方向 + 基础分×颜值加成
/// - 正向事件：颜值 1~4 加成按 0，5~10 才用对照表。
/// - 负向事件：直接用对照表（越漂亮扣得越狠）。
/// - 情侣关系后：负向事件的颜值加成按 0（规则留着，当前没有情侣系统，传 false）。
///
/// 结果夹在 -100~100。
double affinityAfter({
  required double old,
  required AffinityEvent event,
  required int beauty,
  bool lover = false,
}) {
  final bonus = beautyBonus(beauty);
  final applied = event.positive
      ? (beauty >= 5 ? bonus : 0.0)
      : (lover ? 0.0 : bonus);
  final direction = event.positive ? 1.0 : -1.0;
  final next = old + event.base * direction + event.base * applied;
  return next.clamp(-100.0, 100.0).toDouble();
}

/// 把完整算式写成一行，给「好感度面板」显示用（用户要求保留所有项）。
String affinityFormula({
  required double old,
  required AffinityEvent event,
  required int beauty,
  bool lover = false,
}) {
  final bonus = beautyBonus(beauty);
  final applied = event.positive
      ? (beauty >= 5 ? bonus : 0.0)
      : (lover ? 0.0 : bonus);
  final direction = event.positive ? 1 : -1;
  final next = affinityAfter(
    old: old,
    event: event,
    beauty: beauty,
    lover: lover,
  );
  final base = event.base.toStringAsFixed(1);
  final oldText = old.toStringAsFixed(1);
  final appliedText = applied.toStringAsFixed(2);
  final nextText = next.toStringAsFixed(1);
  return '$oldText + $base×$direction + $base×$appliedText = $nextText';
}

/// 分数对应的主状态。八档，从低到高。
String affinityStatus(double score) {
  if (score <= -80) return '🌧️ 心寒';
  if (score <= -55) return '💣 厌恶';
  if (score <= -40) return '❄️ 疏离';
  if (score <= 20) return '☁️ 平淡';
  if (score <= 50) return '⚡ 暗涌';
  if (score <= 65) return '💗 心动';
  if (score <= 80) return '🌸 沉溺';
  return '💞 深爱';
}

/// 档位 → 主动找你的概率（离线补算用）。
/// 偏执 / 又爱又恨各再加一截；🫧错觉锁 50 分上限（超过按 50 算）。
double clingChance({
  required double score,
  bool lovesick = false, // 🩸 偏执
  bool loveHate = false, // 🔥 又爱又恨
  bool illusion = false, // 🫧 错觉：上限锁 50
}) {
  var s = score;
  if (illusion && s > 50) s = 50;
  late final double base;
  if (s <= -80) {
    base = 0;
  } else if (s <= -55) {
    base = 0.05;
  } else if (s <= -40) {
    base = 0.10;
  } else if (s <= 20) {
    base = 0.20;
  } else if (s <= 50) {
    base = 0.35;
  } else if (s <= 65) {
    base = 0.50;
  } else if (s <= 80) {
    base = 0.70;
  } else {
    base = 0.85;
  }
  var extra = 0.0;
  if (lovesick) extra += 0.10;
  if (loveHate) extra += 0.10;
  return (base + extra).clamp(0.0, 0.95);
}

/// 判断这次要不要补一条：按 [chance] 掷骰子。
bool affinityRoll(double chance, Random random) =>
    chance > 0 && random.nextDouble() < chance;

/// 一个人对「我」的好感度档案。
class SocialAffinity {
  const SocialAffinity({
    required this.name,
    this.score = 0,
    this.beauty = 4,
    this.manualStatus = '',
    this.specials = const <String>[],
    this.lastReason = '',
    this.lastFormula = '',
    this.updatedAt = 0,
  });

  final String name;
  final double score;
  final int beauty;

  /// 手动指定的状态标签。空 = 按分数自动算。作弊用。
  final String manualStatus;

  /// 特殊状态：🩸偏执 / 💤爱不自知 / 🫧错觉 / 🔥又爱又恨。
  final List<String> specials;

  /// 最近一次变动的变因 + 算式，给面板显示。
  final String lastReason;
  final String lastFormula;
  final int updatedAt;

  bool get lovesick => specials.contains('🩸 偏执');
  bool get loveHate => specials.contains('🔥 又爱又恨');
  bool get illusion => specials.contains('🫧 错觉');

  /// 面板上显示的状态：手动指定的优先，否则按分数。
  String get status => manualStatus.trim().isEmpty
      ? affinityStatus(score)
      : manualStatus.trim();

  /// 主动找你的概率。
  double get chance => clingChance(
        score: score,
        lovesick: lovesick,
        loveHate: loveHate,
        illusion: illusion,
      );

  /// 应用一次事件，返回新的档案（不可变）。
  SocialAffinity apply(
    AffinityEvent event, {
    bool lover = false,
    String? reason,
    int? now,
  }) {
    final next = affinityAfter(
      old: score,
      event: event,
      beauty: beauty,
      lover: lover,
    );
    return copyWith(
      score: next,
      lastReason: reason ?? event.label,
      lastFormula: affinityFormula(
        old: score,
        event: event,
        beauty: beauty,
        lover: lover,
      ),
      updatedAt: now ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 剧情跳段：意识到了自己的心意，直接落到目标分，不经过中间档。
  /// 🩸偏执不清除（规则要求），其余特殊状态由调用方决定。
  SocialAffinity jumpTo(double target, {String reason = '意识到自己的心意'}) {
    return copyWith(
      score: target.clamp(-100, 100).toDouble(),
      lastReason: reason,
      lastFormula: '跳段 → ${target.toStringAsFixed(1)}',
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  SocialAffinity copyWith({
    String? name,
    double? score,
    int? beauty,
    String? manualStatus,
    List<String>? specials,
    String? lastReason,
    String? lastFormula,
    int? updatedAt,
    bool clearManualStatus = false,
  }) {
    return SocialAffinity(
      name: name ?? this.name,
      score: score ?? this.score,
      beauty: beauty ?? this.beauty,
      manualStatus: clearManualStatus ? '' : (manualStatus ?? this.manualStatus),
      specials: specials ?? this.specials,
      lastReason: lastReason ?? this.lastReason,
      lastFormula: lastFormula ?? this.lastFormula,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'score': score,
        'beauty': beauty,
        if (manualStatus.isNotEmpty) 'status': manualStatus,
        if (specials.isNotEmpty) 'special': specials,
        'reason': lastReason,
        'formula': lastFormula,
        'at': updatedAt,
      };

  static SocialAffinity? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = (raw['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;
    final specials = <String>[];
    final rawSpecials = raw['special'];
    if (rawSpecials is List) {
      for (final value in rawSpecials) {
        final tag = value.toString().trim();
        if (tag.isNotEmpty) specials.add(tag);
      }
    }
    return SocialAffinity(
      name: name,
      score: _doubleOr(raw['score'], 0),
      beauty: _intOr(raw['beauty'], 4).clamp(1, 10),
      manualStatus: (raw['status'] ?? '').toString(),
      specials: specials,
      lastReason: (raw['reason'] ?? '').toString(),
      lastFormula: (raw['formula'] ?? '').toString(),
      updatedAt: _intOr(raw['at'], 0),
    );
  }
}

double _doubleOr(Object? raw, double fallback) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw) ?? fallback;
  return fallback;
}

int _intOr(Object? raw, int fallback) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw) ?? fallback;
  return fallback;
}
