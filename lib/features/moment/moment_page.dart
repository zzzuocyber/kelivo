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

  /// 底部那条内嵌输入栏：正在评论哪条、回谁。
  MomentPost? _composerPost;
  String? _composerReplyTo;
  final TextEditingController _composerController = TextEditingController();
  final FocusNode _composerFocus = FocusNode();

  /// 每条动态的评论区当前在第几页（十条一页）。
  final Map<String, int> _commentPages = <String, int>{};

  /// 正在重写哪条动态 / 哪条评论（长按菜单里的「刷新」）。
  String? _rewritingPostId;
  String? _rewritingCommentKey;

  @override
  void initState() {
    super.initState();
    _store = MomentStore(context.read<ChatService>());
    _loadNow();
  }

  @override
  void dispose() {
    _composerController.dispose();
    _composerFocus.dispose();
    super.dispose();
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

  void _openComposer(MomentPost post, {String? replyTo}) {
    final target = (replyTo ?? post.author).trim();
    setState(() {
      _composerPost = post;
      _composerReplyTo = target;
      _composerController.clear();
    });
    // 焦点等一帧再给，否则输入栏还没挂上键盘弹不出来。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _composerFocus.requestFocus();
    });
  }

  void _closeComposer() {
    _composerFocus.unfocus();
    setState(() {
      _composerPost = null;
      _composerReplyTo = null;
      _composerController.clear();
    });
  }

  Future<void> _sendComposer() async {
    final post = _composerPost;
    final target = _composerReplyTo ?? '';
    if (post == null) return;
    final text = _composerController.text.trim();
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
    _closeComposer();
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
        recentPosts: _posts,
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

  Future<void> _showPostMenu(MomentPost post, Offset position) async {
    final action = await _showAnchorMenu(position, <String>['刷新', '删除']);
    if (action == null) return;
    if (action == '删除') {
      await _confirmDelete(
        '删除这条动态？',
        '连同它的点赞和评论一起删掉。',
        onOk: () => _store.deletePost(post.id),
      );
      return;
    }
    await _rewritePost(post);
  }

  Future<void> _showCommentMenu(
    MomentPost post,
    int index,
    MomentComment comment,
    Offset position,
  ) async {
    if (_rewritingCommentKey != null) return;
    final action = await _showAnchorMenu(position, <String>['刷新', '删除']);
    if (action == null) return;
    if (action == '删除') {
      await _confirmDelete(
        '删除这条回复？',
        '只删这一条，别的不动。',
        onOk: () => _store.deleteComment(post.id, index),
      );
      return;
    }
    await _rewriteComment(post, index, comment);
  }

  /// 贴着手指弹的小菜单，不从底部升起。
  Future<String?> _showAnchorMenu(Offset position, List<String> actions) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final size = MediaQuery.sizeOf(context);
    final left = position.dx > size.width / 2 ? position.dx - 150 : position.dx;
    final top = position.dy;
    return showMenu<String>(
      context: context,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      position: RelativeRect.fromLTRB(
        left,
        top,
        (overlay?.size.width ?? size.width) - left - 140,
        (overlay?.size.height ?? size.height) - top,
      ),
      items: <PopupMenuEntry<String>>[
        for (final action in actions)
          PopupMenuItem<String>(
            value: action,
            height: 44,
            child: Text(
              action,
              style: TextStyle(
                fontSize: 14,
                color: action == '删除'
                    ? const Color(0xFFC0392B)
                    : MomentColors.primaryText,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _confirmDelete(
    String title,
    String message, {
    Future<void> Function()? onOk,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          title,
          style: const TextStyle(color: MomentColors.primaryText, fontSize: 17),
        ),
        content: Text(
          message,
          style: const TextStyle(color: MomentColors.primaryText, fontSize: 14),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除', style: TextStyle(color: Color(0xFFC0392B))),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      if (onOk != null) await onOk();
      if (!mounted) return;
      _reload();
    } catch (_) {
      _toast('没删掉，再试一次');
    }
  }

  Future<void> _rewritePost(MomentPost post) async {
    setState(() => _rewritingPostId = post.id);
    try {
      final settings = context.read<SettingsProvider>();
      final worldBooks = context.read<WorldBookProvider>();
      final rewriter = MomentRewriter(
        settings: settings,
        worldBooks: worldBooks,
        bookId: settings.momentBookId,
        characters: _characters,
        personaName: _personaName(settings),
        recentPosts: _posts,
      );
      final text = await rewriter.rewritePost(post);
      if (text != null && text.isNotEmpty) {
        await _store.updatePostText(post.id, text);
      } else {
        _toast('这次没重写出东西，再长按试一次');
      }
    } catch (_) {
      _toast('重写没成功，再长按试一次');
    } finally {
      if (mounted) {
        setState(() => _rewritingPostId = null);
        _reload();
      }
    }
  }

  Future<void> _rewriteComment(
    MomentPost post,
    int index,
    MomentComment comment,
  ) async {
    final key = '${post.id}#$index';
    setState(() => _rewritingCommentKey = key);
    try {
      final settings = context.read<SettingsProvider>();
      final worldBooks = context.read<WorldBookProvider>();
      final rewriter = MomentRewriter(
        settings: settings,
        worldBooks: worldBooks,
        bookId: settings.momentBookId,
        characters: _characters,
        personaName: _personaName(settings),
        recentPosts: _posts,
      );
      final text = await rewriter.rewriteComment(post, comment);
      if (text != null && text.isNotEmpty) {
        await _store.updateCommentText(post.id, index, text);
      } else {
        _toast('这次没重写出东西，再长按试一次');
      }
    } catch (_) {
      _toast('重写没成功，再长按试一次');
    } finally {
      if (mounted) {
        setState(() => _rewritingCommentKey = null);
        _reload();
      }
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
        backgroundColor: MomentColors.card,
        // 键盘自己处理：底部输入栏按 viewInsets 上移，页面不再被压扁。
        resizeToAvoidBottomInset: false,
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
                  MomentCover(coverPath: personaAssets.cover),
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
            if (_composerPost == null)
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
            if (_composerPost != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedPadding(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: _buildComposerBar(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildComposerBar() {
    final target = _composerReplyTo ?? '';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: const BoxDecoration(
        color: Color(0xFFF7F8FA),
        border: Border(top: BorderSide(color: MomentColors.hairline)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (target.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '回复 $target',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: MomentColors.name,
                      ),
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _closeComposer,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Lucide.X,
                        size: 16,
                        color: MomentColors.secondaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _composerController,
                  focusNode: _composerFocus,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendComposer(),
                  style: const TextStyle(
                    fontSize: 14.5,
                    height: 1.4,
                    color: MomentColors.primaryText,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    hintText: '说一句',
                    hintStyle: const TextStyle(
                      fontSize: 14,
                      color: MomentColors.secondaryText,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: MomentColors.hairline,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: MomentColors.hairline,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(onPressed: _sendComposer, child: const Text('发送')),
            ],
          ),
        ],
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
            avatarPath: momentAssetsForAuthor(
              _assets,
              post.author,
              persona,
            )?.avatar,
            likedByMe: post.likes.contains(persona),
            onTapAvatar: () => _openAuthor(post.author),
            onTapLike: () => _toggleLike(post),
            onTapComment: () => _openComposer(post),
            onTapCommentLine: (comment) =>
                _openComposer(post, replyTo: comment.author),
            onLongPressPost: _rewritingPostId == post.id
                ? null
                : (position) => _showPostMenu(post, position),
            onLongPressComment: (index, comment, position) =>
                _showCommentMenu(post, index, comment, position),
            commentPage: _commentPages[post.id] ?? 0,
            onCommentPageChanged: (page) =>
                setState(() => _commentPages[post.id] = page),
            waitingReply: _waitingReplyPostId == post.id,
          ),
        SizedBox(height: _composerPost == null ? 24 : 96),
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

/// 让页面在别的地方也能直接跳到朋友圈。
Future<void> openMomentPage(BuildContext context) {
  return Navigator.of(
    context,
  ).push<void>(MaterialPageRoute<void>(builder: (_) => const MomentPage()));
}
