import 'dart:async';
import 'dart:math';

import '../../core/providers/settings_provider.dart';
import '../../core/providers/world_book_provider.dart';
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
    bool selfInitiated = false,
  }) {
    if (isPending(key)) return;
    _errors.remove(key);
    _timers[key] = Timer(delay, () {
      _timers.remove(key);
      unawaited(_run(
        key: key,
        contactName: contactName,
        store: store,
        settings: settings,
        worldBooks: worldBooks,
        selfInitiated: selfInitiated,
      ));
    });
    _notify();
  }

  Future<void> _run({
    required String key,
    required String contactName,
    required WechatStore store,
    required SettingsProvider settings,
    required WorldBookProvider worldBooks,
    required bool selfInitiated,
  }) async {
    _inFlight.add(key);
    _notify();
    try {
      // 重新读一次：退出页面期间联系人/设置可能改过。
      final contact =
          store.contact(contactName) ?? WechatContact(name: contactName);
      final wechatSettings = store.wechatSettings();
      final burst = wechatBurstCount(wechatSettings.burstPreset, Random());
      final generator = WechatDmGenerator(
        settings: settings,
        worldBooks: worldBooks,
        contact: contact,
        bookIds: wechatSettings.bookIds,
        persona: wechatSettings.effectivePersona,
        worldPrompt: wechatSettings.worldPrompt,
        history: wechatRecentContext(store.dmMessages(contactName), limit: 40),
        selfInitiated: selfInitiated,
      );
      final text = await generator.generate(burstCount: burst);
      final parts = wechatSplitReply(text, maxParts: burst);
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
          withImage: parsed.withImage,
        );
      }
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
