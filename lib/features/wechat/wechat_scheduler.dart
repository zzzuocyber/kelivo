import 'dart:math';

import 'wechat_models.dart';

/// 决定「下一个人是谁」和「隔多久」。
///
/// 核心是别让群里变成 ABAB 轮流：刚说完的人权重压到极低，
/// 最近几条里出现得多的人也降权，剩下的人按权重抽。
class WechatScheduler {
  WechatScheduler({Random? random}) : _random = random ?? Random();

  final Random _random;

  /// 从群里抽一个人说话。抽不到（没人）返回 null。
  WechatMember? pickSpeaker(WechatGroup group, List<WechatMessage> history) {
    final pool = <WechatMember>[
      for (final member in group.members)
        if (member.name.trim().isNotEmpty) member,
    ];
    if (pool.isEmpty) return null;
    if (pool.length == 1) return pool.first;

    final recent = _recentSpeakers(history, keep: 8);
    final weights = <double>[];
    for (final member in pool) {
      var weight = 1.0;
      final lastIndex = recent.indexOf(member.name);
      if (lastIndex == 0) {
        // 刚说完，基本不让连说（真群里也会偶尔补一句，所以不是 0）
        weight *= 0.07;
      } else if (lastIndex == 1) {
        weight *= 0.4;
      } else if (lastIndex > 1 && lastIndex < 4) {
        weight *= 0.72;
      }
      // 最近几条里出现次数越多越降温，人多时也不会总轮到那几个
      final count = recent.where((name) => name == member.name).length;
      weight *= 1.0 / (1.0 + count * 0.35);
      // 留一点纯随机，免得每次都按同一套权重走
      weight *= 0.55 + _random.nextDouble() * 0.9;
      weights.add(weight);
    }
    return _weightedPick(pool, weights);
  }

  /// 这次之后隔多久再让下一个人开口。
  ///
  /// 群设置里选了「跟随全局」时要传 [settings]，不然拿不到全局那一档。
  Duration nextDelay(WechatGroup group, {WechatSettings? settings}) =>
      group.nextDelay(_random, settings: settings);

  /// 最近谁说过话，最新的在前。
  List<String> _recentSpeakers(List<WechatMessage> history, {int keep = 8}) {
    final out = <String>[];
    for (var i = history.length - 1; i >= 0 && out.length < keep; i--) {
      final message = history[i];
      if (message.system) continue;
      final sender = message.sender.trim();
      if (sender.isEmpty) continue;
      out.add(sender);
    }
    return out;
  }

  WechatMember _weightedPick(List<WechatMember> pool, List<double> weights) {
    final total = weights.fold<double>(0, (sum, item) => sum + item);
    if (total <= 0) return pool[_random.nextInt(pool.length)];
    var roll = _random.nextDouble() * total;
    for (var i = 0; i < pool.length; i++) {
      roll -= weights[i];
      if (roll <= 0) return pool[i];
    }
    return pool.last;
  }
}
