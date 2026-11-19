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
    if (provider == null || model == null) return '跟随全局';
    final config = settings.getProviderConfig(provider);
    final name = config.name.trim().isEmpty ? provider : config.name;
    return '$name · $model';
  }

  // ---------------- 拉人 / 踢人 ----------------

  Future<void> _invite() async {
    final group = _group;
    if (group == null) return;
    final books = context.read<WorldBookProvider>().books;
    final picked = await showModalBottomSheet<List<WechatMember>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (sheetCtx) => _InviteSheet(
        books: books,
        selectedBookIds: group.bookIds,
        existingNames: <String>{for (final m in group.members) m.name},
      ),
    );
    if (picked == null || picked.isEmpty) return;
    final next = await _store.addMembers(group, picked);
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
                for (final member in group.members)
                  _memberRow(member, settings),
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

  Widget _memberRow(WechatMember member, SettingsProvider settings) {
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  member.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    color: WechatColors.primaryText,
                  ),
                ),
                const SizedBox(height: 2),
                GestureDetector(
                  onTap: () => _pickModel(
                    initialProvider: member.providerKey,
                    initialModel: member.modelId,
                    onDone: (provider, model) async {
                      final group = _group;
                      if (group == null) return;
                      await _apply(
                        group.copyWith(
                          members: <WechatMember>[
                            for (final item in group.members)
                              if (item.name == member.name)
                                item.copyWith(
                                  providerKey: provider,
                                  modelId: model,
                                  clearModel: provider == null,
                                )
                              else
                                item,
                          ],
                        ),
                      );
                    },
                  ),
                  child: Text(
                    _modelLabel(member.providerKey, member.modelId, settings),
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: WechatColors.secondaryText,
                    ),
                  ),
                ),
              ],
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
  const _InviteSheet({
    required this.books,
    required this.selectedBookIds,
    required this.existingNames,
  });

  final List<WorldBook> books;
  final List<String> selectedBookIds;
  final Set<String> existingNames;

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

  List<({String name, String entryId, String bookId})> _candidates() {
    final out = <({String name, String entryId, String bookId})>[];
    final seen = <String>{};
    // 选中的世界书优先，没选就全给，反正选的时候能看见来自哪本。
    final books = widget.selectedBookIds.isEmpty
        ? widget.books
        : <WorldBook>[
            for (final book in widget.books)
              if (widget.selectedBookIds.contains(book.id)) book,
          ];
    for (final book in books) {
      for (final entry in book.entries) {
        if (!entry.enabled) continue;
        final name = entry.name.trim();
        if (name.isEmpty) continue;
        if (!seen.add(name)) continue;
        out.add((name: name, entryId: entry.id, bookId: book.id));
      }
    }
    final keyword = _keyword.trim();
    if (keyword.isEmpty) return out;
    return <({String name, String entryId, String bookId})>[
      for (final item in out)
        if (item.name.contains(keyword)) item,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final list = _candidates();
    final height = MediaQuery.sizeOf(context).height * 0.72;
    return SizedBox(
      height: height,
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
                    final picked = <WechatMember>[
                      for (final item in list)
                        if (_picked.contains(item.name))
                          WechatMember(
                            name: item.name,
                            entryId: item.entryId,
                            bookId: item.bookId,
                          ),
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
                  hintText: '搜角色名',
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
                '没找到。先去群设置里选一本世界书，条目里的人才会出现在这儿。',
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
                  final item = list[index];
                  final already = widget.existingNames.contains(item.name);
                  final picked = _picked.contains(item.name);
                  return InkWell(
                    onTap: already
                        ? null
                        : () {
                            setState(() {
                              if (picked) {
                                _picked.remove(item.name);
                              } else {
                                _picked.add(item.name);
                              }
                            });
                          },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: Color(0xFFF0F0F0),
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: Row(
                        children: <Widget>[
                          WechatAvatarText(name: item.name, size: 34),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Text(
                              item.name,
                              style: TextStyle(
                                fontSize: 15,
                                color: already
                                    ? const Color(0xFFB9B9B9)
                                    : WechatColors.primaryText,
                              ),
                            ),
                          ),
                          if (already)
                            const Text(
                              '已在群里',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFFB9B9B9),
                              ),
                            )
                          else if (picked)
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
                                  color: Color(0xFFCFCFCF),
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

/// 两个秒数输入框。单独做成有状态组件，免得外面 setState 一次
/// 就把 controller 换掉、光标跳走。
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
