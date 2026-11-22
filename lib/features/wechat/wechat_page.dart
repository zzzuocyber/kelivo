import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/providers/world_book_provider.dart';
import '../../core/services/chat/chat_service.dart';
import '../../core/services/social_affinity.dart';
import '../../core/services/social_context_builder.dart';
import '../../core/services/social_store.dart';
import '../../icons/lucide_adapter.dart';
import '../moment/moment_store.dart';
import 'wechat_models.dart';
import 'wechat_contacts_page.dart';
import 'wechat_dm_page.dart';
import 'wechat_me_page.dart';
import 'wechat_offline_replay.dart';
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
  late SocialStore _social;
  late MomentStore _momentStore;
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
    final chat = context.read<ChatService>();
    _store = WechatStore(chat);
    _social = SocialStore(chat);
    _momentStore = MomentStore(chat);
    WechatOfflineReplay.instance.addListener(_onOfflineReplay);
    _bootstrap();
  }

  @override
  void dispose() {
    WechatOfflineReplay.instance.removeListener(_onOfflineReplay);
    super.dispose();
  }

  /// 离线补算写完消息后通知一次，刷新会话列表和红点。
  void _onOfflineReplay() {
    if (mounted) _reload();
  }

  /// 先把老数据迁一遍（以前的群成员补进通讯录），再读。
  Future<void> _bootstrap() async {
    await _store.ensureMigrated();
    if (!mounted) return;
    _reload();
    setState(() => _ready = true);
    // 打开微信时补一次「离开期间发生的事」。后台跑，写完通知刷新。
    WechatOfflineReplay.instance.maybeRun(
      store: _store,
      social: _social,
      momentStore: _momentStore,
      settings: context.read<SettingsProvider>(),
      worldBooks: context.read<WorldBookProvider>(),
    );
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
                  Lucide.Eraser,
                  size: 20,
                  color: wechatMenuInk,
                ),
                title: const Text(
                  '清空聊天记录',
                  style: TextStyle(fontSize: 15, color: wechatMenuInk),
                ),
                subtitle: const Text(
                  '只清记录，群和人都在',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: WechatColors.secondaryText,
                  ),
                ),
                onTap: () => Navigator.of(sheetCtx).pop('clear'),
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
    if (!mounted) return;
    if (action == 'clear') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('清空聊天记录？', style: TextStyle(fontSize: 16)),
          content: Text('和「${session.title}」的聊天记录会全部清掉，群和人都留着，删了拿不回来。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('算了'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: const Text(
                '清空',
                style: TextStyle(color: WechatColors.red),
              ),
            ),
          ],
        ),
      );
      if (!mounted || ok != true) return;
      await _store.clearMessages(session.key);
      if (!mounted) return;
      _reload();
      return;
    }
    if (action != 'delete') return;
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
                              onTap: () =>
                                  Navigator.of(sheetCtx)
                                      .pop('open:${group.id}'),
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
    // 建群时先定群主：可以从通讯录里挑一个角色，也可以是我自己。
    // 群主只是名义——拉人/踢人以他的名字发系统消息，权限不变。
    final owner = await _pickOwner();
    if (!mounted || owner == null) return;
    // 新群默认用微信设置里那几本世界书，不选也能马上有人设。
    final group = await _store.createGroup(
      name: '新群聊',
      bookIds: _store.wechatSettings().bookIds,
      owner: owner,
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

  /// 建群时选群主。返回 null = 用户取消建群；返回空串 = 群主是我。
  Future<String?> _pickOwner() async {
    final contacts = _contacts;
    return showModalBottomSheet<String>(
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
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 16, 18, 8),
                child: Text(
                  '谁来当群主（群主只是名义，拉人踢人以他的名字发）',
                  style: TextStyle(
                    fontSize: 13,
                    color: WechatColors.secondaryText,
                  ),
                ),
              ),
              const Divider(height: 0.5, thickness: 0.5),
              ListTile(
                leading: const Icon(
                  Lucide.User,
                  size: 20,
                  color: wechatMenuInk,
                ),
                title: const Text(
                  '我自己',
                  style: TextStyle(fontSize: 15, color: wechatMenuInk),
                ),
                onTap: () => Navigator.of(sheetCtx).pop(''),
              ),
              for (final contact in contacts)
                ListTile(
                  leading: WechatAvatarText(
                    name: contact.name,
                    size: 34,
                    imagePath: _avatars[contact.name],
                  ),
                  title: Text(
                    contact.name,
                    style: const TextStyle(fontSize: 15, color: wechatMenuInk),
                  ),
                  onTap: () => Navigator.of(sheetCtx).pop(contact.name),
                ),
            ],
          ),
        ),
      ),
    );
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
    final who = last.plot
        ? '剧情：'
        : (last.system
              ? ''
              : (last.mine && !last.divine
                    ? '我：'
                    : (session.isGroup ? '${last.sender}：' : '')));
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
  late SocialStore _social;
  late MomentStore _momentStore;
  final WechatScheduler _scheduler = WechatScheduler();
  final Random _burstRandom = Random();
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();

  /// 上一帧的键盘高度：只在键盘「从无到有」的那一刻自动滚到底，
  /// 键盘打字过程中的高度微调不重复滚，免得把正在看的历史消息拽走。
  double _lastKeyboardInset = 0;

  WechatGroup? _group;
  List<WechatMessage> _messages = const <WechatMessage>[];
  Timer? _timer;

  /// 正在想词的人（显示“正在输入”）。
  String? _typingName;

  /// 自动循环关掉了就不主动找人说话，只回你手动发的。
  bool _autoLoop = true;

  /// 长按空白后才把天意消息标出来。
  bool _showDivineMark = false;

  /// 被 @ 的人：发消息时从文本里解析出来，排队等他们接话。发完一个清一个。
  final List<String> _pendingSpeakers = <String>[];

  /// 连续生成失败次数，超过三次才停自动回复，别一次失败就永久哑火。
  int _loopFailures = 0;

  /// @ 按钮刚选完人时的高亮，只管图标颜色，不参与回复调度。
  bool _mentionArmed = false;

  /// 下一条我发的消息要不要带图（输入栏图片开关）。发完自动关掉。
  bool _attachImage = false;

  /// 通讯录（名字 → 联系人），生成时用角色自己绑的模型。
  Map<String, WechatContact> _contactModels = const <String, WechatContact>{};

  /// 头像路径（读的朋友圈那份）。
  Map<String, String> _avatars = const <String, String>{};

  /// 正在重新生成的那条消息 id。非空时界面上把它调淡，也挡住重复点。
  String? _regenId;

  @override
  void initState() {
    super.initState();
    final chat = context.read<ChatService>();
    _store = WechatStore(chat);
    _social = SocialStore(chat);
    _momentStore = MomentStore(chat);
    _group = _store.group(widget.groupId);
    _reload();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _jumpToBottom();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    // 键盘从收起变为弹出：等列表收缩的动画跑完，再自动带到最新一条，
    // 用户不用自己往上拖。
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
      _autoLoop = _social.autoReply(group.id);
    });
    // 进来就算读过了，会话列表的红点会消掉。
    unawaited(_store.markRead(widget.groupId));
    // 离线补算靠这个算「离开了多久」：进群即打点。
    unawaited(_social.markSeen(widget.groupId));
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
    var text = _input.text.trim();
    if (text.isEmpty) return;
    // 打字框快捷夺舍：「角色名>xxx」这条用该成员身份，「我>xxx」用我自己。
    // 只作用这一条，不动 group.divine 持久状态；名字必须精确匹配群成员，防误伤。
    final quick = _parseQuickDivine(text, group);
    if (quick != null) {
      text = quick.body.trim();
      if (text.isEmpty) return;
    }
    // @ 要在文本里认，不能只靠点 @ 按钮时那个临时状态：
    // 计时器抢先跑、退出重进、历史消息重发，都会把临时状态弄丢。
    final mentioned = _mentionsInGroupText(text, group);
    _input.clear();
    final persistentDivine = group.divine.trim();
    // 优先级：我> 用我自己 > 角色名> 用那个人 > 持久夺舍状态。
    final quickName = quick?.name;
    final bool asDivine;
    final String senderName;
    if (quickName == '我') {
      asDivine = false;
      senderName = group.effectivePersona;
    } else if (quickName != null) {
      asDivine = true;
      senderName = quickName;
    } else if (persistentDivine.isNotEmpty) {
      asDivine = true;
      senderName = persistentDivine;
    } else {
      asDivine = false;
      senderName = group.effectivePersona;
    }
    // 夺舍回复会结束冷场：以别人身份开口，就是要打破「先别说话」。
    if (asDivine) unawaited(_social.clearCooldown(socialGroupScope(group.id)));
    final message = await _store.appendMessage(
      group.id,
      sender: senderName,
      text: text,
      mine: true,
      divine: asDivine,
      withImage: _attachImage,
    );
    if (!mounted) return;
    setState(() {
      _attachImage = false;
      _mentionArmed = false;
      // @ 是明确点名，哪怕之前暂停了自动回复也要让这个人接一句。
      if (mentioned.isNotEmpty) _autoLoop = true;
      _messages = <WechatMessage>[..._messages, message];
      for (final name in mentioned) {
        if (!_pendingSpeakers.contains(name)) _pendingSpeakers.add(name);
      }
    });
    // 我在群里 @ 了谁 = 主动找他，给这些人记好感（夺舍发言不算）。
    if (!asDivine) {
      for (final name in mentioned) {
        unawaited(_social.applyAffinityEvent(name, AffinityEvent.meToThem));
      }
    }
    _jumpToBottom();
    _restartLoop();
  }

  /// 解析打字框快捷夺舍语法「角色名>xxx」/「我>xxx」。
  /// 只认当前群成员或「我」，名字必须精确匹配 > 前的整段，防误伤 a>b 这类普通文本。
  /// 返回 (身份名, 去掉前缀后的正文)；没命中返回 null。
  ({String name, String body})? _parseQuickDivine(String text, WechatGroup group) {
    final idx = text.indexOf('>');
    if (idx <= 0) return null;
    final name = text.substring(0, idx).trim();
    if (name.isEmpty) return null;
    if (name != '我' && !group.members.any((m) => m.name.trim() == name)) {
      return null;
    }
    final body = text.substring(idx + 1);
    if (body.trim().isEmpty) return null;
    return (name: name, body: body);
  }

  /// 从群消息文本里挑出 @ 了谁。只认当前群成员，长名字优先，避免短名截断。
  List<String> _mentionsInGroupText(String text, WechatGroup group) {
    final names = <String>[
      for (final member in group.members)
        if (member.name.trim().isNotEmpty) member.name.trim(),
    ]..sort((a, b) => b.length.compareTo(a.length));
    if (names.isEmpty) return const <String>[];
    final pattern = RegExp('@(${names.map(RegExp.escape).join('|')})');
    final out = <String>[];
    for (final match in pattern.allMatches(text)) {
      final name = match.group(1);
      if (name == null || name.isEmpty) continue;
      if (!out.contains(name)) out.add(name);
    }
    return out;
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
    // 只高亮图标：真正的排队交给 _send 从文本里解析，
    // 免得计时器抢先把这个临时状态消费掉。
    setState(() => _mentionArmed = true);
    _focus.requestFocus();
  }

  // ---------------- 自动循环 ----------------

  void _restartLoop({Duration? delay}) {
    _timer?.cancel();
    final group = _group;
    // 自动回复：页面开关 + 单群开关（存在 social store）都要开才转。
    if (!_autoLoop || group == null || !_social.autoReply(group.id)) return;
    // 冷场期内不主动说话，等冷却结束再续上。
    final cooling = _social.topic(socialGroupScope(group.id)).cooldownUntil;
    if (cooling > DateTime.now().millisecondsSinceEpoch) {
      _timer = Timer(
        Duration(milliseconds: cooling - DateTime.now().millisecondsSinceEpoch + 200),
        () => _restartLoop(),
      );
      return;
    }
    _timer = Timer(
      delay ?? _scheduler.nextDelay(group, settings: _store.wechatSettings()),
      () => _tick(),
    );
  }

  Future<void> _tick({bool force = false}) async {
    if (!mounted) return;
    if (!force && !_autoLoop) return;
    final group = _group;
    // 召唤是破例的一次发言，即使这个群关了自动回复也要让他冒这句。
    if (group == null || (!force && !_social.autoReply(group.id))) return;
    // 被 @ 的人优先：说了叫谁就一定是谁，但等的间隔还是按群聊那套。
    final forced = _pendingSpeakers.isEmpty ? null : _pendingSpeakers.first;
    WechatMember? wanted;
    if (forced != null) {
      for (final member in group.members) {
        if (member.name.trim() == forced.trim()) {
          wanted = member;
          break;
        }
      }
      // 名字对不上（人退群了/改名了）就把这个死队列项丢掉，别卡住后面的人。
      if (wanted == null && mounted) _pendingSpeakers.removeAt(0);
    }
    // 一次性天意指令：召唤时强制让被叫的角色这一轮说话。
    final scope = socialGroupScope(group.id);
    final directive = await _social.takeDirective(scope);
    WechatMember? speaker = wanted;
    if (!directive.isNone && directive.kind == 'summon') {
      for (final member in group.members) {
        if (member.name.trim() == directive.who.trim()) {
          speaker = member;
          break;
        }
      }
    }
    speaker ??= _scheduler.pickSpeaker(group, _messages);
    if (speaker == null) {
      _restartLoop();
      return;
    }
    final isForced = wanted != null;
    final speakerName = speaker.name;
    // 等待和生成期间都静默：打字只在消息落地前短暂亮一下。
    try {
      final wechatSettings = _store.wechatSettings();
      final burst = wechatBurstCount(wechatSettings.burstPreset, _burstRandom);
      // 跨场景记忆 + 此刻处境：让角色记得自己在朋友圈/别处聊过的事。
      final memories = <String>[
        ..._momentStore.memoryLinesFor(speakerName),
        ..._store.memoryLinesFor(speakerName, excludeKey: group.id),
      ];
      final whereabouts = _social.whereabouts(speakerName);
      final built = SocialContextBuilder.build(
        name: speakerName,
        scene: 'group',
        memoryLines: memories,
        where: whereabouts.promptLine,
        store: _social,
        // 话题锚开关开了，才把当前话题注入，让角色围着它聊。
        topic: group.autoTopic ? _social.topic(scope).topic : '',
        summaryText: _social.plotSummary,
      );
      final generator = WechatGenerator(
        settings: context.read<SettingsProvider>(),
        worldBooks: context.read<WorldBookProvider>(),
        group: group,
        history: wechatRecentContext(_messages),
        contacts: _contactModels,
        worldPrompt: wechatSettings.worldPrompt,
        groupPrompt: group.groupPrompt,
        socialContext: built.text,
        directiveKind: directive.kind,
        directiveWho: directive.who,
        directiveText: directive.text,
      );
      unawaited(_social.addTokens('group', built.tokens));
      final text = await generator.generateFor(speaker, burstCount: burst);
      if (!mounted) return;
      // 控制剧情走向：整段剧情一条落地，不按连发拆成多个气泡、不挂多个角色名下。
      // 普通发言才按抽到的条数拆，一条一个气泡。
      final isPlot = directive.kind == 'plot' && directive.text.trim().isNotEmpty;
      final parts = isPlot
          ? <String>[text]
          : wechatSplitReply(text, maxParts: burst);
      if (parts.isEmpty) return;
      // 消息要出来了，才亮一下「正在输入」，到点再落气泡。
      setState(() => _typingName = speakerName);
      await Future<void>.delayed(wechatTypingCue);
      if (!mounted) return;
      final added = <WechatMessage>[];
      for (final part in parts) {
        final parsed = wechatStripImageMark(part);
        if (parsed.text.isEmpty) continue;
        added.add(
          await _store.appendMessage(
            group.id,
            // 剧情旁白不挂在某个角色名下；普通发言照旧署名说话人。
            sender: isPlot ? '' : speakerName,
            text: parsed.text,
            withImage: parsed.withImage,
            plot: isPlot,
          ),
        );
      }
      if (added.isEmpty || !mounted) return;
      setState(() {
        _typingName = null;
        _loopFailures = 0;
        if (isForced &&
            _pendingSpeakers.isNotEmpty &&
            _pendingSpeakers.first == forced) {
          _pendingSpeakers.removeAt(0);
        }
        _messages = <WechatMessage>[..._messages, ...added];
      });
      _jumpToBottom();
      _restartLoop();
    } on WechatNoReplyException catch (_) {
      // 天意召唤/冷场：这个角色这会儿不想开口，静默跳过，不算失败。
      if (!mounted) return;
      setState(() => _typingName = null);
      _restartLoop();
    } on WechatServiceException catch (error) {
      if (!mounted) return;
      _handleLoopFailure(_messageFor(error));
    } catch (_) {
      if (!mounted) return;
      _handleLoopFailure('这次没接上，等会儿再试');
    }
  }

  /// 生成失败不再一次就永久停摆：先退避重试，连着三次才停。
  void _handleLoopFailure(String message) {
    final failures = ++_loopFailures;
    setState(() => _typingName = null);
    if (failures >= 3) {
      setState(() => _autoLoop = false);
      _toast('$message，已暂停自动回复');
      return;
    }
    _toast(message);
    _restartLoop(delay: Duration(seconds: 3 * failures));
  }

  String _messageFor(WechatServiceException error) {
    switch (error.code) {
      case 'model_missing':
        return '这个群还没选模型，去设置里挑一个';
      case 'empty':
        return '这次没生成出内容';
      default:
        return '生成失败了';
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
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              _skyTile(
                sheetCtx,
                icon: Lucide.Sparkles,
                label: '召唤角色发言',
                value: 'summon',
              ),
              _skyTile(
                sheetCtx,
                icon: Lucide.SquarePen,
                label: '控制剧情走向',
                value: 'plot',
              ),
              _skyTile(
                sheetCtx,
                icon: Lucide.Shuffle,
                label: '切换话题',
                value: 'switch_topic',
              ),
              _skyTile(
                sheetCtx,
                icon: Lucide.CheckCircle,
                label: '结束话题',
                value: 'end_topic',
              ),
              _skyTile(
                sheetCtx,
                icon: Lucide.Moon,
                label: '冷场一会儿',
                value: 'cooldown',
              ),
              _skyTile(
                sheetCtx,
                icon: Lucide.Sun,
                label: '结束冷场',
                value: 'clear_cooldown',
              ),
              _skyTile(
                sheetCtx,
                icon: Lucide.Eye,
                label: _showDivineMark ? '隐藏天意消息' : '查看天意消息',
                value: 'mark',
              ),
              _skyTile(
                sheetCtx,
                icon: Lucide.User,
                label: '切换天意：用他的身份说话',
                value: 'divine',
              ),
              if (group.divine.trim().isNotEmpty)
                _skyTile(
                  sheetCtx,
                  icon: Lucide.RotateCcw,
                  label: '恢复成我自己',
                  value: 'reset',
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    await _handleSkyAction(group, action);
  }

  Widget _skyTile(
    BuildContext sheetCtx, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return ListTile(
      leading: Icon(icon, size: 20, color: wechatMenuInk),
      title: Text(label, style: const TextStyle(fontSize: 15, color: wechatMenuInk)),
      onTap: () => Navigator.of(sheetCtx).pop(value),
    );
  }

  /// 点空白处 / 三点菜单共用的天意动作分发。
  Future<void> _handleSkyAction(WechatGroup group, String action) async {
    final scope = socialGroupScope(group.id);
    switch (action) {
      case 'mark':
        setState(() => _showDivineMark = !_showDivineMark);
        return;
      case 'reset':
        final next = group.copyWith(divine: '');
        await _store.saveGroup(next);
        if (!mounted) return;
        setState(() => _group = next);
        return;
      case 'divine':
        await _pickDivine(group);
        return;
      case 'summon':
        await _summon(group);
        return;
      case 'plot':
        // 控制剧情走向：手写一段剧情，作为最高指令演这一次。
        // 输入期间把自动循环停一下，免得计时器抢先把剧情指令取走。
        _timer?.cancel();
        final plot = await showDialog<String>(
          context: context,
          builder: (_) => const WechatPlotDialog(),
        );
        if (!mounted || plot == null || plot.trim().isEmpty) {
          _restartLoop();
          return;
        }
        await _social.clearCooldown(scope);
        await _social.setDirective(scope, 'plot', text: plot.trim());
        await _social.addPlotLog(plot.trim(), scene: group.name);
        // 立即演一次，绕过自动回复开关；演完由 _tick 内部按开关决定是否续。
        await _tick(force: true);
        return;
      case 'switch_topic':
      case 'end_topic':
        await _social.setDirective(scope, action);
        _toast(action == 'switch_topic'
            ? '天意已定：下一个人会换个话题'
            : '天意已定：这个话题要收尾了');
        // 话题由下一次发言体现；自动回复开着就催一次。
        if (_social.autoReply(group.id)) _tick();
        return;
      case 'cooldown':
        // 冷场：手动填分钟数，这段时间不主动说话，到点自动恢复。
        _timer?.cancel();
        final minutes = await showDialog<double>(
          context: context,
          builder: (_) => const WechatMinutesDialog(),
        );
        if (!mounted || minutes == null) {
          _restartLoop();
          return;
        }
        final cool = Duration(milliseconds: (minutes * 60 * 1000).round());
        await _social.setCooldown(scope, cool);
        _toast('天意已定：冷场 $minutes 分钟');
        _timer = Timer(cool + const Duration(seconds: 1), () => _restartLoop());
        return;
      case 'clear_cooldown':
        // 结束冷场：立刻清掉冷却，恢复主动发言。
        await _social.clearCooldown(scope);
        _toast('天意已定：冷场结束');
        _timer?.cancel();
        _restartLoop();
        return;
      case 'toggle_auto':
        final next = !_social.autoReply(group.id);
        await _social.setAutoReply(group.id, next);
        if (!mounted) return;
        setState(() => _autoLoop = next);
        if (next) _restartLoop(); else _timer?.cancel();
        _toast(next ? '已开启自动回复' : '已关闭自动回复（只在这个群）');
        return;
    }
  }

  /// 召唤：挑一个人，让他主动私聊我（不是你发他回，是他先开口）。
  /// 天意召唤：挑一个人，让他在群里自己冒出来说一句。
  /// 他不知道是被人叫的（天意叙事），此刻不方便时也会自然地婉拒。
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
                  '天意：选谁立刻冒出来说话',
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
                  subtitle: _social.isAvailable(member.name)
                      ? null
                      : const Text(
                          '这会儿他可能不方便',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                  onTap: () => Navigator.of(sheetCtx).pop(member.name),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || picked == null) return;
    final scope = socialGroupScope(group.id);
    // 召唤会结束冷场：冷场是「先别说话」，现在是天意要他开口。
    await _social.clearCooldown(scope);
    await _social.setDirective(
      scope,
      'summon',
      who: picked,
    );
    _toast('天意已定：$picked 这就开口');
    // 召唤必须即时生效：无条件 force 跑一轮，绕过自动回复开关和页面总开关。
    // 先掐掉在等的计时器，免得这一轮刚生成、定时器又紧接着补一句。
    // 跑完由 _tick 内部按开关决定要不要续上循环，别在这里手动 cancel。
    _timer?.cancel();
    await _tick(force: true);
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
        // 键盘弹起时不压缩整页：消息列表留在原位，只有输入栏浮到键盘上方。
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
                } else if (value == 'clear') {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (dialogCtx) => AlertDialog(
                      backgroundColor: Colors.white,
                      title: const Text(
                        '清空聊天记录？',
                        style: TextStyle(fontSize: 16),
                      ),
                      content: const Text('这个群的记录会全部清掉，群和人都留着，删了拿不回来。'),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.of(dialogCtx).pop(false),
                          child: const Text('算了'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(dialogCtx).pop(true),
                          child: const Text(
                            '清空',
                            style: TextStyle(color: WechatColors.red),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (!mounted || ok != true) return;
                  await _store.clearMessages(group.id);
                  if (!mounted) return;
                  setState(() => _messages = const <WechatMessage>[]);
                  _toast('聊天记录已清空');
                } else if (value == 'toggle') {
                  await _handleSkyAction(group, 'toggle_auto');
                } else if (value == 'divine') {
                  await _pickDivine(group);
                } else if (value == 'reset') {
                  await _handleSkyAction(group, 'reset');
                } else if (value == 'summon' ||
                    value == 'plot' ||
                    value == 'switch_topic' ||
                    value == 'end_topic' ||
                    value == 'cooldown' ||
                    value == 'clear_cooldown') {
                  await _handleSkyAction(group, value);
                }
              },
              itemBuilder: (_) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'toggle',
                  child: Text(_autoLoop ? '暂停自动回复' : '继续自动回复'),
                ),
                const PopupMenuItem<String>(
                  value: 'summon',
                  child: Text('召唤角色发言'),
                ),
                const PopupMenuItem<String>(
                  value: 'plot',
                  child: Text('控制剧情走向'),
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
                  value: 'divine',
                  child: Text('切换天意：用他的身份说话'),
                ),
                if (group.divine.trim().isNotEmpty)
                  const PopupMenuItem<String>(
                    value: 'reset',
                    child: Text('恢复成我自己'),
                  ),
                const PopupMenuItem<String>(
                  value: 'clear',
                  child: Text('清空聊天记录'),
                ),
                const PopupMenuItem<String>(
                  value: 'settings',
                  child: Text('群设置'),
                ),
              ],
            ),
          ],
        ),
        // 消息列表固定铺满，输入栏单独浮在底部并跟随键盘上移，
        // 这样打字时列表不会被键盘顶上去、界面不跳动。
        body: Stack(
          children: <Widget>[
            // 键盘弹出时列表底部跟着收缩，可视区变矮后自动滚到最新一条，
            // 不用用户手动往上拖；顶部标题栏不动（不是把整页顶跑）。
            Positioned.fill(
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    _focus.unfocus();
                    _showBlankMenu();
                  },
                  child: _messageList(group),
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
                child: _inputBar(group),
              ),
            ),
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
      if (message.plot) {
        items.add(_plotRow(message));
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
      // 底部留出输入栏高度：列表不随键盘移动，输入栏浮在上面。
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 72),
      children: items,
    );
  }

  /// 「控制剧情走向」落地的旁白：居中卡片，正文可多行，跟普通气泡区分开。
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _bubbleText(message.text),
          if (message.withImage) ...<Widget>[
            const SizedBox(height: 6),
            WechatEmojiImage(text: message.text, seed: message.id),
          ],
        ],
      ),
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
      // 重新生成只替换这一条，所以明确要一条，别让它连发。
      final text = await generator.generateFor(speaker, burstCount: 1);
      final parts = wechatSplitReply(text, maxParts: 1);
      if (!mounted) return;
      if (parts.isEmpty) {
        setState(() => _regenId = null);
        _toast('这次没写出东西，再试一次');
        return;
      }
      // 只替换这一条；他要是想连发，剩下的丢掉，免得跑到列表最末尾去。
      final parsed = wechatStripImageMark(parts.first);
      if (parsed.text.isEmpty) {
        setState(() => _regenId = null);
        _toast('这次没写出东西，再试一次');
        return;
      }
      await _store.editMessage(
        group.id,
        message.id,
        parsed.text,
        withImage: parsed.withImage,
      );
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
    final armed =
        _mentionArmed ||
        _pendingSpeakers.isNotEmpty ||
        _input.text.contains('@');
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
                  _imageButton(),
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
