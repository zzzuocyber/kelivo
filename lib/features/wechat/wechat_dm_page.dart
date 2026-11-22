import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/providers/world_book_provider.dart';
import '../../core/services/chat/chat_service.dart';
import '../../core/services/social_affinity.dart';
import '../../core/services/social_store.dart';
import '../../icons/lucide_adapter.dart';
import '../moment/moment_store.dart';
import 'wechat_dm_runner.dart';
import 'wechat_models.dart';
import 'wechat_service.dart';
import 'wechat_store.dart';
import 'wechat_ui.dart';

/// 一对一私聊。没有调度器，就是「我发一句，他回一句」。
class WechatDmPage extends StatefulWidget {
  const WechatDmPage({
    super.key,
    required this.contactName,
    this.summon = false,
  });

  final String contactName;

  /// 召唤进来的：不等你说话，他先开口。
  final bool summon;

  @override
  State<WechatDmPage> createState() => _WechatDmPageState();
}

class _WechatDmPageState extends State<WechatDmPage> {
  late WechatStore _store;
  late SocialStore _social;
  late MomentStore _momentStore;
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();
  final Random _random = Random();

  /// 上一帧的键盘高度：只在键盘「从无到有」时自动滚到底，打字中的高度微调不重复滚。
  double _lastKeyboardInset = 0;

  WechatContact? _contact;
  WechatSettings _settings = const WechatSettings();
  Map<String, String> _avatars = const <String, String>{};
  List<WechatMessage> _messages = const <WechatMessage>[];

  /// 他马上要发出来：只在落地前短暂亮一下。
  bool get _typing => WechatDmReplyRunner.instance.isCueing(_chatKey);

  /// 下一条我发的消息要不要带图（输入栏图片开关）。发完自动关掉。
  bool _attachImage = false;

  /// 天意：用他的身份说话（夺舍）。私聊里也一样能用。
  bool _asDivine = false;

  /// 正在重新生成的那条。非空时把它调淡，也挡住重复点。
  String? _regenId;

  /// 这个私聊在 extras 里的键（`dm:名字`）。
  String get _chatKey => WechatStore.dmKey(widget.contactName);

  @override
  void initState() {
    super.initState();
    final chat = context.read<ChatService>();
    _store = WechatStore(chat);
    _social = SocialStore(chat);
    _momentStore = MomentStore(chat);
    WechatDmReplyRunner.instance.addListener(_onReplyChanged);
    _reload();
    unawaited(_store.markRead(WechatStore.dmKey(widget.contactName)));
    // 离线补算靠这个算离开时长：进私聊即打点。
    unawaited(_social.markSeen(WechatStore.dmKey(widget.contactName)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _jumpToBottom();
    });
    // 召唤进来的：他先说话。给一小段时间让页面站稳再开口。
    // 召唤会结束冷场：天意要他开口，就打破「先别回」。
    if (widget.summon) {
      unawaited(_social.clearCooldown(socialDmScope(widget.contactName)));
      _scheduleReply(summonDelay: const Duration(milliseconds: 500));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    // 键盘从收起变为弹出：等列表收缩动画跑完，自动带到最新一条。
    if (inset > 0 && _lastKeyboardInset <= 0 && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future<void>.delayed(const Duration(milliseconds: 160), () {
          if (mounted) _jumpToBottom();
        });
      });
    }
    _lastKeyboardInset = inset;
  }

  @override
  void dispose() {
    // 不取消后台任务：退出了也要把这句生成完写进 store。
    WechatDmReplyRunner.instance.removeListener(_onReplyChanged);
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      // 通讯录里没有也照样能聊（老数据/召唤进来的人），只是没有人设和绑定。
      _contact =
          _store.contact(widget.contactName) ??
          WechatContact(name: widget.contactName);
      _settings = _store.wechatSettings();
      _avatars = _store.avatarPaths();
      _messages = _store.dmMessages(widget.contactName);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _jumpToBottom();
    });
  }

  void _jumpToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  // ---------------- 发 ----------------

  Future<void> _send() async {
    final raw = _input.text.trim();
    if (raw.isEmpty) return;
    if (_contact == null) return;
    final contact = _contact;
    final otherName = contact?.name ?? widget.contactName;
    // 打字框快捷夺舍：「对方名>xxx」这条用他身份，「我>xxx」用我自己。
    // 私聊只有对方一个角色，名字精确匹配对方名；只作用这一条，不动 _asDivine 持久状态。
    String? quickName;
    var text = raw;
    final idx = raw.indexOf('>');
    if (idx > 0) {
      final name = raw.substring(0, idx).trim();
      final body = raw.substring(idx + 1).trim();
      if (body.isNotEmpty &&
          (name == '我' || name == otherName || name == widget.contactName)) {
        quickName = name;
        text = body;
      }
    }
    if (text.isEmpty) return;
    _input.clear();
    // 优先级：我> 用我自己 > 对方名> 用对方 > 持久 _asDivine 状态。
    final bool asDivine;
    final String senderName;
    if (quickName == '我') {
      asDivine = false;
      senderName = _settings.effectivePersona;
    } else if (quickName != null) {
      asDivine = true;
      senderName = otherName;
    } else {
      asDivine = _asDivine;
      senderName = asDivine ? otherName : _settings.effectivePersona;
    }
    // 夺舍回复会结束冷场：以他的身份开口，就是要打破「先别回」。
    if (asDivine) unawaited(_social.clearCooldown(socialDmScope(widget.contactName)));
    // 夺舍：以他的身份发，气泡落在左边、署名他的。
    // 一般情况：署我的马甲名——**不能**用默认值（默认会填成对方的名字，
    // 于是对方下一句就成了“同一个人连发”，头像会被判成连发而不显示）。
    await _store.appendDmMessage(
      widget.contactName,
      text: text,
      mine: true,
      sender: senderName,
      divine: asDivine,
      withImage: _attachImage,
    );
    // 我主动找他：好感度按「我→他」事件微涨（夺舍不算，那是替他说话）。
    if (!asDivine) {
      unawaited(_social.applyAffinityEvent(
        widget.contactName,
        AffinityEvent.meToThem,
      ));
    }
    if (!mounted) return;
    setState(() {
      _attachImage = false;
      _messages = _store.dmMessages(widget.contactName);
    });
    _jumpToBottom();
    _scheduleReply(forceReply: _shouldForceReply(text));
  }

  /// 明确指令、召唤、剧情关键内容必须回，不能触发已读不回。
  bool _shouldForceReply(String text) {
    final t = text.trim();
    if (t.startsWith('/') || t.startsWith('!') || t.startsWith('！'))
      return true;
    return RegExp(r'召唤|角色扮演|剧情|继续|接着说|回答我').hasMatch(t);
  }

  /// 后台执行器状态变了：把 typing 和消息刷新到界面。
  void _onReplyChanged() {
    if (!mounted) return;
    setState(() => _messages = _store.dmMessages(widget.contactName));
    _jumpToBottom();
    // 人还在页上，回完就标已读；人不在页上时不走这里，红点留着。
    if (!WechatDmReplyRunner.instance.isPending(_chatKey)) {
      unawaited(_store.markRead(_chatKey));
    }
    final error = WechatDmReplyRunner.instance.takeError(_chatKey);
    if (error != null) _toast(error);
  }

  /// 隔一会儿他再回，太秒回像机器人。
  /// 等待和生成都交给后台执行器，退出页面也不会停。
  void _scheduleReply({
    Duration? summonDelay,
    bool forceReply = false,
    bool bypassPending = false,
  }) {
    // 控制剧情走向要强制插队：先取消还在等间隔的旧回复，别让剧情被 pending 挡掉。
    if (bypassPending) WechatDmReplyRunner.instance.cancelPending(_chatKey);
    if (WechatDmReplyRunner.instance.isPending(_chatKey)) return;
    // 冷场期内对方不主动回（召唤/天意强制发起的除外）。
    if (!forceReply &&
        _social.topic(socialDmScope(widget.contactName)).isCoolingDown) {
      return;
    }
    final isSummon = summonDelay != null;
    final delay = summonDelay ?? _replyDelay();
    WechatDmReplyRunner.instance.schedule(
      key: _chatKey,
      contactName: widget.contactName,
      store: _store,
      settings: context.read<SettingsProvider>(),
      worldBooks: context.read<WorldBookProvider>(),
      delay: delay,
      social: _social,
      momentStore: _momentStore,
      selfInitiated: isSummon,
      forceReply: forceReply || isSummon,
    );
  }

  /// 点聊天空白处 / 三点菜单：私聊的天意系统（切话题/结束/冷场）。
  Future<void> _showSkyMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (sheetCtx) => Theme(
        data: wechatLightTheme(),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _skyTile(sheetCtx, Lucide.SquarePen, '控制剧情走向', 'plot'),
              _skyTile(sheetCtx, Lucide.Shuffle, '切换话题', 'switch_topic'),
              _skyTile(sheetCtx, Lucide.CheckCircle, '结束话题', 'end_topic'),
              _skyTile(sheetCtx, Lucide.Moon, '冷场一会儿', 'cooldown'),
              _skyTile(sheetCtx, Lucide.Sun, '结束冷场', 'clear_cooldown'),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    await _handleSkyAction(action);
  }

  Widget _skyTile(
    BuildContext sheetCtx,
    IconData icon,
    String label,
    String value,
  ) {
    return ListTile(
      leading: Icon(icon, size: 20, color: wechatMenuInk),
      title: Text(label, style: const TextStyle(fontSize: 15, color: wechatMenuInk)),
      onTap: () => Navigator.of(sheetCtx).pop(value),
    );
  }

  Future<void> _handleSkyAction(String action) async {
    final scope = socialDmScope(widget.contactName);
    switch (action) {
      case 'plot':
        final plot = await showDialog<String>(
          context: context,
          builder: (_) => const WechatPlotDialog(),
        );
        if (!mounted || plot == null || plot.trim().isEmpty) return;
        // 控制剧情走向会结束冷场，立刻让他按剧情接一句。
        await _social.clearCooldown(scope);
        await _social.setDirective(scope, 'plot', text: plot.trim());
        await _social.addPlotLog(plot.trim(), scene: '私聊');
        _scheduleReply(forceReply: true, bypassPending: true);
        return;
      case 'switch_topic':
      case 'end_topic':
        await _social.setDirective(scope, action);
        _toast(action == 'switch_topic' ? '天意已定：换个话题' : '天意已定：话题收尾');
        // 让他接一句把天意演出来。
        _scheduleReply(forceReply: true);
        return;
      case 'cooldown':
        // 冷场：手动填分钟数，这段时间对方不主动回。
        final minutes = await showDialog<double>(
          context: context,
          builder: (_) => const WechatMinutesDialog(),
        );
        if (!mounted || minutes == null) return;
        final cool = Duration(milliseconds: (minutes * 60 * 1000).round());
        await _social.setCooldown(scope, cool);
        _toast('天意已定：冷场 $minutes 分钟');
        return;
      case 'clear_cooldown':
        await _social.clearCooldown(scope);
        _toast('天意已定：冷场结束');
        return;
    }
  }

  /// 磨多久由「这个人自己的回复间隔」决定（第三处间隔：单角色私聊）。
  Duration _replyDelay() {
    final contact = _contact;
    final effective = wechatEffectiveInterval(
      contact?.intervalPreset ?? WechatIntervalPreset.follow,
      customMinSeconds: contact?.customMinSeconds ?? 2,
      customMaxSeconds: contact?.customMaxSeconds ?? 12,
      settings: _settings,
    );
    return wechatDelayOf(
      effective.preset,
      customMinSeconds: effective.min,
      customMaxSeconds: effective.max,
      random: _random,
    );
  }

  /// 这个过程改了隔多久回你：第三处间隔（单角色私聊）就存在联系人身上。
  /// 私聊三点菜单「看好感度」：查看 + 作弊改分数/状态/颜值。
  Future<void> _showAffinity() async {
    final name = widget.contactName.trim();
    if (name.isEmpty) return;
    final current = _social.affinity(name);
    final updated = await showAffinityDialog(context, affinity: current);
    if (updated == null || !mounted) return;
    await _social.setAffinity(updated);
    if (!mounted) return;
    _toast('好感度已保存：${updated.score.round()} · ${updated.status}');
  }

  Future<void> _pickInterval() async {
    final contact = _contact;
    if (contact == null) return;
    var preset = contact.intervalPreset;
    var min = contact.customMinSeconds;
    var max = contact.customMaxSeconds;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (sheetCtx) => Theme(
        data: wechatLightTheme(),
        child: StatefulBuilder(
          builder: (ctx, setSheetState) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
                  child: Row(
                    children: <Widget>[
                      const Expanded(
                        child: Text(
                          '他多久回你一句',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: WechatColors.primaryText,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('好'),
                      ),
                    ],
                  ),
                ),
                WechatIntervalPicker(
                  preset: preset,
                  customMin: min,
                  customMax: max,
                  allowFollow: true,
                  note: preset == WechatIntervalPreset.follow
                      ? '正在跟随全局：${wechatIntervalLabel(_settings.intervalPreset, customMinSeconds: _settings.customMinSeconds, customMaxSeconds: _settings.customMaxSeconds)}'
                      : '只管你们两个人的私聊，跟群里的间隔不通用。',
                  onChanged: (nextPreset, nextMin, nextMax) {
                    setSheetState(() {
                      preset = nextPreset;
                      min = nextMin;
                      max = nextMax;
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (saved != true || !mounted) return;
    await _store.saveContact(
      contact.copyWith(
        intervalPreset: preset,
        customMinSeconds: min,
        customMaxSeconds: max,
      ),
    );
    if (!mounted) return;
    _reload();
  }

  /// 删掉跟这个人的聊天记录。人还留在通讯录里，随时能再聊。
  Future<void> _deleteChat() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('删除聊天记录？', style: TextStyle(fontSize: 16)),
        content: Text('和「${widget.contactName}」的聊天记录会全部删掉，人还留在通讯录里。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('算了'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('删除', style: TextStyle(color: WechatColors.red)),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;
    await _store.deleteDm(widget.contactName);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ---------------- 界面 ----------------

  @override
  Widget build(BuildContext context) {
    final contact = _contact;
    if (contact == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    return Theme(
      data: wechatLightTheme(),
      child: Scaffold(
        backgroundColor: WechatColors.chatBg,
        // 这里不用 Scaffold 自己顶：小手机里这页是套在嵌套路由里的，
        // 靠它顶不起来，改成按 viewInsets 自己算。
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          backgroundColor: WechatColors.navBg,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          shape: const Border(
            bottom: BorderSide(color: Color(0xFFD8D8D8), width: 0.5),
          ),
          leading: IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Lucide.ChevronLeft, size: 22, color: Colors.black),
          ),
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                contact.name,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              if (_typing)
                const Text(
                  '对方正在输入…',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: WechatColors.secondaryText,
                  ),
                ),
            ],
          ),
          actions: <Widget>[
            PopupMenuButton<String>(
              icon: const Icon(Lucide.Ellipsis, color: Colors.black),
              onSelected: (value) async {
                if (value == 'interval') await _pickInterval();
                if (value == 'affinity') await _showAffinity();
                if (value == 'divine') {
                  setState(() => _asDivine = !_asDivine);
                }
                if (value == 'delete') await _deleteChat();
                if (value == 'plot' ||
                    value == 'switch_topic' ||
                    value == 'end_topic' ||
                    value == 'cooldown' ||
                    value == 'clear_cooldown') {
                  await _handleSkyAction(value);
                }
              },
              itemBuilder: (_) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'plot',
                  child: Text('控制剧情走向'),
                ),
                PopupMenuItem<String>(
                  value: 'divine',
                  child: Text(_asDivine ? '恢复成我自己说话' : '天意：用他的身份说话'),
                ),
                const PopupMenuItem<String>(
                  value: 'switch_topic',
                  child: Text('切换话题'),
                ),
                const PopupMenuItem<String>(
                  value: 'end_topic',
                  child: Text('结束话题'),
                ),
                const PopupMenuItem<String>(
                  value: 'cooldown',
                  child: Text('冷场一会儿'),
                ),
                const PopupMenuItem<String>(
                  value: 'clear_cooldown',
                  child: Text('结束冷场'),
                ),
                const PopupMenuItem<String>(
                  value: 'interval',
                  child: Text('回复间隔'),
                ),
                const PopupMenuItem<String>(
                  value: 'affinity',
                  child: Text('看好感度'),
                ),
                const PopupMenuItem<String>(
                  value: 'delete',
                  child: Text('删除聊天记录'),
                ),
              ],
            ),
          ],
        ),
        body: Stack(
          children: <Widget>[
            // 键盘弹出时列表底部跟着收缩，可视区变矮后自动滚到最新一条，
            // 不用用户手动往上拖；顶部标题栏不动。
            Positioned.fill(
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _focus.unfocus(),
                  onLongPress: _showSkyMenu,
                  child: _messageList(),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: _inputBar(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _messageList() {
    if (_messages.isEmpty && !_typing) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            '还没聊过。发一句试试，${widget.contactName}会回你。',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: WechatColors.secondaryText,
              height: 1.7,
            ),
          ),
        ),
      );
    }
    final items = <Widget>[];
    String? lastSender;
    var lastAt = 0;
    for (final message in _messages) {
      if (message.at > 0 &&
          (lastAt == 0 ||
              message.at - lastAt >= wechatTimeDividerGap.inMilliseconds)) {
        items.add(WechatTimeDivider(millis: message.at));
      }
      if (message.at > 0) lastAt = message.at;
      if (message.recalled) {
        items.add(_recallRow(message));
        lastSender = null;
        continue;
      }
      if (message.plot) {
        items.add(_plotRow(message));
        lastSender = null;
        continue;
      }
      final mineHere = message.mine && !message.divine;
      final sameAsPrevious = lastSender == message.sender && !mineHere;
      items.add(_bubbleRow(message, showHead: !mineHere && !sameAsPrevious));
      lastSender = message.sender;
    }
    if (_typing) {
      items.add(_typingRow());
    }
    return ListView(
      controller: _scroll,
      // 底部留出输入栏高度：消息列表不随键盘移动，输入栏浮在上面。
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 72),
      children: items,
    );
  }

  /// 「控制剧情走向」落地的旁白：居中卡片，整段剧情、不挂人名。
  Widget _plotRow(WechatMessage message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 22),
      child: Center(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: const Color(0xFFFBF3E4),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFE8D4A8), width: 0.8),
          ),
          child: Text(
            message.text,
            style: const TextStyle(
              fontSize: 13.5,
              color: Color(0xFF6B5426),
              height: 1.55,
            ),
          ),
        ),
      ),
    );
  }

  /// 撤回后留的那句灰字。
  Widget _recallRow(WechatMessage message) {
    final mine = message.mine && !message.divine;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Text(
          mine ? '你撤回了一条消息' : '${message.sender}撤回了一条消息',
          style: const TextStyle(fontSize: 11.5, color: Color(0xFFA6A6A6)),
        ),
      ),
    );
  }

  // ---------------- 单条消息：长按菜单 ----------------

  Future<void> _showMessageMenu(WechatMessage message) async {
    if (_regenId != null) {
      _toast('等这条重写完再操作');
      return;
    }
    final mine = message.mine && !message.divine;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (sheetCtx) => Theme(
        data: wechatLightTheme(),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (mine)
                _menuItem(sheetCtx, Lucide.Pencil, '编辑', 'edit')
              else
                _menuItem(sheetCtx, Lucide.RefreshCw, '重新生成', 'regen'),
              _menuItem(sheetCtx, Lucide.History, '撤回', 'recall'),
              _menuItem(sheetCtx, Lucide.Trash2, '删除', 'delete', danger: true),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'edit':
        await _editMessage(message);
      case 'regen':
        await _regenerateMessage(message);
      case 'recall':
        await _store.recallMessage(_chatKey, message.id);
        if (!mounted) return;
        setState(() => _messages = _store.dmMessages(widget.contactName));
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            backgroundColor: Colors.white,
            title: const Text('删掉这条？', style: TextStyle(fontSize: 16)),
            content: const Text('删了就没了，不留记录。想留个痕迹用「撤回」。'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: const Text('算了'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(true),
                child: const Text(
                  '删除',
                  style: TextStyle(color: WechatColors.red),
                ),
              ),
            ],
          ),
        );
        if (!mounted || ok != true) return;
        await _store.deleteMessage(_chatKey, message.id);
        if (!mounted) return;
        setState(() => _messages = _store.dmMessages(widget.contactName));
    }
  }

  Widget _menuItem(
    BuildContext sheetCtx,
    IconData icon,
    String label,
    String value, {
    bool danger = false,
  }) {
    final color = danger ? WechatColors.red : wechatMenuInk;
    return ListTile(
      leading: Icon(icon, size: 20, color: color),
      title: Text(label, style: TextStyle(fontSize: 15, color: color)),
      onTap: () => Navigator.of(sheetCtx).pop(value),
    );
  }

  Future<void> _editMessage(WechatMessage message) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => WechatEditMessageDialog(initial: message.text),
    );
    final next = (text ?? '').trim();
    if (!mounted || next.isEmpty || next == message.text) return;
    await _store.editMessage(_chatKey, message.id, next);
    if (!mounted) return;
    setState(() => _messages = _store.dmMessages(widget.contactName));
  }

  /// 用**这条之前**的记录让他重说一遍。
  Future<void> _regenerateMessage(WechatMessage message) async {
    if (_regenId != null) return;
    final contact = _contact;
    if (contact == null) {
      _toast('这个人不在通讯录里了');
      return;
    }
    final index = _messages.indexWhere((m) => m.id == message.id);
    if (index < 0) return;
    final before = _messages.sublist(0, index);
    setState(() => _regenId = message.id);
    try {
      final generator = WechatDmGenerator(
        settings: context.read<SettingsProvider>(),
        worldBooks: context.read<WorldBookProvider>(),
        contact: contact,
        bookIds: _settings.bookIds,
        persona: _settings.effectivePersona,
        worldPrompt: _settings.worldPrompt,
        history: wechatRecentContext(before),
      );
      // 重新生成只替换这一条，明确要一条。
      final text = await generator.generate(burstCount: 1);
      final parts = wechatSplitReply(text, maxParts: 1);
      if (!mounted) return;
      if (parts.isEmpty) {
        setState(() => _regenId = null);
        _toast('这次没写出东西，再试一次');
        return;
      }
      final parsed = wechatStripImageMark(parts.first);
      if (parsed.text.isEmpty) {
        setState(() => _regenId = null);
        _toast('这次没写出东西，再试一次');
        return;
      }
      await _store.editMessage(
        _chatKey,
        message.id,
        parsed.text,
        withImage: parsed.withImage,
      );
      if (!mounted) return;
      setState(() {
        _regenId = null;
        _messages = _store.dmMessages(widget.contactName);
      });
    } on WechatServiceException catch (error) {
      if (!mounted) return;
      setState(() => _regenId = null);
      _toast(
        error.code == 'model_missing'
            ? '这个人还没选模型，去「我 → 设置 → 角色管理」挑一个'
            : '这次没生成出内容',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _regenId = null);
      _toast('这次没重写成功，再点一次');
    }
  }

  Widget _bubbleRow(WechatMessage message, {required bool showHead}) {
    final mine = message.mine && !message.divine;
    final maxWidth = MediaQuery.of(context).size.width * 0.68;
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: mine ? WechatColors.mineBubble : WechatColors.otherBubble,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            message.text,
            style: const TextStyle(
              fontSize: 15,
              height: 1.42,
              color: WechatColors.primaryText,
            ),
          ),
          if (message.withImage) ...<Widget>[
            const SizedBox(height: 6),
            WechatEmojiImage(text: message.text, seed: message.id),
          ],
        ],
      ),
    );

    // 长按出菜单：自己的能改，他的能重写。
    final tappableBubble = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _showMessageMenu(message),
      child: Opacity(opacity: _regenId == message.id ? 0.45 : 1, child: bubble),
    );

    final avatar = mine
        ? WechatAvatarText(
            name: _settings.effectivePersona,
            size: 38,
            // 我的头像在朋友圈的 @me 底下，store 里已经按马甲名挂了一份。
            imagePath: _avatars[_settings.effectivePersona],
          )
        : WechatAvatarText(
            name: message.sender,
            size: 38,
            imagePath: _avatars[message.sender],
          );

    return Padding(
      padding: EdgeInsets.fromLTRB(12, showHead ? 10 : 4, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: mine
            ? <Widget>[tappableBubble, const SizedBox(width: 8), avatar]
            : <Widget>[
                showHead ? avatar : const SizedBox(width: 38),
                const SizedBox(width: 8),
                tappableBubble,
              ],
      ),
    );
  }

  Widget _typingRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        children: <Widget>[
          WechatAvatarText(
            name: widget.contactName,
            size: 38,
            imagePath: _avatars[widget.contactName],
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: WechatColors.otherBubble,
              borderRadius: BorderRadius.circular(5),
            ),
            child: const Text(
              '···',
              style: TextStyle(
                fontSize: 14,
                color: WechatColors.secondaryText,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF7F7F7),
        border: Border(
          top: BorderSide(color: WechatColors.hairline, width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (_asDivine)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                child: Row(
                  children: <Widget>[
                    const Icon(Lucide.User, size: 13, color: Color(0xFF07C160)),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        '正在用「${widget.contactName}」的身份说话',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF07C160),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  _placeholderIcon(Lucide.Mic),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 36),
                      padding: const EdgeInsets.symmetric(horizontal: 11),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: TextField(
                        controller: _input,
                        focusNode: _focus,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        style: const TextStyle(
                          fontSize: 15,
                          color: WechatColors.primaryText,
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 9),
                          hintText: '',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 占位：表情、加号。真功能以后再加，先把位置留着。
                  _imageButton(),
                  const SizedBox(width: 6),
                  _placeholderIcon(Lucide.Plus),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: _send,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: WechatColors.green,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        '发送',
                        style: TextStyle(fontSize: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 发图开关：点亮后这条消息带图，图按文字内容用 emoji 拼出来。
  Widget _imageButton() {
    return GestureDetector(
      onTap: () => setState(() => _attachImage = !_attachImage),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: _attachImage ? const Color(0xFFE7F8EE) : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Icon(
          Lucide.Image,
          size: 22,
          color: _attachImage ? WechatColors.green : const Color(0xFF8A8A8A),
        ),
      ),
    );
  }

  Widget _placeholderIcon(IconData icon) {
    return GestureDetector(
      onTap: () => _toast('这个功能还没做'),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Icon(icon, size: 26, color: const Color(0xFF4A4A4A)),
      ),
    );
  }
}
