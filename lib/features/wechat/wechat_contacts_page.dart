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
  const WechatContactsPage({super.key, this.onChanged});

  /// 加人 / 删人之后通知外层刷新会话列表。
  final VoidCallback? onChanged;

  @override
  State<WechatContactsPage> createState() => _WechatContactsPageState();
}

class _WechatContactsPageState extends State<WechatContactsPage> {
  late WechatStore _store;
  List<WechatContact> _contacts = const <WechatContact>[];
  WechatSettings _settings = const WechatSettings();
  Map<String, String> _avatars = const <String, String>{};

  @override
  void initState() {
    super.initState();
    _store = WechatStore(context.read<ChatService>());
    _reload();
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
    final provider = context.read<WorldBookProvider>();
    final books = <WorldBook>[
      for (final id in _settings.bookIds)
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
                  color: WechatColors.secondaryText,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Lucide.Trash2, size: 19),
              title: const Text('从通讯录删除'),
              subtitle: const Text('群里的他也会一起移出'),
              onTap: () => Navigator.of(sheetCtx).pop('delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action != 'delete') return;
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
    String? lastLetter;
    for (final contact in _contacts) {
      final letter = pinyinInitialOf(contact.name);
      if (letter != lastLetter) {
        rows.add(_letterRow(letter));
        lastLetter = letter;
      }
      rows.add(_contactRow(contact));
    }
    rows.add(_addRow());
    return ListView(padding: EdgeInsets.zero, children: rows);
  }

  /// 首字母那行小灰条（A、B、C…），跟通讯录 App 一个意思。
  Widget _letterRow(String letter) {
    return Container(
      color: const Color(0xFFF2F2F2),
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
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
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
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
