import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/providers/world_book_provider.dart';
import '../../core/services/chat/chat_service.dart';
import '../../icons/lucide_adapter.dart';
import 'moment_assets_page.dart';
import 'moment_contacts_dialog.dart';
import 'moment_author_page.dart';
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
  Map<String, MomentAssets> _assets = const <String, MomentAssets>{};
  bool _generating = false;
  bool _loading = true;

  /// 我正在等谁的回我一句，那一条帖子底下就转个小圈。
  String? _waitingReplyPostId;

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
    _assets = momentAssetsOf(conversation);
    _posts = posts;
    _loading = false;
  }

  void _reload() {
    _loadNow();
    if (mounted) setState(() {});
  }

  String _personaName([SettingsProvider? settings]) {
    final value = (settings ?? context.read<SettingsProvider>())
        .momentPersonaName
        .trim();
    return value.isEmpty ? '我' : value;
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
        return '这次没生成出来，再点一次刷新；一直失败就去设置里把「旧帖最多喂多少字」调小';
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
        personaName: _personaName(settings),
        recentPosts: _posts,
        contextCharLimit: settings.momentContextChars,
      );
      final batch = await generator.generate();
      await _store.applyBatch(batch);
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

  Future<void> _openContacts() {
    return showMomentContactsDialog(
      context,
      characters: _characters,
      assets: _assets,
      onOpen: _openAuthor,
    );
  }

  Future<void> _openAssets() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const MomentAssetsPage()),
    );
    _reload();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const MomentSettingsPage()),
    );
    _reload();
  }

  Future<void> _openAuthor(String author) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => MomentAuthorPage(author: author)),
    );
    _reload();
  }

  Future<void> _toggleLike(MomentPost post) async {
    try {
      await _store.toggleLike(post.id, _personaName());
      if (!mounted) return;
      _reload();
    } catch (_) {
      _toast('点赞没存上，再试一次');
    }
  }

  Future<void> _compose() async {
    final result = await showModalBottomSheet<_ComposeResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const _ComposeSheet(),
    );
    if (result == null || !mounted) return;
    final text = result.text.trim();
    if (text.isEmpty) return;
    try {
      await _store.addPost(
        MomentPost(
          id: newMomentPostId(),
          author: _personaName(),
          createdAt: DateTime.now(),
          text: text,
          hasImage: result.withImage,
          isMine: true,
        ),
      );
      if (!mounted) return;
      _reload();
    } catch (_) {
      _toast('没发出去，再试一次');
    }
  }

  Future<void> _comment(MomentPost post, {String? replyTo}) async {
    final target = (replyTo ?? post.author).trim();
    final myText = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _CommentSheet(post: post, replyTo: target),
    );
    if (!mounted) return;
    final text = (myText ?? '').trim();
    if (text.isEmpty) return;
    final me = _personaName();
    final myComment = MomentComment(
      author: me,
      text: text,
      replyTo: target == me ? null : target,
    );
    try {
      await _store.addComments(post.id, <MomentComment>[myComment]);
    } catch (_) {
      _toast('评论没存上，再试一次');
      return;
    }
    if (!mounted) return;
    _reload();
    await _askForReplies(post, text, me, target);
  }

  Future<void> _askForReplies(
    MomentPost post,
    String myText,
    String me,
    String replyTo,
  ) async {
    setState(() => _waitingReplyPostId = post.id);
    try {
      final settings = context.read<SettingsProvider>();
      final worldBooks = context.read<WorldBookProvider>();
      final composer = MomentReplyComposer(
        settings: settings,
        worldBooks: worldBooks,
        bookId: settings.momentBookId,
        characters: _characters,
        personaName: me,
        post: post,
        myText: myText,
        replyTo: replyTo,
      );
      final replies = await composer.compose();
      if (replies.isNotEmpty) {
        await _store.addComments(post.id, replies);
      }
      if (!mounted) return;
      _reload();
    } catch (_) {
      // 没人回就算了，不打扰。
    } finally {
      if (mounted) setState(() => _waitingReplyPostId = null);
    }
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
    try {
      await _store.clearPosts();
      if (!mounted) return;
      _reload();
    } catch (_) {
      _toast('清空没成功，再试一次');
    }
  }

  @override
  Widget build(BuildContext context) {
    final persona = _personaName(context.watch<SettingsProvider>());
    final personaAssets =
        _assets[MomentAssets.personaKey] ?? const MomentAssets();
    return Theme(
      data: momentLightTheme(),
      child: Scaffold(
        backgroundColor: MomentColors.background,
        body: Stack(
          children: <Widget>[
            RefreshIndicator(
              onRefresh: _refresh,
              color: MomentColors.name,
              backgroundColor: Colors.white,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                children: <Widget>[
                  MomentCover(name: persona, coverPath: personaAssets.cover),
                  MomentPanel(
                    avatarName: persona,
                    avatarPath: personaAssets.avatar,
                    onTapAvatar: () => _openAuthor(persona),
                    child: _buildBody(persona),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: MomentTopBar(
                onBack: () => Navigator.of(context).maybePop(),
                actions: <Widget>[
                  MomentRoundButton(
                    icon: Lucide.RefreshCw,
                    onTap: _generating ? null : _refresh,
                    child: _generating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                  ),
                  MomentPill(
                    icon: Lucide.SquarePen,
                    label: '发布',
                    onTap: _compose,
                  ),
                  PopupMenuButton<String>(
                    color: Colors.white,
                    padding: EdgeInsets.zero,
                    onSelected: (value) {
                      if (value == 'characters') {
                        _openCharacters();
                      } else if (value == 'assets') {
                        _openAssets();
                      } else if (value == 'settings') {
                        _openSettings();
                      } else if (value == 'clear') {
                        _clearAll();
                      }
                    },
                    itemBuilder: (_) => const <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(
                        value: 'characters',
                        child: Text(
                          '邀请角色',
                          style: TextStyle(color: MomentColors.primaryText),
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'assets',
                        child: Text(
                          '角色管理',
                          style: TextStyle(color: MomentColors.primaryText),
                        ),
                      ),
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
                    child: const MomentRoundButton(
                      icon: Lucide.Ellipsis,
                      onTap: null,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 18,
              bottom: 26,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _openContacts,
                child: Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    shape: BoxShape.circle,
                    border: Border.all(color: MomentColors.hairline),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x26000000),
                        blurRadius: 14,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Text('📔', style: TextStyle(fontSize: 24)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(String persona) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_characters.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: _Hint(text: '还没有角色', action: '添加角色', onAction: _openCharacters),
      );
    }
    if (_posts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: _Hint(text: '还没有动态，点右上角刷新'),
      );
    }
    return Column(
      children: <Widget>[
        for (final post in _posts)
          MomentPostCard(
            post: post,
            avatarPath: _assets[post.author]?.avatar,
            likedByMe: post.likes.contains(persona),
            onTapAvatar: () => _openAuthor(post.author),
            onTapLike: () => _toggleLike(post),
            onTapComment: () => _comment(post),
            onTapCommentLine: (comment) =>
                _comment(post, replyTo: comment.author),
            waitingReply: _waitingReplyPostId == post.id,
          ),
        const SizedBox(height: 24),
      ],
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

class _ComposeResult {
  const _ComposeResult({required this.text, required this.withImage});

  final String text;
  final bool withImage;
}

/// 我自己发一条动态。
class _ComposeSheet extends StatefulWidget {
  const _ComposeSheet();

  @override
  State<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends State<_ComposeSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _withImage = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    Navigator.of(
      context,
    ).pop(_ComposeResult(text: text, withImage: _withImage));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            '发一条动态',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: MomentColors.primaryText,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            style: const TextStyle(
              fontSize: 15,
              height: 1.45,
              color: MomentColors.primaryText,
            ),
            decoration: const InputDecoration(
              isDense: true,
              hintText: '随便写点什么',
              hintStyle: TextStyle(
                fontSize: 14,
                color: MomentColors.secondaryText,
              ),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Switch(
                value: _withImage,
                onChanged: (value) => setState(() => _withImage = value),
              ),
              const Text(
                '带图',
                style: TextStyle(fontSize: 13, color: MomentColors.primaryText),
              ),
              const Spacer(),
              TextButton(onPressed: _submit, child: const Text('发布')),
            ],
          ),
        ],
      ),
    );
  }
}

/// 我在某条帖子下评论。
class _CommentSheet extends StatefulWidget {
  const _CommentSheet({required this.post, required this.replyTo});

  final MomentPost post;

  /// 这条评论回的是谁。等于帖主时就是普通评论。
  final String replyTo;

  @override
  State<_CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<_CommentSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            widget.replyTo == widget.post.author
                ? '评论 ${widget.post.author} 的动态'
                : '回复 ${widget.replyTo}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: MomentColors.primaryText,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 2,
            maxLines: 6,
            style: const TextStyle(
              fontSize: 15,
              height: 1.45,
              color: MomentColors.primaryText,
            ),
            decoration: const InputDecoration(
              isDense: true,
              hintText: '说一句',
              hintStyle: TextStyle(
                fontSize: 14,
                color: MomentColors.secondaryText,
              ),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: _submit, child: const Text('发送')),
          ),
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
