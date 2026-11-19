import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/providers/world_book_provider.dart';
import '../../core/services/chat/chat_service.dart';
import '../../icons/lucide_adapter.dart';
import 'wechat_models.dart';
import 'wechat_scheduler.dart';
import 'wechat_ui.dart';
import 'wechat_service.dart';
import 'wechat_settings_page.dart';
import 'wechat_store.dart';

/// 打开微信：先进会话列表。
Future<void> openWechat(BuildContext context) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (sheetCtx) => const WechatPage()),
  );
}

// ============================================================
// 会话列表
// ============================================================

class WechatPage extends StatefulWidget {
  const WechatPage({super.key});

  @override
  State<WechatPage> createState() => _WechatPageState();
}

class _WechatPageState extends State<WechatPage> {
  late WechatStore _store;
  List<WechatGroup> _groups = const <WechatGroup>[];

  @override
  void initState() {
    super.initState();
    _store = WechatStore(context.read<ChatService>());
    _reload();
  }

  void _reload() {
    if (!mounted) return;
    setState(() => _groups = _store.groups());
  }

  Future<void> _createGroup() async {
    final group = await _store.createGroup(name: '新群聊');
    if (!mounted) return;
    _reload();
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (sheetCtx) => WechatSettingsPage(groupId: group.id),
      ),
    );
    _reload();
    if (changed == true && mounted) {
      await _openChat(group.id);
      _reload();
    }
  }

  Future<void> _openChat(String groupId) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (sheetCtx) => WechatChatPage(groupId: groupId),
      ),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: wechatLightTheme(),
      child: Scaffold(
        backgroundColor: WechatColors.listBg,
        appBar: AppBar(
          backgroundColor: const Color(0xFFF7F7F7),
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          shape: const Border(
            bottom: BorderSide(color: Color(0xFFE0E0E0), width: 0.5),
          ),
          title: const Text(
            '微信',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          leading: IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Lucide.ChevronLeft, size: 22, color: Colors.black),
          ),
          actions: <Widget>[
            IconButton(
              onPressed: _createGroup,
              icon: const Icon(Lucide.Plus, size: 22, color: Colors.black),
            ),
          ],
        ),
        body: _groups.isEmpty ? _emptyState() : _groupList(),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Lucide.MessagesSquare,
              size: 44,
              color: WechatColors.secondaryText.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 14),
            const Text(
              '还没有群聊',
              style: TextStyle(fontSize: 15, color: WechatColors.secondaryText),
            ),
            const SizedBox(height: 6),
            const Text(
              '点右上角 + 建一个，把人拉进来就能聊',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: WechatColors.secondaryText,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _createGroup,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF07C160),
                padding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 11,
                ),
              ),
              child: const Text('新建群聊'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupList() {
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: _groups.length,
      itemBuilder: (_, index) {
        final group = _groups[index];
        final messages = _store.messages(group.id);
        final last = messages.isEmpty ? null : messages.last;
        final preview = last == null
            ? '还没人说话'
            : (last.system
                  ? last.text
                  : '${last.mine ? group.effectivePersona : last.sender}：${last.text}');
        return InkWell(
          onTap: () => _openChat(group.id),
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
            child: Row(
              children: <Widget>[
                _groupAvatar(group),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              group.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                color: WechatColors.primaryText,
                              ),
                            ),
                          ),
                          if (messages.isNotEmpty)
                            Text(
                              _shortTime(last?.at ?? 0),
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFFB3B3B3),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: WechatColors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _groupAvatar(WechatGroup group) {
    final members = group.members;
    if (members.isEmpty) {
      return Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: const Color(0xFFDCDCDC),
          borderRadius: BorderRadius.circular(5),
        ),
        alignment: Alignment.center,
        child: const Icon(Lucide.User, size: 22, color: Colors.white),
      );
    }
    if (members.length == 1) {
      return WechatAvatarText(name: members.first.name, size: 46);
    }
    final shown = members.take(4).toList();
    return Container(
      width: 46,
      height: 46,
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        color: const Color(0xFFDCDCDC),
        borderRadius: BorderRadius.circular(5),
      ),
      child: GridView.count(
        crossAxisCount: 2,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 1.5,
        crossAxisSpacing: 1.5,
        children: <Widget>[
          for (final member in shown)
            Container(
              decoration: BoxDecoration(
                color: wechatAvatarColor(member.name),
                borderRadius: BorderRadius.circular(1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                wechatInitialOf(member.name),
                style: const TextStyle(
                  fontSize: 9,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          for (var i = shown.length; i < 4; i++)
            Container(color: const Color(0xFFE8E8E8)),
        ],
      ),
    );
  }
}

// ============================================================
// 群聊页
// ============================================================

class WechatChatPage extends StatefulWidget {
  const WechatChatPage({super.key, required this.groupId});

  final String groupId;

  @override
  State<WechatChatPage> createState() => _WechatChatPageState();
}

class _WechatChatPageState extends State<WechatChatPage> {
  late WechatStore _store;
  final WechatScheduler _scheduler = WechatScheduler();
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();

  WechatGroup? _group;
  List<WechatMessage> _messages = const <WechatMessage>[];
  Timer? _timer;

  /// 正在想词的人（显示“正在输入”）。
  String? _typingName;

  /// 自动循环关掉了就不主动找人说话，只回你手动发的。
  bool _autoLoop = true;

  /// 长按空白后才把天意消息标出来。
  bool _showDivineMark = false;

  @override
  void initState() {
    super.initState();
    _store = WechatStore(context.read<ChatService>());
    _group = _store.group(widget.groupId);
    _reload();
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
    final group = _store.group(widget.groupId);
    if (group == null) return;
    setState(() {
      _group = group;
      _messages = _store.messages(widget.groupId);
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

  // ---------------- 发消息 ----------------

  Future<void> _send() async {
    final group = _group;
    if (group == null) return;
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    final divine = group.divine.trim();
    final asDivine = divine.isNotEmpty;
    final message = await _store.appendMessage(
      group.id,
      sender: asDivine ? divine : group.effectivePersona,
      text: text,
      mine: true,
      divine: asDivine,
    );
    if (!mounted) return;
    setState(() => _messages = <WechatMessage>[..._messages, message]);
    _jumpToBottom();
    _restartLoop();
  }

  // ---------------- 自动循环 ----------------

  void _restartLoop() {
    _timer?.cancel();
    if (!_autoLoop || _group == null) return;
    final delay = _scheduler.nextDelay(_group!);
    _timer = Timer(delay, () => _tick());
  }

  Future<void> _tick() async {
    if (!mounted || !_autoLoop) return;
    final group = _group;
    if (group == null) return;
    final speaker = _scheduler.pickSpeaker(group, _messages);
    if (speaker == null) return;
    setState(() => _typingName = speaker.name);
    try {
      final generator = WechatGenerator(
        settings: context.read<SettingsProvider>(),
        worldBooks: context.read<WorldBookProvider>(),
        group: group,
        history: wechatRecentContext(_messages),
      );
      final text = await generator.generateFor(speaker);
      if (!mounted) return;
      final message = await _store.appendMessage(
        group.id,
        sender: speaker.name,
        text: text,
      );
      if (!mounted) return;
      setState(() {
        _typingName = null;
        _messages = <WechatMessage>[..._messages, message];
      });
      _jumpToBottom();
      _restartLoop();
    } on WechatServiceException catch (error) {
      if (!mounted) return;
      setState(() {
        _typingName = null;
        _autoLoop = false;
      });
      _toast(_messageFor(error));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _typingName = null;
        _autoLoop = false;
      });
      _toast('这次没接上，点右上角继续');
    }
  }

  String _messageFor(WechatServiceException error) {
    switch (error.code) {
      case 'model_missing':
        return '这个群还没选模型，去设置里挑一个';
      case 'empty':
        return '这次没生成出内容，点右上角继续';
      default:
        return '生成失败了，点右上角继续';
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
      );
  }

  // ---------------- 长按空白 ----------------

  Future<void> _showBlankMenu() async {
    final group = _group;
    if (group == null) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: Icon(
                _showDivineMark ? Lucide.EyeOff : Lucide.Eye,
                size: 20,
              ),
              title: Text(_showDivineMark ? '隐藏天意消息' : '查看天意消息'),
              onTap: () => Navigator.of(sheetCtx).pop('mark'),
            ),
            ListTile(
              leading: const Icon(Lucide.User, size: 20),
              title: const Text('天意：换个身份说话'),
              onTap: () => Navigator.of(sheetCtx).pop('divine'),
            ),
            if (group.divine.trim().isNotEmpty)
              ListTile(
                leading: const Icon(Lucide.RotateCcw, size: 20),
                title: const Text('恢复成我自己'),
                onTap: () => Navigator.of(sheetCtx).pop('reset'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'mark') {
      setState(() => _showDivineMark = !_showDivineMark);
      return;
    }
    if (action == 'reset') {
      final next = group.copyWith(divine: '');
      await _store.saveGroup(next);
      if (!mounted) return;
      setState(() => _group = next);
      return;
    }
    if (action == 'divine') {
      await _pickDivine(group);
    }
  }

  Future<void> _pickDivine(WechatGroup group) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 16, 18, 8),
              child: Text(
                '接下来用谁的身份说话',
                style: TextStyle(
                  fontSize: 13,
                  color: WechatColors.secondaryText,
                ),
              ),
            ),
            for (final member in group.members)
              ListTile(
                leading: WechatAvatarText(name: member.name, size: 34),
                title: Text(member.name),
                trailing: group.divine.trim() == member.name
                    ? const Icon(
                        Lucide.Check,
                        size: 18,
                        color: Color(0xFF07C160),
                      )
                    : null,
                onTap: () => Navigator.of(sheetCtx).pop(member.name),
              ),
          ],
        ),
      ),
    );
    if (!mounted || picked == null) return;
    final next = group.copyWith(divine: picked);
    await _store.saveGroup(next);
    if (!mounted) return;
    setState(() => _group = next);
    _toast('现在用「$picked」的身份说话');
  }

  // ---------------- 界面 ----------------

  @override
  Widget build(BuildContext context) {
    final group = _group;
    if (group == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    return Theme(
      data: wechatLightTheme(),
      child: Scaffold(
        backgroundColor: WechatColors.chatBg,
        // 键盘起来时整页压缩，输入栏贴着键盘上沿，气泡不会被挡住。
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
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '${group.name} (${group.members.length})',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              if (_typingName != null)
                Text(
                  '$_typingName 正在输入…',
                  style: const TextStyle(
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
                if (value == 'settings') {
                  await Navigator.of(context).push<bool>(
                    MaterialPageRoute<bool>(
                      builder: (sheetCtx) =>
                          WechatSettingsPage(groupId: group.id),
                    ),
                  );
                  _reload();
                } else if (value == 'toggle') {
                  setState(() => _autoLoop = !_autoLoop);
                  if (_autoLoop) {
                    _restartLoop();
                  } else {
                    _timer?.cancel();
                  }
                } else if (value == 'divine') {
                  await _pickDivine(group);
                }
              },
              itemBuilder: (_) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'toggle',
                  child: Text(_autoLoop ? '暂停自动回复' : '继续自动回复'),
                ),
                const PopupMenuItem<String>(
                  value: 'divine',
                  child: Text('天意：换个身份说话'),
                ),
                const PopupMenuItem<String>(
                  value: 'settings',
                  child: Text('群设置'),
                ),
              ],
            ),
          ],
        ),
        body: Column(
          children: <Widget>[
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: _showBlankMenu,
                child: _messageList(group),
              ),
            ),
            _inputBar(group),
          ],
        ),
      ),
    );
  }

  Widget _messageList(WechatGroup group) {
    if (_messages.isEmpty && _typingName == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            group.members.isEmpty ? '群里还没人，点右上角进群设置把人拉进来' : '发一句话，群里就开始聊了',
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
    for (var i = 0; i < _messages.length; i++) {
      final message = _messages[i];
      if (message.system) {
        items.add(_systemRow(message));
        lastSender = null;
        continue;
      }
      final sameAsPrevious = lastSender == message.sender && !message.mine;
      items.add(
        _bubbleRow(group, message, showHead: !message.mine && !sameAsPrevious),
      );
      lastSender = message.sender;
    }
    if (_typingName != null) {
      items.add(_typingRow());
    }
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
      children: items,
    );
  }

  Widget _systemRow(WechatMessage message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 40),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0x14000000),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            message.text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11.5,
              color: Color(0xFFA6A6A6),
              height: 1.45,
            ),
          ),
        ),
      ),
    );
  }

  Widget _bubbleRow(
    WechatGroup group,
    WechatMessage message, {
    required bool showHead,
  }) {
    final mine = message.mine;
    final marked = _showDivineMark && message.divine;
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 258),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: mine ? WechatColors.mineBubble : WechatColors.otherBubble,
        borderRadius: BorderRadius.circular(4.5),
        border: marked
            ? Border.all(color: const Color(0xFF07C160), width: 1)
            : null,
      ),
      child: Text(
        message.text,
        style: const TextStyle(
          fontSize: 15.5,
          height: 1.42,
          color: WechatColors.primaryText,
        ),
      ),
    );

    // 气泡上吞掉长按，免得点消息也弹出空白菜单。
    final guardedBubble = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () {},
      child: bubble,
    );

    final column = Column(
      crossAxisAlignment: mine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: <Widget>[
        if (!mine && showHead)
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 3),
            child: Text(
              message.sender,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF9A9A9A),
                height: 1,
              ),
            ),
          ),
        guardedBubble,
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 2),
      child: Row(
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (!mine) ...<Widget>[
            if (showHead)
              WechatAvatarText(name: message.sender, size: 38)
            else
              const SizedBox(width: 38),
            const SizedBox(width: 9),
          ],
          Flexible(child: column),
          if (mine) ...<Widget>[
            const SizedBox(width: 9),
            WechatAvatarText(name: group.effectivePersona, size: 38),
          ],
        ],
      ),
    );
  }

  Widget _typingRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      child: Row(
        children: <Widget>[
          WechatAvatarText(name: _typingName ?? '', size: 38),
          const SizedBox(width: 9),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: WechatColors.otherBubble,
              borderRadius: BorderRadius.circular(4.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (var i = 0; i < 3; i++)
                  Padding(
                    padding: EdgeInsets.only(right: i == 2 ? 0 : 4),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: Color(0xFFB9B9B9),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputBar(WechatGroup group) {
    final divine = group.divine.trim();
    final asDivine = divine.isNotEmpty;
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
            if (asDivine)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                child: Row(
                  children: <Widget>[
                    const Icon(Lucide.User, size: 13, color: Color(0xFF07C160)),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        '正在用「$divine」的身份说话',
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
                          hintText: '说点什么…',
                          hintStyle: TextStyle(
                            fontSize: 15,
                            color: Color(0xFFB2B2B2),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _send,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF07C160),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Text(
                        '发送',
                        style: TextStyle(fontSize: 14.5, color: Colors.white),
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
}

String _shortTime(int millis) {
  if (millis <= 0) return '';
  final time = DateTime.fromMillisecondsSinceEpoch(millis);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(time.year, time.month, time.day);
  final diff = today.difference(that).inDays;
  if (diff == 0) {
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
  if (diff == 1) return '昨天';
  if (diff < 7) {
    const weeks = <String>['一', '二', '三', '四', '五', '六', '日'];
    return '星期${weeks[time.weekday - 1]}';
  }
  final mo = time.month.toString().padLeft(2, '0');
  final day = time.day.toString().padLeft(2, '0');
  return '$mo-$day';
}
