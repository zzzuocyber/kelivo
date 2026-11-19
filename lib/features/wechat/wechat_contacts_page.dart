import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/world_book.dart';
import '../../core/providers/world_book_provider.dart';
import '../../core/services/chat/chat_service.dart';
import '../../core/utils/pinyin_sort.dart';
import '../../icons/lucide_adapter.dart';
import 'wechat_dm_page.dart';
import 'wechat_models.dart';
import 'wechat_store.dart';
import 'wechat_ui.dart';

/// 通讯录：**手动添加**的联系人。人设还是去世界书取，但人得自己加。
class WechatContactsPage extends StatefulWidget {
  const WechatContactsPage({super.key, this.onChanged, this.revision = 0});

  /// 加人 / 删人之后通知外层刷新会话列表。
  final VoidCallback? onChanged;

  /// 外层每次刷新就 +1，子页看到变化自己也重读一遍
  /// （IndexedStack 里的子页 initState 只跑一次，不然设置改了这里看不见）。
  final int revision;

  @override
  State<WechatContactsPage> createState() => _WechatContactsPageState();
}

class _WechatContactsPageState extends State<WechatContactsPage> {
  late WechatStore _store;
  List<WechatContact> _contacts = const <WechatContact>[];
  WechatSettings _settings = const WechatSettings();
  Map<String, String> _avatars = const <String, String>{};

  final ScrollController _scroll = ScrollController();

  /// 两个字高固定，右侧字母条才能算准该滚到哪。
  static const double _letterRowHeight = 24;
  static const double _contactRowHeight = 64;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _store = WechatStore(context.read<ChatService>());
    _reload();
  }

  @override
  void didUpdateWidget(covariant WechatContactsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) _reload();
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      // 按首字母排，加了人也不会跳来跳去。
      _contacts = sortedByPinyin(_store.contacts(), (c) => c.name);
      _settings = _store.wechatSettings();
      _avatars = _store.avatarPaths();
    });
  }

  // ---------------- 加人 ----------------

  Future<void> _add() async {
    // 这里必须**现读**：世界观页可能刚改过世界书，而这一页是
    // IndexedStack 里的子页，initState 只跑一次，缓存的值早就过期了。
    final settings = _store.wechatSettings();
    _settings = settings;
    final provider = context.read<WorldBookProvider>();
    final books = <WorldBook>[
      for (final id in settings.bookIds)
        if (provider.getById(id) != null) provider.getById(id)!,
    ];
    if (books.isEmpty) {
      _toast('还没选世界书。先去「我 → 设置 → 世界观」选几本');
      return;
    }
    final existing = <String>{for (final c in _contacts) c.name};
    // 名字 → 条目。同名只留第一个（先选的书的优先）。
    final candidates = <String, WechatContact>{};
    for (final book in books) {
      for (final entry in book.entries) {
        final name = entry.name.trim();
        if (name.isEmpty) continue;
        if (existing.contains(name)) continue;
        if (candidates.containsKey(name)) continue;
        candidates[name] = WechatContact(
          name: name,
          entryId: entry.id,
          bookId: book.id,
        );
      }
    }
    if (candidates.isEmpty) {
      _toast('选中的世界书里没有新人可以加');
      return;
    }
    final picked = await showModalBottomSheet<List<WechatContact>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => _AddContactsSheet(candidates: candidates),
    );
    if (!mounted || picked == null || picked.isEmpty) return;
    await _store.addContacts(picked);
    if (!mounted) return;
    _reload();
    widget.onChanged?.call();
  }

  Future<void> _openDm(WechatContact contact) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => WechatDmPage(contactName: contact.name),
      ),
    );
    _reload();
  }

  Future<void> _showContactMenu(WechatContact contact) async {
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
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
              child: Text(
                contact.name,
                style: const TextStyle(
                  fontSize: 13,
                  color: WechatColors.primaryText,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(
                Lucide.MessageCircle,
                size: 19,
                color: WechatColors.primaryText,
              ),
              title: const Text(
                '召唤他来找我',
                style: TextStyle(color: WechatColors.primaryText),
              ),
              subtitle: const Text('进私聊，他先开口'),
              onTap: () => Navigator.of(sheetCtx).pop('summon'),
            ),
            ListTile(
              leading: const Icon(
                Lucide.Trash2,
                size: 19,
                color: WechatColors.primaryText,
              ),
              title: const Text(
                '从通讯录删除',
                style: TextStyle(color: WechatColors.primaryText),
              ),
              subtitle: const Text('群里的他也会一起移出'),
              onTap: () => Navigator.of(sheetCtx).pop('delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'summon') {
      // 召唤：进私聊，让他先开口（跟群里长按空白那个召唤一套逻辑）。
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => WechatDmPage(contactName: contact.name, summon: true),
        ),
      );
      if (!mounted) return;
      _reload();
      widget.onChanged?.call();
      return;
    }
    if (action != 'delete') return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('从通讯录删除？'),
        content: Text('「${contact.name}」会从通讯录消失，所在群里也会被移出并留一条记录。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('算了'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;
    await _store.removeContact(contact.name);
    if (!mounted) return;
    _reload();
    widget.onChanged?.call();
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(child: _contacts.isEmpty ? _emptyState() : _list()),
      ],
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
              Lucide.User,
              size: 42,
              color: WechatColors.secondaryText.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 14),
            const Text(
              '通讯录还是空的',
              style: TextStyle(fontSize: 15, color: WechatColors.secondaryText),
            ),
            const SizedBox(height: 6),
            const Text(
              '人不会自动进来，得你自己加。\n加进来才能私聊、才能拉进群。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: WechatColors.secondaryText,
                height: 1.7,
              ),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _add,
              style: FilledButton.styleFrom(
                backgroundColor: WechatColors.green,
                padding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 11,
                ),
              ),
              child: const Text('添加联系人'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list() {
    final rows = <Widget>[];
    final letters = <String>[];
    // 每个字母那行在整张列表里的纵向位置，点字母条要滚到这里。
    final offsets = <String, double>{};
    var y = 0.0;
    String? lastLetter;
    for (final contact in _contacts) {
      final letter = pinyinInitialOf(contact.name);
      if (letter != lastLetter) {
        letters.add(letter);
        offsets[letter] = y;
        y += _letterRowHeight;
        rows.add(_letterRow(letter));
        lastLetter = letter;
      }
      y += _contactRowHeight;
      rows.add(_contactRow(contact));
    }
    rows.add(_addRow());
    return Stack(
      children: <Widget>[
        // 右边留出一条给字母条，不然会盖住字。
        ListView(
          controller: _scroll,
          padding: const EdgeInsets.only(right: 22),
          children: rows,
        ),
        if (letters.length > 2)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: _indexBar(letters, offsets),
          ),
      ],
    );
  }

  /// 右侧那一竖排 A、B、C……，点一下滚到对应分组。
  Widget _indexBar(List<String> letters, Map<String, double> offsets) {
    return Center(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0x0D000000),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final letter in letters)
                GestureDetector(
                  onTap: () => _jumpTo(letter, offsets),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 1.2,
                    ),
                    child: Text(
                      letter,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: WechatColors.secondaryText,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _jumpTo(String letter, Map<String, double> offsets) {
    if (!_scroll.hasClients) return;
    final target = offsets[letter];
    if (target == null) return;
    final max = _scroll.position.maxScrollExtent;
    _scroll.animateTo(
      // clamp 返回的是 num，animateTo 要 double，这里必须转一下。
      target.clamp(0.0, max).toDouble(),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  /// 首字母那行小灰条（A、B、C…），高度固定，右侧字母条靠它算位置。
  Widget _letterRow(String letter) {
    return Container(
      height: _letterRowHeight,
      color: const Color(0xFFF2F2F2),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      child: Text(
        letter,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: WechatColors.secondaryText,
        ),
      ),
    );
  }

  Widget _contactRow(WechatContact contact) {
    return InkWell(
      onTap: () => _openDm(contact),
      onLongPress: () => _showContactMenu(contact),
      child: Container(
        height: _contactRowHeight,
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: <Widget>[
            WechatAvatarText(
              name: contact.name,
              size: 44,
              imagePath: _avatars[contact.name],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                contact.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  color: WechatColors.primaryText,
                ),
              ),
            ),
            if (contact.modelId != null)
              const Icon(Lucide.Bot, size: 15, color: Color(0xFF07C160)),
          ],
        ),
      ),
    );
  }

  Widget _addRow() {
    return InkWell(
      onTap: _add,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFF2F2F2),
                borderRadius: BorderRadius.circular(5),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Lucide.Plus,
                size: 22,
                color: WechatColors.secondaryText,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              '添加联系人',
              style: TextStyle(fontSize: 16, color: WechatColors.primaryText),
            ),
          ],
        ),
      ),
    );
  }
}

/// 选人面板：勾一个或多个。
class _AddContactsSheet extends StatefulWidget {
  const _AddContactsSheet({required this.candidates});

  final Map<String, WechatContact> candidates;

  @override
  State<_AddContactsSheet> createState() => _AddContactsSheetState();
}

class _AddContactsSheetState extends State<_AddContactsSheet> {
  final Set<String> _picked = <String>{};
  String _keyword = '';

  @override
  Widget build(BuildContext context) {
    final names = widget.candidates.keys
        .where((name) => _keyword.isEmpty || name.contains(_keyword))
        .toList(growable: false);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.66,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '添加联系人（已选 ${_picked.length}）',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: WechatColors.primaryText,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(<WechatContact>[
                      for (final name in _picked)
                        if (widget.candidates[name] != null)
                          widget.candidates[name]!,
                    ]),
                    child: const Text('添加'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F2F2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: TextField(
                  onChanged: (value) => setState(() => _keyword = value.trim()),
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 9),
                    hintText: '搜名字',
                    hintStyle: TextStyle(fontSize: 14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: names.isEmpty
                  ? const Center(
                      child: Text(
                        '没有匹配的名字',
                        style: TextStyle(
                          fontSize: 13,
                          color: WechatColors.secondaryText,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: names.length,
                      itemBuilder: (_, index) {
                        final name = names[index];
                        final picked = _picked.contains(name);
                        return InkWell(
                          onTap: () => setState(() {
                            if (!_picked.remove(name)) _picked.add(name);
                          }),
                          child: Container(
                            color: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    name,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      color: WechatColors.primaryText,
                                    ),
                                  ),
                                ),
                                if (picked)
                                  const Icon(
                                    Lucide.Check,
                                    size: 20,
                                    color: WechatColors.green,
                                  )
                                else
                                  Container(
                                    width: 18,
                                    height: 18,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFFCFCFCF),
                                        width: 1.4,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
