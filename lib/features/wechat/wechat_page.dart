import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/providers/world_book_provider.dart';
import '../../core/services/chat/chat_service.dart';
import '../../icons/lucide_adapter.dart';
import 'wechat_models.dart';
import 'wechat_contacts_page.dart';
import 'wechat_dm_page.dart';
import 'wechat_me_page.dart';
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
// 微信外壳：微信 / 通讯录 / 发现 / 我
// ============================================================

/// 会话列表里的一行：群或者私聊，统一看待。
class _WechatSession {
  const _WechatSession({
    required this.key,
    required this.title,
    required this.isGroup,
    required this.memberNames,
    required this.last,
    required this.unread,
  });

  /// 群 id，或者 `dm:名字`。
  final String key;
  final String title;
  final bool isGroup;

  /// 拿来画头像：私聊就一个人，群就是成员。
  final List<String> memberNames;

  final WechatMessage? last;
  final int unread;

  int get sortAt => last?.at ?? 0;
}

class WechatPage extends StatefulWidget {
  const WechatPage({super.key});

  @override
  State<WechatPage> createState() => _WechatPageState();
}

class _WechatPageState extends State<WechatPage> {
  late WechatStore _store;
  int _tab = 0;

  /// 老数据迁完没有。没迁完先别建子页面，不然通讯录会读到空的。
  bool _ready = false;

  /// 每刷新一次 +1，拿去通知 IndexedStack 里的子页重读设置。
  int _revision = 0;

  List<WechatGroup> _groups = const <WechatGroup>[];
  List<WechatContact> _contacts = const <WechatContact>[];
  Map<String, String> _avatars = const <String, String>{};

  @override
  void initState() {
    super.initState();
    _store = WechatStore(context.read<ChatService>());
    _bootstrap();
  }

  /// 先把老数据迁一遍（以前的群成员补进通讯录），再读。
  Future<void> _bootstrap() async {
    await _store.ensureMigrated();
    if (!mounted) return;
    _reload();
    setState(() => _ready = true);
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _revision++;
      _groups = _store.groups();
      _contacts = _store.contacts();
      _avatars = _store.avatarPaths();
    });
  }

  // ---------------- 会话 ----------------

  List<_WechatSession> _sessions() {
    final out = <_WechatSession>[];
    for (final group in _groups) {
      final messages = _store.messages(group.id);
      out.add(
        _WechatSession(
          key: group.id,
          title: group.name,
          isGroup: true,
          memberNames: <String>[for (final m in group.members) m.name],
          last: messages.isEmpty ? null : messages.last,
          unread: _store.unreadOf(group.id),
        ),
      );
    }
    for (final key in _store.dmKeysWithMessages()) {
      final name = key.substring(3);
      final messages = _store.messages(key);
      if (messages.isEmpty) continue;
      out.add(
        _WechatSession(
          key: key,
          title: name,
          isGroup: false,
          memberNames: <String>[name],
          last: messages.last,
          unread: _store.unreadOf(key),
        ),
      );
    }
    out.sort((a, b) => b.sortAt.compareTo(a.sortAt));
    return out;
  }

  /// 长按会话：删掉这次聊天（群连群一起删，私聊只删记录）。
  Future<void> _showSessionMenu(_WechatSession session) async {
    final isGroup = session.isGroup;
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
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    session.title,
                    style: const TextStyle(
                      fontSize: 13,
                      color: WechatColors.secondaryText,
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(
                  Lucide.Trash2,
                  size: 20,
                  color: wechatMenuInk,
                ),
                title: Text(
                  isGroup ? '删除群聊' : '删除聊天记录',
                  style: const TextStyle(fontSize: 15, color: wechatMenuInk),
                ),
                subtitle: Text(
                  isGroup ? '连群带记录一起删，删了拿不回来' : '只删你们的聊天，人还留在通讯录',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: WechatColors.secondaryText,
                  ),
                ),
                onTap: () => Navigator.of(sheetCtx).pop('delete'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action != 'delete') return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          isGroup ? '删除这个群？' : '删除聊天记录？',
          style: const TextStyle(fontSize: 16),
        ),
        content: Text(
          isGroup
              ? '「${session.title}」和里面的聊天记录都会删掉，删了拿不回来。'
              : '和「${session.title}」的聊天记录会全部删掉，人还留在通讯录里。',
        ),
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
    if (isGroup) {
      await _store.deleteGroup(session.key);
    } else {
      await _store.deleteDm(session.title);
    }
    if (!mounted) return;
    _reload();
  }

  Future<void> _openSession(_WechatSession session) async {
    if (session.isGroup) {
      await _openChat(session.key);
    } else {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => WechatDmPage(contactName: session.title),
        ),
      );
    }
    _reload();
  }

  Future<void> _openChat(String groupId) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (sheetCtx) => WechatChatPage(groupId: groupId),
      ),
    );
    _reload();
  }

  // ---------------- 新建群 ----------------

  /// 点 + 先进群列表，最下面才是「新建群聊」。
  /// 没点新建就什么都不发生，不会凭空多出一个空群。
  Future<void> _showGroupPicker() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 16, 18, 8),
                child: Text(
                  '选择群聊',
                  style: TextStyle(
                    fontSize: 13,
                    color: WechatColors.secondaryText,
                  ),
                ),
              ),
              Expanded(
                child: _groups.isEmpty
                    ? const Center(
                        child: Text(
                          '还没有群聊',
                          style: TextStyle(
                            fontSize: 13,
                            color: WechatColors.secondaryText,
                          ),
                        ),
                      )
                    : ListView(
                        children: <Widget>[
                          for (final group in _groups)
                            ListTile(
                              leading: _groupAvatar(group),
                              title: Text(
                                group.name,
                                style: const TextStyle(
                                  fontSize: 15,
                                  color: WechatColors.primaryText,
                                ),
                              ),
                              subtitle: Text(
                                '${group.memberCount} 人',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: WechatColors.secondaryText,
                                ),
                              ),
                              onTap: () => Navigator.of(
                                sheetCtx,
                              ).pop('open:${group.id}'),
                            ),
                        ],
                      ),
              ),
              const Divider(height: 0.5, thickness: 0.5),
              ListTile(
                leading: const Icon(
                  Lucide.Plus,
                  size: 20,
                  color: WechatColors.green,
                ),
                title: const Text(
                  '新建群聊',
                  style: TextStyle(fontSize: 15, color: WechatColors.green),
                ),
                onTap: () => Navigator.of(sheetCtx).pop('new'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'new') {
      await _createGroup();
      return;
    }
    if (action.startsWith('open:')) {
      await _openChat(action.substring(5));
    }
  }

  /// 只有点了「新建群聊」才会走到这里。
  Future<void> _createGroup() async {
    // 新群默认用微信设置里那几本世界书，不选也能马上有人设。
    final group = await _store.createGroup(
      name: '新群聊',
      bookIds: _store.wechatSettings().bookIds,
    );
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

  // ---------------- 界面 ----------------

  @override
  Widget build(BuildContext context) {
    final titles = <String>['微信', '通讯录', '发现', '我'];
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
          title: Text(
            titles[_tab],
            style: const TextStyle(
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
            if (_tab == 0)
              IconButton(
                onPressed: _showGroupPicker,
                icon: const Icon(Lucide.Plus, size: 22, color: Colors.black),
                tooltip: '群聊',
              ),
          ],
        ),
        body: !_ready
            ? const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IndexedStack(
                index: _tab,
                children: <Widget>[
                  _sessionList(),
                  WechatContactsPage(onChanged: _reload, revision: _revision),
                  _discoverPlaceholder(),
                  WechatMePage(onChanged: _reload),
                ],
              ),
        bottomNavigationBar: _bottomBar(),
      ),
    );
  }

  Widget _bottomBar() {
    const items = <({IconData icon, String label})>[
      (icon: Lucide.MessageCircle, label: '微信'),
      (icon: Lucide.User, label: '通讯录'),
      (icon: Lucide.Compass, label: '发现'),
      (icon: Lucide.Settings, label: '我'),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF7F7F7),
        border: Border(top: BorderSide(color: Color(0xFFDCDCDC), width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 50,
          child: Row(
            children: <Widget>[
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _tab = i),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(
                          items[i].icon,
                          size: 22,
                          color: _tab == i
                              ? WechatColors.green
                              : const Color(0xFF8A8A8A),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          items[i].label,
                          style: TextStyle(
                            fontSize: 10,
                            color: _tab == i
                                ? WechatColors.green
                                : const Color(0xFF8A8A8A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _discoverPlaceholder() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 40),
        child: Text(
          '这里还空着',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: WechatColors.secondaryText,
            height: 1.7,
          ),
        ),
      ),
    );
  }

  Widget _sessionList() {
    final sessions = _sessions();
    if (sessions.isEmpty) {
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
                '还没有聊天',
                style: TextStyle(
                  fontSize: 15,
                  color: WechatColors.secondaryText,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '建个群，或者去通讯录找个人私聊',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: WechatColors.secondaryText,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: sessions.length,
      itemBuilder: (_, index) {
        final session = sessions[index];
        return InkWell(
          onTap: () => _openSession(session),
          onLongPress: () => _showSessionMenu(session),
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
            child: Row(
              children: <Widget>[
                _sessionAvatar(session),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              session.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                color: WechatColors.primaryText,
                              ),
                            ),
                          ),
                          Text(
                            _shortTime(session.sortAt),
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFFB3B3B3),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: <Widget>[
                          Expanded(child: _preview(session)),
                          if (session.unread > 0) ...<Widget>[
                            const SizedBox(width: 8),
                            _unreadBadge(session.unread),
                          ],
                        ],
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

  Widget _preview(_WechatSession session) {
    final last = session.last;
    if (last == null) {
      return const Text(
        '还没人说话',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13, color: WechatColors.secondaryText),
      );
    }
    final who = last.system
        ? ''
        : (last.mine && !last.divine
              ? '我：'
              : (session.isGroup ? '${last.sender}：' : ''));
    return Text(
      '$who${last.text}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 13, color: WechatColors.secondaryText),
    );
  }

  Widget _unreadBadge(int count) {
    final text = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 17),
      height: 17,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: WechatColors.red,
        borderRadius: BorderRadius.circular(9),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10.5,
          color: Colors.white,
          height: 1.1,
        ),
      ),
    );
  }

  Widget _sessionAvatar(_WechatSession session) {
    if (!session.isGroup) {
      final name = session.title;
      return WechatAvatarText(name: name, size: 46, imagePath: _avatars[name]);
    }
    final members = session.memberNames;
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
      return WechatAvatarText(
        name: members.first,
        size: 46,
        imagePath: _avatars[members.first],
      );
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
          for (final name in shown)
            WechatAvatarText(name: name, size: 21, imagePath: _avatars[name]),
          for (var i = shown.length; i < 4; i++)
            Container(color: const Color(0xFFE8E8E8)),
        ],
      ),
    );
  }

  Widget _groupAvatar(WechatGroup group) {
    final members = group.members;
    if (members.isEmpty) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFFDCDCDC),
          borderRadius: BorderRadius.circular(5),
        ),
        alignment: Alignment.center,
        child: const Icon(Lucide.User, size: 20, color: Colors.white),
      );
    }
    return WechatAvatarText(
      name: members.first.name,
      size: 40,
      imagePath: _avatars[members.first.name],
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

  /// 被 @ 的人：下一次一定轮到他说话。发完就清掉。
  String? _pendingSpeaker;

  /// 通讯录（名字 → 联系人），生成时用角色自己绑的模型。
  Map<String, WechatContact> _contactModels = const <String, WechatContact>{};

  /// 头像路径（读的朋友圈那份）。
  Map<String, String> _avatars = const <String, String>{};

  /// 正在重新生成的那条消息 id。非空时界面上把它调淡，也挡住重复点。
  String? _regenId;

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
      _contactModels = <String, WechatContact>{
        for (final contact in _store.contacts()) contact.name: contact,
      };
      _avatars = _store.avatarPaths();
    });
    // 进来就算读过了，会话列表的红点会消掉。
    unawaited(_store.markRead(widget.groupId));
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

  /// @ 一个人：下一次一定是他说话，等的间隔照旧按群聊那套。
  Future<void> _pickMention(WechatGroup group) async {
    if (group.members.isEmpty) {
      _toast('群里还没人，先拉个人进来');
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (sheetCtx) => Theme(
        data: wechatLightTheme(),
        child: SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 16, 18, 8),
                child: Text(
                  '@ 谁（下一句一定是他接）',
                  style: TextStyle(
                    fontSize: 13,
                    color: WechatColors.secondaryText,
                  ),
                ),
              ),
              const Divider(height: 0.5, thickness: 0.5),
              for (final member in group.members)
                ListTile(
                  leading: WechatAvatarText(
                    name: member.name,
                    size: 34,
                    imagePath: _avatars[member.name],
                  ),
                  title: Text(
                    member.name,
                    style: const TextStyle(fontSize: 15, color: wechatMenuInk),
                  ),
                  onTap: () => Navigator.of(sheetCtx).pop(member.name),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || picked == null) return;
    final insert = '@$picked ';
    final selection = _input.selection;
    if (selection.isValid) {
      final start = selection.start;
      final end = selection.end;
      _input.text = _input.text.replaceRange(start, end, insert);
      _input.selection = TextSelection.collapsed(offset: start + insert.length);
    } else {
      _input.text = '${_input.text}$insert';
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
    }
    setState(() => _pendingSpeaker = picked);
    _focus.requestFocus();
  }

  // ---------------- 自动循环 ----------------

  void _restartLoop() {
    _timer?.cancel();
    if (!_autoLoop || _group == null) return;
    final delay = _scheduler.nextDelay(
      _group!,
      settings: _store.wechatSettings(),
    );
    _timer = Timer(delay, () => _tick());
  }

  Future<void> _tick() async {
    if (!mounted || !_autoLoop) return;
    final group = _group;
    if (group == null) return;
    // 被 @ 的人优先：说了叫谁就一定是谁，但等的间隔还是按群聊那套。
    final forced = _pendingSpeaker;
    WechatMember? wanted;
    if (forced != null) {
      for (final member in group.members) {
        if (member.name == forced) {
          wanted = member;
          break;
        }
      }
    }
    final speaker = wanted ?? _scheduler.pickSpeaker(group, _messages);
    if (speaker == null) return;
    final isForced = forced != null && speaker.name == forced;
    final speakerName = speaker.name;
    setState(() => _typingName = speakerName);
    try {
      final generator = WechatGenerator(
        settings: context.read<SettingsProvider>(),
        worldBooks: context.read<WorldBookProvider>(),
        group: group,
        history: wechatRecentContext(_messages),
        contacts: _contactModels,
        worldPrompt: _store.wechatSettings().worldPrompt,
      );
      final text = await generator.generateFor(speaker);
      if (!mounted) return;
      // 他可能连着发几条（模型用换行分的），一条一个气泡。
      final added = <WechatMessage>[];
      for (final part in wechatSplitReply(text)) {
        added.add(
          await _store.appendMessage(group.id, sender: speakerName, text: part),
        );
      }
      if (added.isEmpty || !mounted) return;
      setState(() {
        _typingName = null;
        if (isForced) _pendingSpeaker = null;
        _messages = <WechatMessage>[..._messages, ...added];
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
      // 这个面板是插到根 Overlay 上的，不套主题会跟着 App 的主题走，
      // 夜间模式下字就浅到看不清。这里固定成微信浅色。
      builder: (sheetCtx) => Theme(
        data: wechatLightTheme(),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Lucide.Eye, size: 20, color: wechatMenuInk),
                title: Text(
                  _showDivineMark ? '隐藏天意消息' : '查看天意消息',
                  style: const TextStyle(fontSize: 15, color: wechatMenuInk),
                ),
                onTap: () => Navigator.of(sheetCtx).pop('mark'),
              ),
              ListTile(
                leading: const Icon(
                  Lucide.MessageCircle,
                  size: 20,
                  color: wechatMenuInk,
                ),
                title: const Text(
                  '召唤：叫他私聊我',
                  style: TextStyle(fontSize: 15, color: wechatMenuInk),
                ),
                onTap: () => Navigator.of(sheetCtx).pop('summon'),
              ),
              ListTile(
                leading: const Icon(
                  Lucide.User,
                  size: 20,
                  color: wechatMenuInk,
                ),
                title: const Text(
                  '切换天意：用他的身份说话',
                  style: TextStyle(fontSize: 15, color: wechatMenuInk),
                ),
                onTap: () => Navigator.of(sheetCtx).pop('divine'),
              ),
              if (group.divine.trim().isNotEmpty)
                ListTile(
                  leading: const Icon(
                    Lucide.RotateCcw,
                    size: 20,
                    color: wechatMenuInk,
                  ),
                  title: const Text(
                    '恢复成我自己',
                    style: TextStyle(fontSize: 15, color: wechatMenuInk),
                  ),
                  onTap: () => Navigator.of(sheetCtx).pop('reset'),
                ),
            ],
          ),
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
      return;
    }
    if (action == 'summon') {
      await _summon(group);
    }
  }

  /// 召唤：挑一个人，让他主动私聊我（不是你发他回，是他先开口）。
  Future<void> _summon(WechatGroup group) async {
    if (group.members.isEmpty) {
      _toast('群里还没人，先拉个人进来');
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (sheetCtx) => Theme(
        data: wechatLightTheme(),
        child: SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 16, 18, 8),
                child: Text(
                  '叫谁来找你（他会先开口）',
                  style: TextStyle(
                    fontSize: 13,
                    color: WechatColors.secondaryText,
                  ),
                ),
              ),
              const Divider(height: 0.5, thickness: 0.5),
              for (final member in group.members)
                ListTile(
                  leading: WechatAvatarText(
                    name: member.name,
                    size: 34,
                    imagePath: _avatars[member.name],
                  ),
                  title: Text(
                    member.name,
                    style: const TextStyle(fontSize: 15, color: wechatMenuInk),
                  ),
                  onTap: () => Navigator.of(sheetCtx).pop(member.name),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || picked == null) return;
    // 万一群里有人没进通讯录（老数据），先补进去，不然私聊页找不到人设。
    if (_store.contact(picked) == null) {
      for (final member in group.members) {
        if (member.name == picked) {
          await _store.addContacts(<WechatContact>[
            WechatContact.ofMember(member),
          ]);
          break;
        }
      }
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => WechatDmPage(contactName: picked, summon: true),
      ),
    );
    if (!mounted) return;
    _reload();
  }

  Future<void> _pickDivine(WechatGroup group) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (sheetCtx) => Theme(
        data: wechatLightTheme(),
        child: SafeArea(
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
                  leading: WechatAvatarText(
                    name: member.name,
                    size: 34,
                    imagePath: _avatars[member.name],
                  ),
                  title: Text(
                    member.name,
                    style: const TextStyle(fontSize: 15, color: wechatMenuInk),
                  ),
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
                '${group.name} (${group.memberCount})',
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
                } else if (value == 'summon') {
                  await _summon(group);
                }
              },
              itemBuilder: (_) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'toggle',
                  child: Text(_autoLoop ? '暂停自动回复' : '继续自动回复'),
                ),
                const PopupMenuItem<String>(
                  value: 'summon',
                  child: Text('召唤：叫他私聊我'),
                ),
                const PopupMenuItem<String>(
                  value: 'divine',
                  child: Text('切换天意：用他的身份说话'),
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
    var lastAt = 0;
    for (var i = 0; i < _messages.length; i++) {
      final message = _messages[i];
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
      if (message.system) {
        items.add(_systemRow(message));
        lastSender = null;
        continue;
      }
      final sameAsPrevious = lastSender == message.sender && !_isMine(message);
      items.add(
        _bubbleRow(
          group,
          message,
          showHead: !_isMine(message) && !sameAsPrevious,
        ),
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

  /// 撤回后留的那句灰字。正文已经清空了，这里只有这句。
  Widget _recallRow(WechatMessage message) {
    final who = _isMine(message) ? '你' : message.sender;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Text(
          '$who撤回了一条消息',
          style: const TextStyle(fontSize: 11.5, color: Color(0xFFA6A6A6)),
        ),
      ),
    );
  }

  Widget _bubbleRow(
    WechatGroup group,
    WechatMessage message, {
    required bool showHead,
  }) {
    // 天意发的消息算“他说的”：气泡在左边、头像名字都是他。
    final mine = _isMine(message);
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
      child: _bubbleText(message.text),
    );
    // 气泡上接长按菜单（以前是空手势，纯粹为了吞掉空白菜单）。
    final guardedBubble = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _showMessageMenu(group, message),
      child: Opacity(
        // 正在重新生成的那条淡一点，让人知道在等。
        opacity: _regenId == message.id ? 0.45 : 1,
        child: bubble,
      ),
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
              WechatAvatarText(
                name: message.sender,
                size: 38,
                imagePath: _avatars[message.sender],
              )
            else
              const SizedBox(width: 38),
            const SizedBox(width: 9),
          ],
          Flexible(child: column),
          if (mine) ...<Widget>[
            const SizedBox(width: 9),
            WechatAvatarText(
              name: group.effectivePersona,
              size: 38,
              // 我自己那张头像存在朋友圈的 @me 底下，不走名字查。
              imagePath: _avatars[group.effectivePersona],
            ),
          ],
        ],
      ),
    );
  }

  // ---------------- 单条消息：长按菜单 ----------------

  /// 长按一条消息：自己的能改能撤，别人的能重写能撤。复制按用户说的先不做。
  Future<void> _showMessageMenu(
    WechatGroup group,
    WechatMessage message,
  ) async {
    if (_regenId != null) {
      _toast('等这条重写完再操作');
      return;
    }
    final mine = _isMine(message);
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
                _messageMenuItem(
                  sheetCtx,
                  icon: Lucide.Pencil,
                  label: '编辑',
                  value: 'edit',
                )
              else
                _messageMenuItem(
                  sheetCtx,
                  icon: Lucide.RefreshCw,
                  label: '重新生成',
                  value: 'regen',
                ),
              _messageMenuItem(
                sheetCtx,
                icon: Lucide.History,
                label: '撤回',
                value: 'recall',
              ),
              _messageMenuItem(
                sheetCtx,
                icon: Lucide.Trash2,
                label: '删除',
                value: 'delete',
                danger: true,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'edit':
        await _editMessage(group, message);
      case 'regen':
        await _regenerateMessage(group, message);
      case 'recall':
        await _store.recallMessage(group.id, message.id);
        if (!mounted) return;
        setState(() => _messages = _store.messages(group.id));
      case 'delete':
        final ok = await _confirmMessageDelete();
        if (!mounted || !ok) return;
        await _store.deleteMessage(group.id, message.id);
        if (!mounted) return;
        setState(() => _messages = _store.messages(group.id));
    }
  }

  Widget _messageMenuItem(
    BuildContext sheetCtx, {
    required IconData icon,
    required String label,
    required String value,
    bool danger = false,
  }) {
    final color = danger ? WechatColors.red : wechatMenuInk;
    return ListTile(
      leading: Icon(icon, size: 20, color: color),
      title: Text(label, style: TextStyle(fontSize: 15, color: color)),
      onTap: () => Navigator.of(sheetCtx).pop(value),
    );
  }

  Future<bool> _confirmMessageDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('删掉这条？', style: TextStyle(fontSize: 16)),
        content: const Text('删了就没了，不留记录。只想让它消失但留个痕迹的话，用「撤回」。'),
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
    return ok ?? false;
  }

  Future<void> _editMessage(WechatGroup group, WechatMessage message) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => WechatEditMessageDialog(initial: message.text),
    );
    final next = (text ?? '').trim();
    if (!mounted || next.isEmpty || next == message.text) return;
    await _store.editMessage(group.id, message.id, next);
    if (!mounted) return;
    setState(() => _messages = _store.messages(group.id));
  }

  /// 把这条重写一遍：用**它之前**的记录当上下文，同一个人再说一次。
  Future<void> _regenerateMessage(
    WechatGroup group,
    WechatMessage message,
  ) async {
    if (_regenId != null) return;
    final index = _messages.indexWhere((m) => m.id == message.id);
    if (index < 0) return;
    WechatMember? speaker;
    for (final member in group.members) {
      if (member.name == message.sender) {
        speaker = member;
        break;
      }
    }
    if (speaker == null) {
      _toast('这个人已经不在群里了');
      return;
    }
    final before = _messages.sublist(0, index);
    setState(() => _regenId = message.id);
    try {
      final generator = WechatGenerator(
        settings: context.read<SettingsProvider>(),
        worldBooks: context.read<WorldBookProvider>(),
        group: group,
        history: wechatRecentContext(before),
        contacts: _contactModels,
        worldPrompt: _store.wechatSettings().worldPrompt,
      );
      final text = await generator.generateFor(speaker);
      final parts = wechatSplitReply(text);
      if (!mounted) return;
      if (parts.isEmpty) {
        setState(() => _regenId = null);
        _toast('这次没写出东西，再试一次');
        return;
      }
      // 只替换这一条；他要是想连发，剩下的丢掉，免得跑到列表最末尾去。
      await _store.editMessage(group.id, message.id, parts.first);
      if (!mounted) return;
      setState(() {
        _regenId = null;
        _messages = _store.messages(group.id);
      });
    } on WechatServiceException catch (error) {
      if (!mounted) return;
      setState(() => _regenId = null);
      _toast(_messageFor(error));
    } catch (_) {
      if (!mounted) return;
      setState(() => _regenId = null);
      _toast('这次没重写成功，再点一次');
    }
  }

  /// 这条是不是“我这边发的”。天意替别人说的话不算。
  bool _isMine(WechatMessage message) => message.mine && !message.divine;

  /// 气泡里的字：把 `@某某` 挑出来染成微信那种蓝，别的照旧。
  Widget _bubbleText(String text) {
    const base = TextStyle(
      fontSize: 15.5,
      height: 1.42,
      color: WechatColors.primaryText,
    );
    final pattern = RegExp(r'@[^\s@]+');
    final matches = pattern.allMatches(text);
    if (matches.isEmpty) {
      return Text(text, style: base);
    }
    final spans = <TextSpan>[];
    var last = 0;
    for (final match in matches) {
      if (match.start > last) {
        spans.add(TextSpan(text: text.substring(last, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(0),
          style: const TextStyle(color: WechatColors.link),
        ),
      );
      last = match.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }
    return Text.rich(TextSpan(style: base, children: spans));
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

  /// @ 按钮。图标库里没有 AtSign，就直接写一个 @，比找个近似图标清楚。
  Widget _mentionButton(WechatGroup group) {
    final armed = _pendingSpeaker != null;
    return GestureDetector(
      onTap: () => _pickMention(group),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 3, left: 1, right: 1),
        child: Text(
          '@',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w600,
            color: armed ? WechatColors.green : const Color(0xFF4A4A4A),
          ),
        ),
      ),
    );
  }

  /// 还没做的按钮：点一下老实说没做，不做假功能。
  Widget _placeholderIcon(IconData icon) {
    return GestureDetector(
      onTap: () => _toast('这个功能还没做'),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Icon(icon, size: 25, color: const Color(0xFF4A4A4A)),
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
                  // 占位：语音。真功能以后再加，位置先留着。
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
                          hintText: '说点什么…',
                          hintStyle: TextStyle(
                            fontSize: 15,
                            color: Color(0xFFB2B2B2),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _mentionButton(group),
                  const SizedBox(width: 6),
                  _placeholderIcon(Lucide.Sparkles),
                  const SizedBox(width: 6),
                  _placeholderIcon(Lucide.Plus),
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
