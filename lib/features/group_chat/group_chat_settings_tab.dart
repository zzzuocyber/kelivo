part of 'group_chat_tab.dart';

/// 助手设置页里的「群聊」tab。独立的 part，不碰原有 9 个 tab。
class _GroupChatTab extends StatefulWidget {
  const _GroupChatTab({required this.assistantId});
  final String assistantId;

  @override
  State<_GroupChatTab> createState() => _GroupChatTabState();
}

class _GroupChatTabState extends State<_GroupChatTab> {
  final TextEditingController _worldCtrl = TextEditingController();
  final TextEditingController _groupCtrl = TextEditingController();

  Assistant get _assistant =>
      context.read<AssistantProvider>().getById(widget.assistantId)!;
  GroupChatConfig get _config => _assistant.groupChat;

  @override
  void initState() {
    super.initState();
    _worldCtrl.text = _config.worldPrompt;
    _groupCtrl.text = _config.groupPrompt;
  }

  @override
  void dispose() {
    _worldCtrl.dispose();
    _groupCtrl.dispose();
    super.dispose();
  }

  Future<void> _save(GroupChatConfig next) async {
    await context.read<AssistantProvider>().updateAssistant(
      _assistant.copyWith(groupChat: next),
    );
  }

  Future<void> _pickImage(GroupChatMember member) async {
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (x == null) return;
    final next = _config.copyWith(
      members: [
        for (final m in _config.members)
          if (m.name == member.name) m.copyWith(avatar: x.path) else m,
      ],
    );
    await _save(next);
  }

  Future<void> _pickModel(GroupChatMember member) async {
    final sel = await showModelSelector(
      context,
      allowInherit: true,
      inheritLabel: '跟随助手',
      initialProviderKey: member.providerKey,
      initialModelId: member.modelId,
    );
    if (sel == null) return;
    final next = _config.copyWith(
      members: [
        for (final m in _config.members)
          if (m.name == member.name)
            sel.providerKey.isEmpty
                ? m.copyWith(clearModel: true)
                : m.copyWith(
                    providerKey: sel.providerKey,
                    modelId: sel.modelId,
                  )
          else m,
      ],
    );
    await _save(next);
  }

  Future<void> _pickBooks() async {
    final picked = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _BookPickSheet(selected: _config.bookIds),
    );
    if (picked == null) return;
    await _save(_config.copyWith(bookIds: picked));
  }

  Future<void> _pickMembers() async {
    final picked = await showModalBottomSheet<List<GroupChatMember>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _MemberPickSheet(
        bookIds: _config.bookIds,
        current: _config.members,
      ),
    );
    if (picked == null) return;
    // 保留还在群里的人已有的头像/模型设置。
    final old = {for (final m in _config.members) m.name: m};
    final merged = picked.map((m) {
      final prev = old[m.name];
      if (prev == null) return m;
      return m.copyWith(
        avatar: prev.avatar,
        providerKey: prev.providerKey,
        modelId: prev.modelId,
      );
    }).toList();
    await _save(_config.copyWith(members: merged));
  }

  Widget _section(String title, Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final config = _config;
    final enabled = config.enabled;

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _section(
          '群聊模式',
          SwitchListTile(
            value: enabled,
            onChanged: (v) => _save(config.copyWith(enabled: v)),
            title: const Text('开启群聊'),
            subtitle: const Text(
              '开启后，这个助手可以拉一群世界书角色一起说话。关闭即恢复原来的单聊。',
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (enabled) ...[
          _section(
            '说话顺序',
            SegmentedButton<GroupChatMode>(
              segments: const [
                ButtonSegment(
                  value: GroupChatMode.round,
                  label: Text('轮流圆桌'),
                  icon: Icon(Icons.rotate_right),
                ),
                ButtonSegment(
                  value: GroupChatMode.random,
                  label: Text('随机抢话'),
                  icon: Icon(Icons.shuffle),
                ),
              ],
              selected: <GroupChatMode>{config.mode},
              onSelectionChanged: (set) =>
                  _save(config.copyWith(mode: set.first)),
            ),
          ),
          _section(
            '用哪些世界书',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    for (final id in config.bookIds)
                      Chip(
                        label: Text(
                          context
                                  .read<WorldBookProvider>()
                                  .getById(id)
                                  ?.name ??
                              id,
                        ),
                      ),
                    ActionChip(
                      label: const Text('选择世界书'),
                      onPressed: _pickBooks,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '群成员从这些书里的条目来选；世界观、剧情前情等条目当背景。',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          _section(
            '群成员（${config.members.length}）',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.person_add, size: 18),
                      label: const Text('选择角色'),
                      onPressed: config.bookIds.isEmpty
                          ? null
                          : _pickMembers,
                    ),
                  ],
                ),
                if (config.bookIds.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '先选世界书，才能挑角色。',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ),
                const SizedBox(height: 8),
                for (final member in config.members)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundImage: member.avatar.isNotEmpty
                            ? FileImage(File(member.avatar))
                            : null,
                        child: member.avatar.isEmpty
                            ? Text(member.name.isEmpty ? '?' : member.name[0])
                            : null,
                      ),
                      title: Text(member.name),
                      subtitle: Text(
                        member.providerKey == null || member.modelId == null
                            ? '模型：跟随助手'
                            : '模型：${member.modelId}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '换头像',
                            icon: const Icon(Icons.image_outlined),
                            onPressed: () => _pickImage(member),
                          ),
                          IconButton(
                            tooltip: '选模型',
                            icon: const Icon(Icons.smart_toy_outlined),
                            onPressed: () => _pickModel(member),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _section(
            '世界观（最高优先级）',
            TextField(
              controller: _worldCtrl,
              maxLines: 4,
              onChanged: (v) => _save(config.copyWith(worldPrompt: v)),
              decoration: const InputDecoration(
                hintText: '所有角色必须遵守的背景设定…',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          _section(
            '本群设定',
            TextField(
              controller: _groupCtrl,
              maxLines: 3,
              onChanged: (v) => _save(config.copyWith(groupPrompt: v)),
              decoration: const InputDecoration(
                hintText: '这个群的氛围、主题、风格…',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: FilledButton.icon(
              onPressed: config.members.isEmpty
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            GroupChatPage(assistantId: widget.assistantId),
                      ),
                    ),
              icon: const Icon(Icons.forum_outlined),
              label: const Text('进入群聊'),
            ),
          ),
        ],
      ],
    );
  }
}

/// 选世界书（多选）。
class _BookPickSheet extends StatelessWidget {
  const _BookPickSheet({required this.selected});
  final List<String> selected;

  @override
  Widget build(BuildContext context) {
    final books = context.watch<WorldBookProvider>().books;
    final chosen = selected.toSet();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('选择世界书', style: TextStyle(fontSize: 18)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final book in books)
                    CheckboxListTile(
                      title: Text(book.name.isEmpty ? '(未命名)' : book.name),
                      subtitle: Text('${book.entries.length} 个条目'),
                      value: chosen.contains(book.id),
                      onChanged: (v) {
                        if (v == true) chosen.add(book.id);
                        else chosen.remove(book.id);
                        Navigator.of(context).pop<List<String>>(
                          chosen.toList(),
                        );
                      },
                    ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(chosen.toList()),
              child: const Text('完成'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 从选中世界书的条目里挑角色（多选）。每条 = 一个角色候选。
class _MemberPickSheet extends StatelessWidget {
  const _MemberPickSheet({required this.bookIds, required this.current});
  final List<String> bookIds;
  final List<GroupChatMember> current;

  @override
  Widget build(BuildContext context) {
    final wb = context.watch<WorldBookProvider>();
    final books = <WorldBook>[
      for (final id in bookIds)
        if (wb.getById(id) != null) wb.getById(id)!,
    ];
    final candidates = <String, GroupChatMember>{};
    for (final book in books) {
      for (final entry in book.entries) {
        final name = entry.name.trim();
        if (name.isEmpty) continue;
        if (candidates.containsKey(name)) continue;
        candidates[name] = GroupChatMember(
          name: name,
          entryId: entry.id,
          bookId: book.id,
        );
      }
    }
    for (final m in current) {
      candidates[m.name] = m;
    }
    final chosen = current.map((m) => m.name).toSet();

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('选择角色', style: TextStyle(fontSize: 18)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final entry in candidates.entries)
                    CheckboxListTile(
                      title: Text(entry.key),
                      subtitle: Text('来自 ${entry.value.bookId.isEmpty ? '世界书' : '已选书'}'),
                      value: chosen.contains(entry.key),
                      onChanged: (v) {
                        if (v == true) chosen.add(entry.key);
                        else chosen.remove(entry.key);
                        Navigator.of(context).pop<List<GroupChatMember>>(
                          [
                            for (final c in candidates.entries)
                              if (chosen.contains(c.key)) c.value,
                          ],
                        );
                      },
                    ),
                  if (candidates.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('选中的书里没有带名字的条目。'),
                    ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop([
                for (final c in candidates.entries)
                  if (chosen.contains(c.key)) c.value,
              ]),
              child: const Text('完成'),
            ),
          ],
        ),
      ),
    );
  }
}
