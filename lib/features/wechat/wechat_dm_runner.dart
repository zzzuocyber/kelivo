import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/providers/world_book_provider.dart';
import '../../core/services/social_context_builder.dart';
import '../../core/services/social_store.dart';
import '../moment/moment_store.dart';
import 'wechat_models.dart';
import 'wechat_service.dart';
import 'wechat_store.dart';

/// 私聊的「对方回一句」后台执行器。
///
/// 放在页面之外，是为了解决「退出私聊就停止生成」：
/// 等待和生成都归它管，页面退出后照样把消息写进 store，
/// 下次进来能看到，未读红点也照常。页面只订阅状态刷新界面。
class WechatDmReplyRunner {
  WechatDmReplyRunner._();

  static final WechatDmReplyRunner instance = WechatDmReplyRunner._();

  /// key 是 `dm:名字`。
  final Map<String, Timer> _timers = <String, Timer>{};
  final Set<String> _inFlight = <String>{};

  /// 只有消息马上落地的一小段时间算「正在输入」。
  final Set<String> _cueing = <String>{};

  /// 上一轮的错误，页面回来时取走提示一次。
  final Map<String, String> _errors = <String, String>{};

  /// 内部用的连续不回次数；只用于强制兜底，界面永远看不到。
  final Map<String, int> _noReplyStreak = <String, int>{};

  static const int _maxNoReplyStreak = 2;

  final List<VoidCallback> _listeners = <VoidCallback>[];

  void addListener(VoidCallback listener) => _listeners.add(listener);

  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void _notify() {
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }

  /// 这个人还有一句没回（在等间隔或正在生成）。
  bool isPending(String key) =>
      _timers.containsKey(key) || _inFlight.contains(key);

  /// 取消一个还没开始生成的等待（在等间隔的那句）。用于剧情/召唤强制插队。
  void cancelPending(String key) {
    _timers.remove(key)?.cancel();
    _notify();
  }

  /// 现在该显示「对方正在输入」。
  bool isCueing(String key) => _cueing.contains(key);

  /// 取走并清掉上一次的错误提示。
  String? takeError(String key) {
    final message = _errors[key];
    if (message != null) _errors.remove(key);
    return message;
  }

  /// 排一句回复。[delay] 是等待间隔；到点后在后台生成、写库。
  void schedule({
    required String key,
    required String contactName,
    required WechatStore store,
    required SettingsProvider settings,
    required WorldBookProvider worldBooks,
    required Duration delay,
    SocialStore? social,
    MomentStore? momentStore,
    bool selfInitiated = false,
    bool forceReply = false,
  }) {
    if (isPending(key)) return;
    _errors.remove(key);
    _timers[key] = Timer(delay, () {
      _timers.remove(key);
      unawaited(
        _run(
          key: key,
          contactName: contactName,
          store: store,
          settings: settings,
          worldBooks: worldBooks,
          social: social,
          momentStore: momentStore,
          selfInitiated: selfInitiated,
          forceReply: forceReply,
        ),
      );
    });
    _notify();
  }

  Future<void> _run({
    required String key,
    required String contactName,
    required WechatStore store,
    required SettingsProvider settings,
    required WorldBookProvider worldBooks,
    SocialStore? social,
    MomentStore? momentStore,
    required bool selfInitiated,
    required bool forceReply,
  }) async {
    final streak = _noReplyStreak[key] ?? 0;
    _inFlight.add(key);
    _notify();
    try {
      // 重新读一次：退出页面期间联系人/设置可能改过。
      final contact =
          store.contact(contactName) ?? WechatContact(name: contactName);
      final wechatSettings = store.wechatSettings();
      final burst = wechatBurstCount(wechatSettings.burstPreset, Random());
      // 概率只决定「这一轮允不允许考虑不回」，最终由模型按人设输出暗号。
      // 召唤、明确指令、连续不回太多都直接关掉这个口子。
      final allowNoReply =
          contact.noReplyEnabled &&
          !forceReply &&
          !selfInitiated &&
          streak < _maxNoReplyStreak &&
          Random().nextDouble() < contact.noReplyStrength.chance;
      // 一次性天意指令（切换话题/结束/冷场）。
      final scope = socialDmScope(contactName);
      final directive = social == null
          ? SocialDirective.none
          : await social.takeDirective(scope);
      // 跨场景记忆 + 此刻处境：只跟「我」有关的别处记录才有意义。
      var contextText = '';
      if (social != null) {
        final memories = <String>[
          ...?momentStore?.memoryLinesFor(contactName),
          ...store.memoryLinesFor(contactName, excludeKey: key),
        ];
        final where = social.whereabouts(contactName);
        final built = SocialContextBuilder.build(
          name: contactName,
          scene: 'dm',
          memoryLines: memories,
          where: where.promptLine,
          store: social,
          topic: social.topic(scope).topic,
          summaryText: social.plotSummary,
        );
        contextText = built.text;
        unawaited(social.addTokens('dm', built.tokens));
        // 引导也算我给模型看的上下文的一部分，粗略计入。
      }
      final generator = WechatDmGenerator(
        settings: settings,
        worldBooks: worldBooks,
        contact: contact,
        bookIds: wechatSettings.bookIds,
        persona: wechatSettings.effectivePersona,
        worldPrompt: wechatSettings.worldPrompt,
        history: wechatRecentContext(store.dmMessages(contactName), limit: 40),
        selfInitiated: selfInitiated,
        allowNoReply: allowNoReply,
        socialContext: contextText,
        directiveKind: directive.kind,
        directiveWho: directive.who,
        directiveText: directive.text,
      );
      final text = await generator.generate(burstCount: burst);
      final isPlot = directive.kind == 'plot' && directive.text.trim().isNotEmpty;
      // 控制剧情走向：整段一条旁白，不拆成多条、不挂对方名下。
      final parts = isPlot
          ? <String>[text]
          : wechatSplitReply(text, maxParts: burst);
      if (parts.isEmpty) {
        throw const WechatServiceException('empty');
      }
      // 落地前短暂亮一下「正在输入」，再一条条写进去。
      _cueing.add(key);
      _notify();
      await Future<void>.delayed(wechatTypingCue);
      for (final part in parts) {
        final parsed = wechatStripImageMark(part);
        if (parsed.text.isEmpty) continue;
        await store.appendDmMessage(
          contactName,
          text: parsed.text,
          mine: false,
          withImage: parsed.withImage && !isPlot,
          plot: isPlot,
        );
      }
      // 真回过一次就把连续不回清零。
      _noReplyStreak.remove(key);
    } on WechatNoReplyException catch (_) {
      // 模型决定不理：不建消息、不写库、不弹提示，只记个内部计数防连续冷暴力。
      _noReplyStreak[key] = streak + 1;
      return;
    } on WechatServiceException catch (error) {
      _errors[key] = error.code == 'model_missing'
          ? '这个人还没选模型，去「我 → 设置 → 角色管理」挑一个'
          : '这次没生成出内容';
    } catch (_) {
      _errors[key] = '这次没接上，再发一句试试';
    } finally {
      _cueing.remove(key);
      _inFlight.remove(key);
      _notify();
    }
  }
}
