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
  const WechatDmPage({super.key, required this.contactName});

  final String contactName;

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

  @override
  void initState() {
    super.initState();
    _store = WechatStore(context.read<ChatService>());
    _reload();
    unawaited(_store.markRead(WechatStore.dmKey(widget.contactName)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _jumpToBottom();
    });
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
      _contact = _store.contact(widget.contactName);
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
    await _store.appendDmMessage(widget.contactName, text: text, mine: true);
    if (!mounted) return;
    setState(() => _messages = _store.dmMessages(widget.contactName));
    _jumpToBottom();
    _scheduleReply();
  }

  /// 隔一小会儿他再回，太秒回像机器人。
  /// 第二批会接上「回复间隔」那套设置，现在先给个短随机。
  void _scheduleReply() {
    if (_waiting) return;
    _timer?.cancel();
    final seconds = 2 + _random.nextInt(6);
    _timer = Timer(Duration(seconds: seconds), _reply);
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
      final sameAsPrevious = lastSender == message.sender && !message.mine;
      items.add(
        _bubbleRow(message, showHead: !message.mine && !sameAsPrevious),
      );
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
    final mine = message.mine;
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
        child: Padding(
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
