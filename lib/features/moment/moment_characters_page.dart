import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/world_book.dart';
import '../../core/providers/world_book_provider.dart';
import '../../core/services/chat/chat_service.dart';
import '../../core/services/social_affinity.dart';
import '../../core/services/social_store.dart';
import '../../icons/lucide_adapter.dart';
import '../wechat/wechat_ui.dart';
import 'moment_models.dart';
import 'moment_settings_page.dart';
import 'moment_store.dart';
import 'moment_widgets.dart';

/// 从选中的世界书里挑角色：条目标题就是角色名，正文是人设。
/// 可以同时用多本，同名的条目只算一次。
class MomentCharactersPage extends StatefulWidget {
  const MomentCharactersPage({super.key, required this.bookIds});

  final List<String> bookIds;

  @override
  State<MomentCharactersPage> createState() => _MomentCharactersPageState();
}

class _MomentCharactersPageState extends State<MomentCharactersPage> {
  late final MomentStore _store;
  late final SocialStore _social;
  late Set<String> _selected;

  List<WorldBook> get _books {
    final provider = context.read<WorldBookProvider>();
    final out = <WorldBook>[];
    for (final id in widget.bookIds) {
      final book = provider.getById(id.trim());
      if (book != null) out.add(book);
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    final chat = context.read<ChatService>();
    _store = MomentStore(chat);
    _social = SocialStore(chat);
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
      for (final book in _books)
        for (final e in book.entries)
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

  /// 长按某个角色：看好感度 + 作弊改分数/状态/颜值。
  Future<void> _editAffinity(String name) async {
    final key = name.trim();
    if (key.isEmpty) return;
    final current = _social.affinity(key);
    final updated = await showAffinityDialog(context, affinity: current);
    if (updated == null || !mounted) return;
    await _social.setAffinity(updated);
  }

  @override
  Widget build(BuildContext context) {
    final books = _books;
    return Theme(
      data: momentLightTheme(),
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '添加角色',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              Text(
                '点一下选用，长按改好感度',
                style: TextStyle(fontSize: 11, color: MomentColors.secondaryText),
              ),
            ],
          ),
        ),
        body: _buildBody(books),
      ),
    );
  }

  Widget _buildBody(List<WorldBook> books) {
    if (widget.bookIds.isEmpty || books.isEmpty) {
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
    final seen = <String>{};
    final entries = <WorldBookEntry>[];
    for (final book in books) {
      for (final entry in book.entries) {
        final name = entry.name.trim();
        if (name.isEmpty) continue;
        if (!seen.add(name)) continue;
        entries.add(entry);
      }
    }
    if (entries.isEmpty) {
      return const Center(
        child: Text(
          '选中的世界书里没有带名字的条目',
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
        final entry = entries[index];
        final name = entry.name.trim();
        final on = _selected.contains(name);
        return InkWell(
          onTap: () => _toggle(entry),
          onLongPress: () => _editAffinity(name),
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
