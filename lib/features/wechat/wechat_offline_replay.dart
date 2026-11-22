import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/providers/world_book_provider.dart';
import '../../core/services/social_affinity.dart';
import '../../core/services/social_context_builder.dart';
import '../../core/services/social_store.dart';
import '../moment/moment_store.dart';
import 'wechat_models.dart';
import 'wechat_service.dart';
import 'wechat_store.dart';

// ---------------------------------------------------------------------------
// 离线补算：解决「退出群聊他们就不说话了」。
//
// 不搞后台常驻（费电、烧 token、还会被系统杀）。改成：打开微信的那一刻，
// 按离开时长算一笔「这期间发生过的事」，让角色临场补几句标成过去时间的消息。
// 打开时有新消息、红点；不在的时候零消耗。
//
// 防刷屏三道闸：
// 1. 全局打点：距上次补算不足 [minGap] 直接跳过（反复进出不重复补）。
// 2. 每个会话第一次见只种哨兵、不补（老用户第一次升级不会突然冒一堆）。
// 3. 离开时长不够 [minAway] 不补；每次最多补 [maxGroups] 个群 + [maxDms] 个私聊，
//    每个会话只补一轮（1~几条按 burst）。
// ---------------------------------------------------------------------------

class WechatOfflineReplay {
  WechatOfflineReplay._();

  static final WechatOfflineReplay instance = WechatOfflineReplay._();

  /// 两次补算之间的最小间隔。频繁进出微信不会次次都刷消息。
  static const Duration minGap = Duration(minutes: 5);

  /// 离开至少要这么久才值得补。刚锁屏马上回来不补。
  static const Duration minAway = Duration(minutes: 3);

  /// 一次最多补几个会话，避免一进来满屏新消息。
  static const int maxGroups = 2;
  static const int maxDms = 2;

  /// 全局上次补算的时刻键（存在社交容器里）。
  static const String _lastRunKey = '@offline_replay';

  final Random _random = Random();
  bool _running = false;

  final List<VoidCallback> _listeners = <VoidCallback>[];
  void addListener(VoidCallback listener) => _listeners.add(listener);
  void removeListener(VoidCallback listener) => _listeners.remove(listener);
  void _notify() {
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }

  /// 打开微信时调用。缺依赖就静默跳过，绝不抛到界面。
  void maybeRun({
    required WechatStore store,
    required SocialStore social,
    required MomentStore momentStore,
    required SettingsProvider settings,
    required WorldBookProvider worldBooks,
  }) {
    if (_running) return;
    _running = true;
    unawaited(_run(
      store: store,
      social: social,
      momentStore: momentStore,
      settings: settings,
      worldBooks: worldBooks,
    ));
  }

  Future<void> _run({
    required WechatStore store,
    required SocialStore social,
    required MomentStore momentStore,
    required SettingsProvider settings,
    required WorldBookProvider worldBooks,
  }) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final lastRun = social.lastSeen(_lastRunKey);
      // 闸 1：距上次补算太近，跳过。
      if (lastRun > 0 && now - lastRun < minGap.inMilliseconds) return;
      // 先把全局打点记上，哪怕后面一条都没补，也别下次进来又算一遍。
      await social.markSeen(_lastRunKey, at: now);

      var added = 0;
      added += await _replayGroups(
        store: store,
        social: social,
        momentStore: momentStore,
        settings: settings,
        worldBooks: worldBooks,
        now: now,
      );
      added += await _replayDms(
        store: store,
        social: social,
        momentStore: momentStore,
        settings: settings,
        worldBooks: worldBooks,
        now: now,
      );
      if (added > 0) _notify();
    } catch (_) {
      // 离线补算是锦上添花，任何异常都不该影响微信正常打开。
    } finally {
      _running = false;
    }
  }

  /// 给某个会话算一条落在离开区间里的过去时间戳。
  int _pastStamp(int seenAt, int now) {
    final lo = seenAt > 0 ? seenAt : now - minAway.inMilliseconds;
    final hi = now - 1000;
    if (hi <= lo) return lo;
    return lo + _random.nextInt(hi - lo);
  }

  Future<int> _replayGroups({
    required WechatStore store,
    required SocialStore social,
    required MomentStore momentStore,
    required SettingsProvider settings,
    required WorldBookProvider worldBooks,
    required int now,
  }) async {
    final candidates = <WechatGroup>[];
    for (final group in store.groups()) {
      if (!social.autoReply(group.id)) continue;
      if (social.topic(groupScope(group.id)).isCoolingDown) continue;
      if (group.members.isEmpty) continue;
      final seen = social.lastSeen(group.id);
      if (seen == 0) {
        // 闸 2：第一次见这个群，只种哨兵。
        await social.markSeen(group.id, at: now);
        continue;
      }
      if (now - seen < minAway.inMilliseconds) continue;
      // 再掷一次骰子，不是每个够资格的群都补。
      if (_random.nextDouble() > 0.5) continue;
      candidates.add(group);
    }
    // 打乱后限量，群聊之间机会均等。
    candidates.shuffle(_random);
    final picked = candidates.take(maxGroups).toList(growable: false);

    var count = 0;
    for (final group in picked) {
      try {
        final seen = social.lastSeen(group.id);
        final speaker =
            group.members[_random.nextInt(group.members.length)];
        final speakerName = speaker.name;
        final wechatSettings = store.wechatSettings();
        final burst = wechatBurstCount(wechatSettings.burstPreset, _random);
        final forgetFloor = social.forgetFloor(speakerName);
        final memories = <String>[
          ...momentStore.memoryLinesFor(speakerName, since: forgetFloor),
          ...store.memoryLinesFor(
            speakerName,
            excludeKey: group.id,
            since: forgetFloor,
          ),
        ];
        // 按这条补算消息「发生」的真实时刻（pastReal）换算成故事时间，
        // 查作息、写时间句、写库时间戳都用同一个时刻——避免「昨晚的消息按今天作息说话」。
        final pastReal = _pastStamp(seen, now);
        final storyAt = social.storyTimeFromRealMillis(pastReal);
        final where = social.whereabouts(speakerName, now: storyAt);
        final built = SocialContextBuilder.build(
          name: speakerName,
          scene: 'group',
          memoryLines: memories,
          where: where.promptLine,
          store: social,
          topic: group.autoTopic ? social.topic(groupScope(group.id)).topic : '',
          summaryText: social.plotSummary,
          timeLine: socialTimeLine(storyAt),
        );
        final generator = WechatGenerator(
          settings: settings,
          worldBooks: worldBooks,
          group: group,
          history: wechatRecentContext(store.messages(group.id)),
          bookIds: wechatSettings.bookIds,
          contacts: <String, WechatContact>{
            for (final c in store.contacts()) c.name: c,
          },
          worldPrompt: wechatSettings.worldPrompt,
          groupPrompt: group.groupPrompt,
          socialContext: built.text,
        );
        final text = await generator.generateFor(speaker, burstCount: burst);
        final parts = wechatSplitReply(text, maxParts: burst);
        if (parts.isEmpty) continue;
        var wrote = 0;
        for (final part in parts) {
          final parsed = wechatStripImageMark(part);
          if (parsed.text.isEmpty) continue;
          // 几条之间错开几秒，像真的一段对话；基准与查作息的时刻一致。
          final at = pastReal + wrote * 1500;
          await store.appendMessage(
            group.id,
            sender: speakerName,
            text: parsed.text,
            withImage: parsed.withImage,
            at: at > now ? now - 1000 : at,
          );
          wrote++;
          count++;
        }
        if (wrote > 0) {
          await store.markUnread(group.id);
          await social.markSeen(group.id, at: now);
        }
      } on WechatNoReplyException catch (_) {
        // 这轮他不想开口，跳过这个群。
      } catch (_) {
        // 单个群失败不影响别的。
      }
    }
    return count;
  }

  Future<int> _replayDms({
    required WechatStore store,
    required SocialStore social,
    required MomentStore momentStore,
    required SettingsProvider settings,
    required WorldBookProvider worldBooks,
    required int now,
  }) async {
    final candidates = <({String name, double chance})>[];
    for (final contact in store.contacts()) {
      final key = wechatDmKey(contact.name);
      final seen = social.lastSeen(key);
      if (seen == 0) {
        await social.markSeen(key, at: now);
        continue;
      }
      if (now - seen < minAway.inMilliseconds) continue;
      if (social.topic(socialDmScope(contact.name)).isCoolingDown) continue;
      // 私聊按好感度的粘人概率决定补不补。
      final chance = social.affinity(contact.name).chance;
      if (!affinityRoll(chance, _random)) continue;
      candidates.add((name: contact.name, chance: chance));
    }
    // 越粘人的排前面，限量时优先补他们。
    candidates.sort((a, b) => b.chance.compareTo(a.chance));
    final picked = candidates.take(maxDms).toList(growable: false);

    var count = 0;
    for (final item in picked) {
      final name = item.name;
      try {
        final key = wechatDmKey(name);
        final seen = social.lastSeen(key);
        final contact = store.contact(name) ?? WechatContact(name: name);
        final wechatSettings = store.wechatSettings();
        final burst = wechatBurstCount(wechatSettings.burstPreset, _random);
        final forgetFloor = social.forgetFloor(name);
        final memories = <String>[
          ...momentStore.memoryLinesFor(name, since: forgetFloor),
          ...store.memoryLinesFor(name, excludeKey: key, since: forgetFloor),
        ];
        // 按补算消息发生的时刻（pastReal）换算故事时间，查作息/时间戳用同一个。
        final pastReal = _pastStamp(seen, now);
        final storyAt = social.storyTimeFromRealMillis(pastReal);
        final where = social.whereabouts(name, now: storyAt);
        final built = SocialContextBuilder.build(
          name: name,
          scene: 'dm',
          memoryLines: memories,
          where: where.promptLine,
          store: social,
          topic: social.topic(key).topic,
          summaryText: social.plotSummary,
          timeLine: socialTimeLine(storyAt),
        );
        final generator = WechatDmGenerator(
          settings: settings,
          worldBooks: worldBooks,
          contact: contact,
          bookIds: wechatSettings.bookIds,
          persona: wechatSettings.effectivePersona,
          worldPrompt: wechatSettings.worldPrompt,
          history: wechatRecentContext(store.dmMessages(name), limit: 40),
          socialContext: built.text,
        );
        final text = await generator.generate(burstCount: burst);
        final parts = wechatSplitReply(text, maxParts: burst);
        var wrote = 0;
        for (final part in parts) {
          final parsed = wechatStripImageMark(part);
          if (parsed.text.isEmpty) continue;
          final at = pastReal + wrote * 1500;
          await store.appendDmMessage(
            name,
            text: parsed.text,
            mine: false,
            withImage: parsed.withImage,
            at: at > now ? now - 1000 : at,
          );
          wrote++;
          count++;
        }
        if (wrote > 0) {
          await store.markUnread(key);
          await social.markSeen(key, at: now);
          // 他主动来找我：好感微涨（越粘越来）。
          await social.applyAffinityEvent(name, AffinityEvent.themToMe);
        }
      } on WechatNoReplyException catch (_) {
        // 他这轮不想搭理，跳过。
      } catch (_) {
        // 单个人失败不影响别的。
      }
    }
    return count;
  }
}

/// 群聊的作用域键（跟页面里 socialGroupScope 一致，这里自己拼免得交叉 import）。
String groupScope(String groupId) => 'group:$groupId';
