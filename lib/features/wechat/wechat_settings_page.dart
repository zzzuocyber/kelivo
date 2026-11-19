import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/world_book.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/world_book_provider.dart';
import '../../core/services/chat/chat_service.dart';
import '../../icons/lucide_adapter.dart';
import '../model/widgets/model_select_sheet.dart';
import 'wechat_models.dart';
import 'wechat_store.dart';
import 'wechat_ui.dart';

/// 群设置：改名、拉人、踢人、选世界书、调间隔、绑模型、删群。
/// 返回 true 表示动过东西（列表页拿它决定要不要直接进群）。
class WechatSettingsPage extends StatefulWidget {
  const WechatSettingsPage({super.key, required this.groupId});

  final String groupId;

  @override
  State<WechatSettingsPage> createState() => _WechatSettingsPageState();
}

class _WechatSettingsPageState extends State<WechatSettingsPage> {
  late WechatStore _store;
  WechatGroup? _group;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _store = WechatStore(context.read<ChatService>());
    _group = _store.group(widget.groupId);
  }

  Future<void> _apply(WechatGroup next) async {
    await _store.saveGroup(next);
    if (!mounted) return;
    setState(() {
      _group = next;
      _changed = true;
    });
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

  // ---------------- 改文字 ----------------

  Future<void> _editText({
    required String title,
    required String initial,
    required String hint,
    required Future<void> Function(String value) onDone,
  }) async {
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (sheetCtx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(title, style: const TextStyle(fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          style: const TextStyle(fontSize: 15),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(sheetCtx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(sheetCtx).pop(controller.text.trim()),
            child: const Text('好'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    await onDone(value);
  }

  // ---------------- 模型 ----------------

  Future<void> _pickModel({
    String? initialProvider,
    String? initialModel,
    required Future<void> Function(String? provider, String? model) onDone,
  }) async {
    final picked = await showModelSelector(
      context,
      initialProviderKey: initialProvider,
      initialModelId: initialModel,
    );
    if (picked == null) return;
    await onDone(picked.providerKey, picked.modelId);
  }

  String _modelLabel(
    String? provider,
    String? model,
    SettingsProvider settings,
  ) {
    if (provider == null || model == null) return '跟群默认';
    final config = settings.getProviderConfig(provider);
    final name = config.name.trim().isEmpty ? provider : config.name;
    return '$name · $model';
  }

  // ---------------- 拉人 / 踢人 ----------------

  Future<void> _invite() async {
    final group = _group;
    if (group == null) return;
    // 拉人只从通讯录里挑：世界书里有人但没加进通讯录的，这里看不到。
    final contacts = _store.contacts();
    if (contacts.isEmpty) {
      _toast('通讯录里还没人，先去通讯录取加几个');
      return;
    }
    final existing = <String>{for (final m in group.members) m.name};
    final pool = <WechatContact>[
      for (final contact in contacts)
        if (!existing.contains(contact.name)) contact,
    ];
    if (pool.isEmpty) {
      _toast('通讯录里的人都已经在群里了');
      return;
    }
    final picked = await showModalBottomSheet<List<WechatContact>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (sheetCtx) =>
          _InviteSheet(contacts: pool, avatars: _store.avatarPaths()),
    );
    if (picked == null || picked.isEmpty) return;
    final next = await _store.addMembers(group, <WechatMember>[
      for (final contact in picked) contact.toMember(),
    ]);
    if (!mounted) return;
    setState(() {
      _group = next;
      _changed = true;
    });
  }

  Future<void> _remove(String name) async {
    final group = _group;
    if (group == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (sheetCtx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('移出群聊', style: TextStyle(fontSize: 16)),
        content: Text('把「$name」移出这个群？群里会留一条记录。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(sheetCtx).pop(false),
            child: const Text('算了'),
          ),
          TextButton(
            onPressed: () => Navigator.of(sheetCtx).pop(true),
            child: const Text('移出', style: TextStyle(color: WechatColors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final next = await _store.removeMember(group, name);
    if (!mounted) return;
    setState(() {
      _group = next;
      _changed = true;
    });
  }

  Future<void> _delete() async {
    final group = _group;
    if (group == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (sheetCtx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('删除群聊', style: TextStyle(fontSize: 16)),
        content: Text('「${group.name}」和里面的聊天记录都会删掉，删了拿不回来。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(sheetCtx).pop(false),
            child: const Text('算了'),
          ),
          TextButton(
            onPressed: () => Navigator.of(sheetCtx).pop(true),
            child: const Text('删除', style: TextStyle(color: WechatColors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _store.deleteGroup(group.id);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  // ---------------- 界面 ----------------

  @override
  Widget build(BuildContext context) {
    final group = _group;
    if (group == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    final settings = context.watch<SettingsProvider>();
    return Theme(
      data: wechatLightTheme(),
      child: PopScope(
        canPop: true,
        child: Scaffold(
          backgroundColor: const Color(0xFFEDEDED),
          appBar: AppBar(
            backgroundColor: const Color(0xFFEDEDED),
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            centerTitle: true,
            shape: const Border(
              bottom: BorderSide(color: Color(0xFFD8D8D8), width: 0.5),
            ),
            leading: IconButton(
              onPressed: () => Navigator.of(context).pop(_changed),
              icon: const Icon(
                Lucide.ChevronLeft,
                size: 22,
                color: Colors.black,
              ),
            ),
            title: const Text(
              '群设置',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 30),
            children: <Widget>[
              const SizedBox(height: 8),
              _section(<Widget>[
                _row(
                  title: '群名称',
                  value: group.name,
                  onTap: () => _editText(
                    title: '群名称',
                    initial: group.name,
                    hint: '起个名字',
                    onDone: (value) async {
                      if (value.isEmpty) return;
                      await _apply(group.copyWith(name: value));
                    },
                  ),
                ),
                _row(
                  title: '我的名字',
                  value: group.effectivePersona,
                  onTap: () => _editText(
                    title: '我在群里的名字',
                    initial: group.persona,
                    hint: '比如你的马甲名',
                    onDone: (value) async {
                      await _apply(group.copyWith(persona: value));
                    },
                  ),
                ),
              ]),

              _header('成员（${group.members.length}）'),
              _section(<Widget>[
                for (final member in group.members) _memberRow(member),
                _addRow(),
              ]),

              _header('世界书（可以多本）'),
              _bookSection(group),

              _header('发言间隔'),
              _intervalSection(group),

              _header('默认模型'),
              _section(<Widget>[
                _row(
                  title: '群默认',
                  value: _modelLabel(
                    group.providerKey,
                    group.modelId,
                    settings,
                  ),
                  onTap: () => _pickModel(
                    initialProvider: group.providerKey,
                    initialModel: group.modelId,
                    onDone: (provider, model) async {
                      await _apply(
                        group.copyWith(providerKey: provider, modelId: model),
                      );
                    },
                  ),
                ),
              ]),

              const SizedBox(height: 24),
              _section(<Widget>[
                InkWell(
                  onTap: _delete,
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    alignment: Alignment.center,
                    child: const Text(
                      '删除群聊',
                      style: TextStyle(fontSize: 16, color: WechatColors.red),
                    ),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12.5,
          color: WechatColors.secondaryText,
        ),
      ),
    );
  }

  Widget _section(List<Widget> children) {
    return Container(
      color: Colors.white,
      child: Column(children: children),
    );
  }

  Widget _row({
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0xFFEEEEEE), width: 0.5),
          ),
        ),
        child: Row(
          children: <Widget>[
            Text(
              title,
              style: const TextStyle(
                fontSize: 15.5,
                color: WechatColors.primaryText,
              ),
            ),
            const Spacer(),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 14,
                  color: WechatColors.secondaryText,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Lucide.ChevronRight, size: 15, color: Color(0xFFC8C8C8)),
          ],
        ),
      ),
    );
  }

  Widget _memberRow(WechatMember member) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFEEEEEE), width: 0.5),
        ),
      ),
      child: Row(
        children: <Widget>[
          WechatAvatarText(name: member.name, size: 36),
          const SizedBox(width: 11),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                member.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  color: WechatColors.primaryText,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: () => _remove(member.name),
            icon: const Icon(Lucide.X, size: 17, color: Color(0xFFB9B9B9)),
          ),
        ],
      ),
    );
  }

  Widget _addRow() {
    return InkWell(
      onTap: _invite,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: <Widget>[
            const Icon(Lucide.Plus, size: 18, color: WechatColors.green),
            const SizedBox(width: 8),
            const Text(
              '拉人进群',
              style: TextStyle(fontSize: 15, color: WechatColors.green),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bookSection(WechatGroup group) {
    final books = context.watch<WorldBookProvider>().books;
    if (books.isEmpty) {
      return _section(<Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          alignment: Alignment.centerLeft,
          child: const Text(
            '还没有世界书，先去建一本',
            style: TextStyle(fontSize: 13, color: WechatColors.secondaryText),
          ),
        ),
      ]);
    }
    return _section(<Widget>[for (final book in books) _bookRow(group, book)]);
  }

  Widget _bookRow(WechatGroup group, WorldBook book) {
    final checked = group.bookIds.contains(book.id);
    return InkWell(
      onTap: () async {
        final next = <String>[...group.bookIds];
        if (checked) {
          next.remove(book.id);
        } else {
          next.add(book.id);
        }
        await _apply(group.copyWith(bookIds: next));
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0xFFEEEEEE), width: 0.5),
          ),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    book.name,
                    style: const TextStyle(
                      fontSize: 15,
                      color: WechatColors.primaryText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${book.entries.length} 个条目',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: WechatColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            if (checked)
              const Icon(Lucide.Check, size: 21, color: WechatColors.green)
            else
              Container(
                width: 19,
                height: 19,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Color(0xFFCFCFCF), width: 1.4),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _intervalSection(WechatGroup group) {
    return Column(
      children: <Widget>[
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final preset in WechatIntervalPreset.values)
                _presetChip(group, preset),
            ],
          ),
        ),
        if (group.intervalPreset == WechatIntervalPreset.custom)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Row(
              children: <Widget>[
                _WechatNumberField(
                  label: '最短',
                  value: group.customMinSeconds,
                  onDone: (value) async {
                    await _apply(
                      group.copyWith(
                        customMinSeconds: value,
                        customMaxSeconds: value > group.customMaxSeconds
                            ? value
                            : group.customMaxSeconds,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 14),
                _WechatNumberField(
                  label: '最长',
                  value: group.customMaxSeconds,
                  onDone: (value) async {
                    await _apply(
                      group.copyWith(
                        customMaxSeconds: value < group.customMinSeconds
                            ? group.customMinSeconds
                            : value,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 10),
                const Text(
                  '秒',
                  style: TextStyle(
                    fontSize: 13,
                    color: WechatColors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _presetChip(WechatGroup group, WechatIntervalPreset preset) {
    final active = group.intervalPreset == preset;
    return GestureDetector(
      onTap: () async {
        await _apply(group.copyWith(intervalPreset: preset));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFE7F8EE) : const Color(0xFFF2F2F2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? WechatColors.green : Colors.transparent,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              preset.label,
              style: TextStyle(
                fontSize: 13,
                color: active ? WechatColors.green : WechatColors.primaryText,
                fontWeight: active ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              preset.hint,
              style: const TextStyle(
                fontSize: 9.5,
                color: WechatColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 拉人面板
// ============================================================

class _InviteSheet extends StatefulWidget {
  const _InviteSheet({required this.contacts, required this.avatars});

  /// 通讯录里还没进这个群的人。
  final List<WechatContact> contacts;
  final Map<String, String> avatars;

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  final TextEditingController _search = TextEditingController();
  final Set<String> _picked = <String>{};
  String _keyword = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<WechatContact> _candidates() {
    final keyword = _keyword.trim();
    if (keyword.isEmpty) return widget.contacts;
    return <WechatContact>[
      for (final contact in widget.contacts)
        if (contact.name.contains(keyword)) contact,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final list = _candidates();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.72,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
            child: Row(
              children: <Widget>[
                const Text(
                  '拉人进群',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: WechatColors.primaryText,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    final picked = <WechatContact>[
                      for (final contact in list)
                        if (_picked.contains(contact.name)) contact,
                    ];
                    Navigator.of(context).pop(picked);
                  },
                  child: Text('加入（${_picked.length}）'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F2F2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: TextField(
                controller: _search,
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: '搜名字',
                  hintStyle: TextStyle(fontSize: 14, color: Color(0xFFB2B2B2)),
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
                onChanged: (value) => setState(() => _keyword = value),
              ),
            ),
          ),
          const SizedBox(height: 6),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Text(
                '没找到。人得先去通讯录里加进来，这里才有。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: WechatColors.secondaryText,
                  height: 1.7,
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, index) {
                  final contact = list[index];
                  final picked = _picked.contains(contact.name);
                  return InkWell(
                    onTap: () => setState(() {
                      if (!_picked.remove(contact.name)) {
                        _picked.add(contact.name);
                      }
                    }),
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Row(
                        children: <Widget>[
                          WechatAvatarText(
                            name: contact.name,
                            size: 36,
                            imagePath: widget.avatars[contact.name],
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Text(
                              contact.name,
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
    );
  }
}

class _WechatNumberField extends StatefulWidget {
  const _WechatNumberField({
    required this.label,
    required this.value,
    required this.onDone,
  });

  final String label;
  final int value;
  final Future<void> Function(int value) onDone;

  @override
  State<_WechatNumberField> createState() => _WechatNumberFieldState();
}

class _WechatNumberFieldState extends State<_WechatNumberField> {
  late final TextEditingController _controller = TextEditingController(
    text: '${widget.value}',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: <Widget>[
          Text(
            widget.label,
            style: const TextStyle(
              fontSize: 13,
              color: WechatColors.secondaryText,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onSubmitted: (text) {
                  final parsed = int.tryParse(text.trim());
                  if (parsed == null || parsed < 0) return;
                  widget.onDone(parsed > 3600 ? 3600 : parsed);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
