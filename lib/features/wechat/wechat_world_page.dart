import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/world_book.dart';
import '../../core/providers/world_book_provider.dart';
import '../../core/services/chat/chat_service.dart';
import '../../icons/lucide_adapter.dart';
import 'wechat_models.dart';
import 'wechat_store.dart';
import 'wechat_ui.dart';

/// 世界观：两件事装在一页里。
///
/// 一是**写**：一个正经的多行文本框，想说什么设定都行，群聊和私聊都会塞进系统提示；
/// 二是**导**：从已有的世界书里挑几本，条目会当世界背景喂进去。
///
/// 两样各管各的，填了哪个算哪个。
class WechatWorldPage extends StatefulWidget {
  const WechatWorldPage({super.key});

  @override
  State<WechatWorldPage> createState() => _WechatWorldPageState();
}

class _WechatWorldPageState extends State<WechatWorldPage> {
  late WechatStore _store;
  late final TextEditingController _controller;
  WechatSettings _settings = const WechatSettings();
  List<String> _bookIds = const <String>[];

  @override
  void initState() {
    super.initState();
    _store = WechatStore(context.read<ChatService>());
    _settings = _store.wechatSettings();
    _controller = TextEditingController(text: _settings.worldPrompt);
    _bookIds = List<String>.from(_settings.bookIds);
  }

  @override
  void dispose() {
    // 手滑划返回也不能把刚写的一大段丢掉。
    unawaited(_save());
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() {
    final next = _settings.copyWith(
      worldPrompt: _controller.text,
      bookIds: List<String>.from(_bookIds),
    );
    _settings = next;
    return _store.saveWechatSettings(next);
  }

  Future<void> _saveAndClose() async {
    await _save();
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  void _toggleBook(WorldBook book) {
    setState(() {
      final next = <String>[..._bookIds];
      if (!next.remove(book.id)) next.add(book.id);
      _bookIds = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final books = context.watch<WorldBookProvider>().books;
    return Theme(
      data: wechatLightTheme(),
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
            onPressed: _saveAndClose,
            icon: const Icon(Lucide.ChevronLeft, size: 22, color: Colors.black),
          ),
          title: const Text(
            '世界观',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: _saveAndClose,
              child: const Text(
                '保存',
                style: TextStyle(fontSize: 15, color: Colors.black),
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: <Widget>[
            _header('世界观设定'),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: TextField(
                controller: _controller,
                minLines: 6,
                maxLines: 16,
                keyboardType: TextInputType.multiline,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(
                  fontSize: 14.5,
                  height: 1.55,
                  color: WechatColors.primaryText,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText:
                      '这里写什么都行：年代、地点、规矩、角色之间的关系……\n'
                      '群聊和私聊都会把这段塞进提示词，只写一次，两边都认。',
                  hintStyle: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: Color(0xFFB2B2B2),
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                '跟下面导入的世界书是两条路，各填各的，都填也不冲突。',
                style: TextStyle(
                  fontSize: 11.5,
                  color: WechatColors.secondaryText,
                  height: 1.6,
                ),
              ),
            ),

            _header('从世界书导入'),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '勾上的书：条目会当世界背景喂进去，通讯录加人、私聊也都从这几本里找人设。\n'
                '群聊自己有单独的一份，不受这里影响。',
                style: TextStyle(
                  fontSize: 11.5,
                  color: WechatColors.secondaryText,
                  height: 1.6,
                ),
              ),
            ),
            if (books.isEmpty)
              Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                alignment: Alignment.centerLeft,
                child: const Text(
                  '还没有世界书，先去建一本',
                  style: TextStyle(
                    fontSize: 13,
                    color: WechatColors.secondaryText,
                  ),
                ),
              )
            else
              Container(
                color: Colors.white,
                child: Column(
                  children: <Widget>[for (final book in books) _bookRow(book)],
                ),
              ),
          ],
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

  Widget _bookRow(WorldBook book) {
    final checked = _bookIds.contains(book.id);
    return InkWell(
      onTap: () => _toggleBook(book),
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
                    book.name.trim().isEmpty ? '未命名世界书' : book.name,
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
  }
}
