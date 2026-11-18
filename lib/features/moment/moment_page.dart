import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/providers/world_book_provider.dart';
import '../../core/services/chat/chat_service.dart';
import '../../icons/lucide_adapter.dart';
import 'moment_characters_page.dart';
import 'moment_models.dart';
import 'moment_service.dart';
import 'moment_settings_page.dart';
import 'moment_store.dart';
import 'moment_widgets.dart';

/// 朋友圈：点抽屉底部的罗盘进来。界面是新做的一套，不沿用对话气泡。
class MomentPage extends StatefulWidget {
  const MomentPage({super.key});

  @override
  State<MomentPage> createState() => _MomentPageState();
}

class _MomentPageState extends State<MomentPage> {
  late final MomentStore _store;
  List<MomentCharacter> _characters = const <MomentCharacter>[];
  List<MomentPost> _posts = const <MomentPost>[];
  bool _generating = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _store = MomentStore(context.read<ChatService>());
    _loadNow();
  }

  void _loadNow() {
    final conversation = _store.findConversation();
    final posts = <MomentPost>[...momentPostsOf(conversation)]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _characters = momentCharactersOf(conversation);
    _posts = posts;
    _loading = false;
  }

  void _reload() {
    _loadNow();
    if (mounted) setState(() {});
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
      );
  }

  String _messageFor(Object error) {
    final code = error is MomentServiceException ? error.code : '';
    switch (code) {
      case 'no_characters':
        return '还没有角色，先点右上角添加';
      case 'no_book':
        return '先去设置里选一本世界书';
      case 'model_missing':
        return '先去设置里选一个模型';
      case 'parse_failed':
        return '模型这次没按格式回，再点一次刷新';
      default:
        return '这次没生成出来，再点一次刷新';
    }
  }

  Future<void> _refresh() async {
    if (_generating) return;
    if (_characters.isEmpty) {
      _toast('还没有角色，先点右上角添加');
      return;
    }
    final settings = context.read<SettingsProvider>();
    final worldBooks = context.read<WorldBookProvider>();
    setState(() => _generating = true);
    try {
      final generator = MomentGenerator(
        settings: settings,
        worldBooks: worldBooks,
        bookId: settings.momentBookId,
        characters: _characters,
      );
      final posts = await generator.generate();
      await _store.appendPosts(posts);
      if (!mounted) return;
      _reload();
    } catch (error) {
      _toast(_messageFor(error));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _openCharacters() async {
    final bookId = context.read<SettingsProvider>().momentBookId;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MomentCharactersPage(bookId: bookId),
      ),
    );
    _reload();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const MomentSettingsPage()),
    );
    _reload();
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          '清除所有记录',
          style: TextStyle(color: MomentColors.primaryText, fontSize: 17),
        ),
        content: const Text(
          '所有动态、点赞和评论都会被删掉，加进去的角色名单保留。',
          style: TextStyle(color: MomentColors.primaryText, fontSize: 14),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清除', style: TextStyle(color: Color(0xFFC0392B))),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _store.clearPosts();
    if (!mounted) return;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: momentLightTheme(),
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: const Text(
            '朋友圈',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          actions: <Widget>[
            IconButton(
              tooltip: '刷新',
              onPressed: _generating ? null : _refresh,
              icon: _generating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Lucide.RefreshCw, size: 21),
            ),
            IconButton(
              tooltip: '添加角色',
              onPressed: _openCharacters,
              icon: const Icon(Lucide.MessageCirclePlus, size: 21),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Lucide.Ellipsis, size: 21),
              color: Colors.white,
              onSelected: (value) {
                if (value == 'settings') {
                  _openSettings();
                } else if (value == 'clear') {
                  _clearAll();
                }
              },
              itemBuilder: (_) => const <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'settings',
                  child: Text(
                    '设置',
                    style: TextStyle(color: MomentColors.primaryText),
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'clear',
                  child: Text(
                    '清除所有记录',
                    style: TextStyle(color: MomentColors.primaryText),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_characters.isEmpty) {
      return _Hint(text: '还没有角色', action: '添加角色', onAction: _openCharacters);
    }
    if (_posts.isEmpty) {
      return const _Hint(text: '还没有动态，点右上角刷新');
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: _posts.length,
      itemBuilder: (_, index) => MomentPostCard(post: _posts[index]),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text, this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              color: MomentColors.secondaryText,
            ),
          ),
          if (action != null) ...<Widget>[
            const SizedBox(height: 14),
            SizedBox(
              height: 38,
              child: OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  foregroundColor: MomentColors.name,
                  side: const BorderSide(color: MomentColors.hairline),
                ),
                child: Text(action!, style: const TextStyle(fontSize: 14)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 让页面在别的地方也能直接跳到朋友圈。
Future<void> openMomentPage(BuildContext context) {
  return Navigator.of(
    context,
  ).push<void>(MaterialPageRoute<void>(builder: (_) => const MomentPage()));
}
