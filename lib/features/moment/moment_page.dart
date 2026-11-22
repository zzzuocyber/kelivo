import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/providers/world_book_provider.dart';
import '../../core/services/chat/chat_service.dart';
import '../../core/services/social_affinity.dart';
import '../../core/services/social_store.dart';
import '../../core/utils/token_estimator.dart';
import '../../core/utils/pinyin_sort.dart';
import '../../icons/lucide_adapter.dart';
import '../wechat/wechat_store.dart';
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
  late final SocialStore _social;
  late final WechatStore _wechatStore;
  List<MomentCharacter> _characters = const <MomentCharacter>[];
  List<MomentPost> _posts = const <MomentPost>[];
  Map<String, MomentAssets> _assets = const <String, MomentAssets>{};
  bool _generating = false;
  bool _loading = true;

  /// 我正在等谁的回我一句，那一条帖子底下就转个小圈。
  String? _waitingReplyPostId;

  /// 现在开着天意的那个人；null = 没开，评论署名回到我自己的马甲。
  String? _divineName;

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
    final chat = context.read<ChatService>();
    _store = MomentStore(chat);
    _social = SocialStore(chat);
    _wechatStore = WechatStore(chat);
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
    final divine = momentDivineOf(conversation);
    // 天意指向的角色被删掉就不算数，免得评论区署名落在一个名单外的人身上。
    _divineName =
        divine.isNotEmpty && _characters.any((c) => c.name.trim() == divine)
        ? divine
        : null;
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

  /// 现在拿谁的名义说话：开了天意就是那个人，没开就是我自己的马甲。
  String _actingName([SettingsProvider? settings]) {
    final divine = (_divineName ?? '').trim();
    if (divine.isNotEmpty) return divine;
    return _personaName(settings);
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

  /// 生成朋友圈前，把每个角色此刻的去处和最近在微信里说过的话整理成一段，
  /// 注入提示词。时间地点跟群聊/私聊共用同一份作息表，所以三处对得上。
  Future<String> _buildSocialContext() async {
    final lines = <String>[];
    // 故事时间坐标，跟群聊/私聊同一份；明确告诉模型现在星期几、白天还是晚上。
    lines.add(_social.storyTimeLine);
    for (final character in _characters) {
      final where = _social.whereabouts(character.name).promptLine;
      lines.add('${character.name}：$where');
      // 他在微信里说过的话，取最近几条。删过记录的角色跳过水位线之前的话。
      final wechat = _wechatStore.memoryLinesFor(
        character.name,
        limit: 6,
        since: _social.forgetFloor(character.name),
      );
      for (final line in wechat.take(6)) {
        lines.add('  - $line');
      }
    }
    final mode = _social.contextMode('moment');
    final manual = _social.plotSummary.trim();
    // 摘要模式 + 我写了剧情概括：三场景共用这一份，不再各压各的。
    final body = mode.isSummary && manual.isNotEmpty
        ? manual
        : (mode.isSummary ? socialSummarize(lines) : lines.join('\n'));
    unawaited(_social.addTokens('moment', estimateTokens(body)));
    return body;
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
      final socialContext = await _buildSocialContext();
      final generator = MomentGenerator(
        settings: settings,
        worldBooks: worldBooks,
        bookIds: _wechatStore.wechatSettings().bookIds,
        characters: _characters,
        personaName: _personaName(settings),
        recentPosts: _posts,
        contextCharLimit: settings.momentContextChars,
        socialContext: socialContext,
        heartVoiceNames: _social.heartVoiceNames(),
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
    final bookIds = _wechatStore.wechatSettings().bookIds;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MomentCharactersPage(bookIds: bookIds),
      ),
    );
    _reload();
  }

  Future<void> _openContacts() async {
    final outcome = await showMomentContactsDialog(
      context,
      characters: _characters,
      assets: _assets,
      divineName: _divineName,
      // 弹窗改完不关窗，所以天意得当场写进库，不能再等返回值。
      onDivineChanged: _setDivine,
    );
    if (outcome == null || !mounted) return;
    await _openAuthor(outcome.openAuthor);
  }

  /// 返回 true 才算存上了；弹窗那边只有拿到 true 才把灰底挪过去。
  Future<bool> _setDivine(String? name) async {
    try {
      await _store.setDivine(name);
      if (!mounted) return false;
      _reload();
      return true;
    } catch (_) {
      _toast('天意没存上，再试一次');
      return false;
    }
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
    final me = _actingName();
    // 穿着谁的皮，就别给那个人自己的帖子点赞。
    if (_divineName != null && post.author.trim() == me) return;
    try {
      await _store.toggleLike(post.id, me);
      // 以我自己名义给角色点赞 = 朋友圈互动，好感微涨（夺舍不算）。
      final author = post.author.trim();
      if (_divineName == null && author.isNotEmpty && author != me) {
        unawaited(_social.applyAffinityEvent(author, AffinityEvent.momentTouch));
      }
      if (!mounted) return;
      _reload();
    } catch (_) {
      _toast('点赞没存上，再试一次');
    }
  }

  Future<void> _compose() async {
    final result = await showModalBottomSheet<MomentComposeResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const MomentComposeSheet(),
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
    final me = _actingName();
    final myComment = MomentComment(
      author: me,
      text: text,
      replyTo: target == me ? null : target,
    );
    try {
      await _store.addComments(post.id, <MomentComment>[myComment]);
      // 以我自己名义回复角色 = 朋友圈互动，好感微涨（夺舍不算）。
      final who = target.trim();
      if (_divineName == null && who.isNotEmpty && who != me) {
        unawaited(_social.applyAffinityEvent(who, AffinityEvent.momentTouch));
      }
    } catch (_) {
      _toast('评论没存上，再试一次');
      return;
    }
    if (!mounted) return;
    _closeComposer();
    _reload();
    final mentioned = _mentionsIn(text);
    if (mentioned.isNotEmpty) {
      await _askMentioned(post, text, me, mentioned);
      return;
    }
    await _askForReplies(post, text, me, target);
  }

  /// 从我说的话里挑出「@了谁」。名字要一字不差，长名字优先，只认通讯录里的人；
  /// 我自己的马甲、以及现在穿着的这个角色都不算。
  List<String> _mentionsIn(String text) {
    final persona = _personaName().trim();
    final acting = _actingName().trim();
    final names = <String>[
      for (final character in _characters)
        if (character.name.trim() != persona && character.name.trim() != acting)
          character.name.trim(),
    ]..sort((a, b) => b.length.compareTo(a.length));
    if (names.isEmpty) return const <String>[];
    final pattern = RegExp('@(${names.map(RegExp.escape).join('|')})');
    final out = <String>[];
    for (final match in pattern.allMatches(text)) {
      final name = match.group(1);
      if (name == null || name.isEmpty) continue;
      if (!out.contains(name)) out.add(name);
    }
    return out;
  }

  /// @ 了谁，谁就单独回我一句；@ 几个就几条。
  Future<void> _askMentioned(
    MomentPost post,
    String myText,
    String me,
    List<String> mentioned,
  ) async {
    setState(() => _waitingReplyPostId = post.id);
    try {
      final settings = context.read<SettingsProvider>();
      final worldBooks = context.read<WorldBookProvider>();
      final composer = MomentMentionReplies(
        settings: settings,
        worldBooks: worldBooks,
        bookIds: _wechatStore.wechatSettings().bookIds,
        characters: _characters,
        personaName: me,
        post: post,
        myText: myText,
        mentioned: mentioned,
        recentPosts: _posts,
      );
      final replies = await composer.compose();
      if (replies.isNotEmpty) {
        await _store.addComments(post.id, replies);
      }
      if (!mounted) return;
      _reload();
    } catch (_) {
      // 有人没回就算了，不打扰。
    } finally {
      if (mounted) setState(() => _waitingReplyPostId = null);
    }
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
        bookIds: _wechatStore.wechatSettings().bookIds,
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
    // 心声是角色发这条动态时存下的；我发的动态没有。
    final hasHeart = !post.isMine && post.heartVoice.trim().isNotEmpty;
    final actions = <String>[
      if (hasHeart) '偷看心声',
      '刷新',
      '删除',
    ];
    final action = await _showAnchorMenu(position, actions);
    if (action == null) return;
    if (action == '偷看心声') {
      await showDialog<void>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: Row(
            children: <Widget>[
              const Icon(Lucide.Heart, size: 18, color: MomentColors.name),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${post.author} 的心声',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            post.heartVoice,
            style: const TextStyle(
              fontSize: 14,
              color: MomentColors.primaryText,
              height: 1.5,
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }
    if (action == '删除') {
      await _confirmDelete(
        '删除这条动态？',
        '连同它的点赞和评论一起删掉，角色也不会再记得。',
        onOk: () async {
          await _store.deletePost(post.id);
          // 连根清：作者是角色的话，让他忘掉这一刻之前的记忆。
          if (!post.isMine && post.author.trim().isNotEmpty) {
            await _social.forgetBefore(<String>[post.author]);
          }
        },
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
    final author = comment.author.trim();
    final lastSummon = _store.summonName();
    final canRepeat =
        lastSummon.isNotEmpty &&
        lastSummon != author &&
        _characters.any((c) => c.name.trim() == lastSummon);
    final actions = <String>[
      '召唤',
      if (canRepeat) '再叫一次 $lastSummon',
      '刷新',
      '删除',
    ];
    final action = await _showAnchorMenu(position, actions);
    if (action == null) return;
    if (action == '召唤') {
      await _pickSummon(post, comment);
      return;
    }
    if (canRepeat && action == '再叫一次 $lastSummon') {
      await _summon(post, comment, lastSummon);
      return;
    }
    if (action == '删除') {
      await _confirmDelete(
        '删除这条回复？',
        '只删这一条，角色也不会再记得。',
        onOk: () async {
          await _store.deleteComment(post.id, index);
          // 连根清：作者是角色的话，让他忘掉这一刻之前的记忆。
          if (author.isNotEmpty) {
            await _social.forgetBefore(<String>[author]);
          }
        },
      );
      return;
    }
    await _rewriteComment(post, index, comment);
  }

  /// 长按评论气泡图标：不用先选评论，直接挑人。有评论就回最新那条，没评论就回帖子本身。
  Future<void> _pickSummonForPost(MomentPost post) async {
    final comment = post.comments.isEmpty
        ? MomentComment(
            author: post.author,
            text: post.text.trim().isEmpty ? '这条动态' : post.text,
          )
        : post.comments.last;
    await _pickSummon(post, comment);
  }

  /// 召唤：挑一个人，让他去回这条评论。名单里排掉评论作者自己。
  ///
  /// 名单只按首字母分组，右侧给一条 A～Z 索引；收藏那套没用，已经去掉。
  Future<void> _pickSummon(MomentPost post, MomentComment comment) async {
    // 作者本人也在名单里：他可以接着自己这条往下说（补充、改口都行）。
    final pool = sortedByPinyin(<MomentCharacter>[
      for (final character in _characters)
        if (character.name.trim().isNotEmpty) character,
    ], (character) => character.name);
    if (pool.isEmpty) {
      _toast('通讯录里没人可以召唤');
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (sheetCtx) => _SummonSheet(pool: pool, avatars: _assets),
    );
    if (!mounted || picked == null) return;
    await _summon(post, comment, picked);
  }

  /// 让 [who] 去回这条评论。走的是「@ 某人单独回一次」那套引擎，
  /// 只是把"回应我的评论"换成"回应某条评论"。
  Future<void> _summon(
    MomentPost post,
    MomentComment comment,
    String who,
  ) async {
    setState(() => _waitingReplyPostId = post.id);
    try {
      final settings = context.read<SettingsProvider>();
      final worldBooks = context.read<WorldBookProvider>();
      final composer = MomentMentionReplies(
        settings: settings,
        worldBooks: worldBooks,
        bookIds: _wechatStore.wechatSettings().bookIds,
        characters: _characters,
        personaName: _actingName(settings),
        post: post,
        myText: comment.text,
        mentioned: <String>[who],
        replyTarget: comment.author.trim(),
        recentPosts: _posts,
      );
      final replies = await composer.compose();
      if (replies.isNotEmpty) {
        await _store.addComments(post.id, replies);
        await _store.setSummon(who);
      }
      if (!mounted) return;
      _reload();
    } catch (_) {
      // 没叫来就算了，不打扰。
    } finally {
      if (mounted) setState(() => _waitingReplyPostId = null);
    }
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
        bookIds: _wechatStore.wechatSettings().bookIds,
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
        bookIds: _wechatStore.wechatSettings().bookIds,
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
    final acting = (_divineName ?? '').trim().isEmpty
        ? persona
        : _divineName!.trim();
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
                    child: _buildBody(persona, acting),
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
    final divine = (_divineName ?? '').trim();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: const BoxDecoration(
        color: Color(0xFFF7F8FA),
        border: Border(top: BorderSide(color: MomentColors.hairline)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (divine.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '已开启天意：$divine',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: MomentColors.secondaryText,
                  ),
                ),
              ),
            ),
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

  Widget _buildBody(String persona, String acting) {
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
            likedByMe: post.likes.contains(acting),
            onTapAvatar: () => _openAuthor(post.author),
            onTapLike: () => _toggleLike(post),
            // 评论气泡：单击=我评论；长按=召唤角色来回。
            onTapComment: () => _openComposer(post),
            onLongPressCommentIcon: () => _pickSummonForPost(post),
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

/// 让页面在别的地方也能直接跳到朋友圈。
Future<void> openMomentPage(BuildContext context) {
  return Navigator.of(context)
      .push<void>(MaterialPageRoute<void>(builder: (_) => const MomentPage()));
}

// ============================================================
// 召唤列表：按名字首字母分组，右侧一条 A～Z 索引
// ============================================================

/// 召唤谁去回这条评论。
///
/// 这个面板是插到根 Overlay 上的，**不继承朋友圈那套浅色主题**，
/// 所以配色一律写死（浅底 + 深字），不然夜间模式下白底白字看不见。
class _SummonSheet extends StatefulWidget {
  const _SummonSheet({required this.pool, required this.avatars});

  /// 候选角色，进来之前已经按首字母排好序。
  final List<MomentCharacter> pool;
  final Map<String, MomentAssets> avatars;

  @override
  State<_SummonSheet> createState() => _SummonSheetState();
}

class _SummonSheetState extends State<_SummonSheet> {
  static const double _letterRowHeight = 26;
  static const double _contactRowHeight = 54;

  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[];
    final letters = <String>[];
    final offsets = <String, double>{};
    var y = 0.0;
    String? lastLetter;
    for (final character in widget.pool) {
      final letter = pinyinInitialOf(character.name);
      if (letter != lastLetter) {
        letters.add(letter);
        offsets[letter] = y;
        y += _letterRowHeight;
        tiles.add(_letter(letter));
        lastLetter = letter;
      }
      y += _contactRowHeight;
      tiles.add(_row(character));
    }

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
              child: Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      '召唤谁来回复这条',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: MomentColors.primaryText,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      '取消',
                      style: TextStyle(
                        fontSize: 14,
                        color: MomentColors.secondaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(
              height: 0.5,
              thickness: 0.5,
              color: MomentColors.hairline,
            ),
            Expanded(
              child: Stack(
                children: <Widget>[
                  // 右边留出一条给字母条，不然会盖住字。
                  ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.only(right: 22, bottom: 12),
                    children: tiles,
                  ),
                  if (letters.length > 2)
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: _indexBar(letters, offsets),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _letter(String letter) {
    return Container(
      height: _letterRowHeight,
      color: const Color(0xFFF4F5F7),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      alignment: Alignment.centerLeft,
      child: Text(
        letter,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
          color: MomentColors.secondaryText,
        ),
      ),
    );
  }

  Widget _row(MomentCharacter character) {
    final name = character.name.trim();
    return SizedBox(
      height: _contactRowHeight,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(18, 0, 8, 0),
        child: InkWell(
          onTap: () => Navigator.of(context).pop(name),
          child: Row(
            children: <Widget>[
              MomentAvatar(
                name: name,
                size: 34,
                imagePath: widget.avatars[name]?.avatar,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    color: MomentColors.primaryText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 右侧那一竖排 A、B、C……，点一下滚到对应分组。
  Widget _indexBar(List<String> letters, Map<String, double> offsets) {
    return Center(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0x0D000000),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final letter in letters)
                GestureDetector(
                  onTap: () => _jumpTo(letter, offsets),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 1.2,
                    ),
                    child: Text(
                      letter,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: MomentColors.secondaryText,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _jumpTo(String letter, Map<String, double> offsets) {
    if (!_scroll.hasClients) return;
    final target = offsets[letter];
    if (target == null) return;
    final max = _scroll.position.maxScrollExtent;
    _scroll.animateTo(
      target.clamp(0.0, max).toDouble(),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }
}
