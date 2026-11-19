import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/providers/world_book_provider.dart';
import '../../core/services/chat/chat_service.dart';
import '../../icons/lucide_adapter.dart';
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
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();
  final Random _random = Random();

  WechatContact? _contact;
  WechatSettings _settings = const WechatSettings();
  Map<String, String> _avatars = const <String, String>{};
  List<WechatMessage> _messages = const <WechatMessage>[];

  /// 他正在想词。
  bool _typing = false;

  /// 正在等他这一句回来，别让用户连发两次把他淹了。
  bool _waiting = false;

  Timer? _timer;

  /// 天意：用他的身份说话（夺舍）。私聊里也一样能用。
  bool _asDivine = false;

  @override
  void initState() {
    super.initState();
    _store = WechatStore(context.read<ChatService>());
    _reload();
    unawaited(_store.markRead(WechatStore.dmKey(widget.contactName)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _jumpToBottom();
    });
    // 召唤进来的：他先说话。给一小段时间让页面站稳再开口。
    if (widget.summon) {
      _timer = Timer(const Duration(milliseconds: 500), _reply);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
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
    final text = _input.text.trim();
    if (text.isEmpty) return;
    if (_contact == null) return;
    _input.clear();
    final contact = _contact;
    // 夺舍：以他的身份发，气泡落在左边、署名他的。
    // 一般情况：署我的马甲名——**不能**用默认值（默认会填成对方的名字，
    // 于是对方下一句就成了“同一个人连发”，头像会被判成连发而不显示）。
    await _store.appendDmMessage(
      widget.contactName,
      text: text,
      mine: true,
      sender: _asDivine
          ? (contact?.name ?? widget.contactName)
          : _settings.effectivePersona,
      divine: _asDivine,
    );
    if (!mounted) return;
    setState(() => _messages = _store.dmMessages(widget.contactName));
    _jumpToBottom();
    _scheduleReply();
  }

  /// 隔一会儿他再回，太秒回像机器人。
  /// 磨多久由「这个人自己的回复间隔」决定（第三处间隔：单角色私聊）。
  void _scheduleReply() {
    if (_waiting) return;
    _timer?.cancel();
    final contact = _contact;
    final delay = wechatDelayOf(
      contact?.intervalPreset ?? WechatIntervalPreset.normal,
      customMinSeconds: contact?.customMinSeconds ?? 2,
      customMaxSeconds: contact?.customMaxSeconds ?? 12,
      random: _random,
    );
    _timer = Timer(delay, _reply);
  }

  Future<void> _reply() async {
    final contact = _contact;
    if (contact == null || !mounted) return;
    setState(() {
      _typing = true;
      _waiting = true;
    });
    try {
      final generator = WechatDmGenerator(
        settings: context.read<SettingsProvider>(),
        worldBooks: context.read<WorldBookProvider>(),
        contact: contact,
        bookIds: _settings.bookIds,
        persona: _settings.effectivePersona,
        worldPrompt: _settings.worldPrompt,
        history: _messages.length > 40
            ? _messages.sublist(_messages.length - 40)
            : _messages,
      );
      final text = await generator.generate();
      if (!mounted) return;
      await _store.appendDmMessage(widget.contactName, text: text, mine: false);
      if (!mounted) return;
      setState(() => _messages = _store.dmMessages(widget.contactName));
      _jumpToBottom();
      unawaited(_store.markRead(WechatStore.dmKey(widget.contactName)));
    } on WechatServiceException catch (error) {
      if (!mounted) return;
      _toast(
        error.code == 'model_missing'
            ? '这个人还没选模型，去「我 → 设置 → 角色管理」挑一个'
            : '这次没生成出内容',
      );
    } catch (_) {
      if (!mounted) return;
      _toast('这次没接上，再发一句试试');
    } finally {
      if (mounted) {
        setState(() {
          _typing = false;
          _waiting = false;
        });
      }
    }
  }

  /// 这个过程改了隔多久回你：第三处间隔（单角色私聊）就存在联系人身上。
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
                  note: '只管你们两个人的私聊，跟群里的间隔不通用。',
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
        resizeToAvoidBottomInset: true,
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
          title: Text(
            contact.name,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          actions: <Widget>[
            PopupMenuButton<String>(
              icon: const Icon(Lucide.Ellipsis, color: Colors.black),
              onSelected: (value) async {
                if (value == 'interval') await _pickInterval();
                if (value == 'divine') {
                  setState(() => _asDivine = !_asDivine);
                }
              },
              itemBuilder: (_) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'divine',
                  child: Text(_asDivine ? '恢复成我自己说话' : '天意：用他的身份说话'),
                ),
                const PopupMenuItem<String>(
                  value: 'interval',
                  child: Text('回复间隔'),
                ),
              ],
            ),
          ],
        ),
        body: Column(
          children: <Widget>[
            Expanded(child: _messageList()),
            _inputBar(),
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
    for (final message in _messages) {
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
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
      children: items,
    );
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
      child: Text(
        message.text,
        style: const TextStyle(
          fontSize: 15,
          height: 1.42,
          color: WechatColors.primaryText,
        ),
      ),
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
            ? <Widget>[bubble, const SizedBox(width: 8), avatar]
            : <Widget>[
                showHead ? avatar : const SizedBox(width: 38),
                const SizedBox(width: 8),
                bubble,
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
                  _placeholderIcon(Lucide.Sparkles),
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
