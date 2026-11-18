import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/world_book.dart';
import '../../core/providers/world_book_provider.dart';
import '../../core/services/chat/chat_service.dart';
import '../../icons/lucide_adapter.dart';
import 'moment_models.dart';
import 'moment_settings_page.dart';
import 'moment_store.dart';
import 'moment_widgets.dart';

/// 从选定的那本世界书里挑角色：条目标题就是角色名，正文是人设。
class MomentCharactersPage extends StatefulWidget {
  const MomentCharactersPage({super.key, required this.bookId});

  final String bookId;

  @override
  State<MomentCharactersPage> createState() => _MomentCharactersPageState();
}

class _MomentCharactersPageState extends State<MomentCharactersPage> {
  late final MomentStore _store;
  late Set<String> _selected;

  WorldBook? get _book =>
      context.read<WorldBookProvider>().getById(widget.bookId.trim());

  @override
  void initState() {
    super.initState();
    final chat = context.read<ChatService>();
    _store = MomentStore(chat);
    final conversation = _store.findConversation();
    _selected = <String>{
      for (final c in momentCharactersOf(conversation)) c.name,
    };
  }

  Future<void> _toggle(WorldBookEntry entry) async {
    final name = entry.name.trim();
    if (name.isEmpty) return;
    setState(() {
      if (!_selected.remove(name)) _selected.add(name);
    });
    final allSelectedNames = <String>{..._selected};
    final characters = <MomentCharacter>[
      for (final e in _book?.entries ?? const <WorldBookEntry>[])
        if (allSelectedNames.contains(e.name.trim()) &&
            e.name.trim().isNotEmpty)
          MomentCharacter(name: e.name.trim(), entryId: e.id),
    ];
    try {
      await _store.saveCharacters(characters);
    } catch (_) {
      // 存不进去也不炸页面，下次进来再保存。
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;
    return Theme(
      data: momentLightTheme(),
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: const Text(
            '添加角色',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ),
        body: _buildBody(book),
      ),
    );
  }

  Widget _buildBody(WorldBook? book) {
    if (widget.bookId.trim().isEmpty || book == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              '还没有选世界书',
              style: TextStyle(fontSize: 14, color: MomentColors.secondaryText),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 38,
              child: OutlinedButton(
                onPressed: () async {
                  await Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const MomentSettingsPage(),
                    ),
                  );
                  setState(() {});
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: MomentColors.name,
                  side: const BorderSide(color: MomentColors.hairline),
                ),
                child: const Text('去设置', style: TextStyle(fontSize: 14)),
              ),
            ),
          ],
        ),
      );
    }
    final entries = book.entries.where((e) => e.name.trim().isNotEmpty);
    if (entries.isEmpty) {
      return const Center(
        child: Text(
          '这本世界书里没有带名字的条目',
          style: TextStyle(fontSize: 14, color: MomentColors.secondaryText),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      itemCount: entries.length,
      separatorBuilder: (context, index) =>
          const Divider(height: 1, color: MomentColors.hairline),
      itemBuilder: (_, index) {
        final entry = entries.elementAt(index);
        final name = entry.name.trim();
        final on = _selected.contains(name);
        return InkWell(
          onTap: () => _toggle(entry),
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              children: <Widget>[
                MomentAvatar(name: name, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 15,
                      color: MomentColors.primaryText,
                    ),
                  ),
                ),
                Icon(
                  on ? Lucide.Check : Lucide.Plus,
                  size: 20,
                  color: on ? MomentColors.name : MomentColors.secondaryText,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
