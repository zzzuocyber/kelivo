import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/services/chat/chat_service.dart';
import 'moment_models.dart';
import 'moment_store.dart';
import 'moment_widgets.dart';

/// 点帖子上的头像进来：只看这个人自己发的动态。
/// 长按他的头像 → 弹「发布」→ 替他发一条（写的是你，署名是他）。
class MomentAuthorPage extends StatefulWidget {
  const MomentAuthorPage({super.key, required this.author});

  final String author;

  @override
  State<MomentAuthorPage> createState() => _MomentAuthorPageState();
}

class _MomentAuthorPageState extends State<MomentAuthorPage> {
  late final MomentStore _store;
  List<MomentPost> _posts = const <MomentPost>[];
  MomentAssets _assets = const MomentAssets();

  /// 我自己的马甲名。主页上这一位是自己，不给代发。
  String _persona = '我';

  @override
  void initState() {
    super.initState();
    _store = MomentStore(context.read<ChatService>());
    _load();
  }

  void _load() {
    final conversation = _store.findConversation();
    final persona = context.read<SettingsProvider>().momentPersonaName.trim();
    _persona = persona.isEmpty ? '我' : persona;
    _assets =
        momentAssetsForAuthor(
          momentAssetsOf(conversation),
          widget.author,
          _persona,
        ) ??
        const MomentAssets();
    final posts = <MomentPost>[...momentPostsOf(conversation)]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _posts = posts
        .where((p) => p.author == widget.author)
        .toList(growable: false);
  }

  bool get _canPost => widget.author.trim() != _persona;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: momentLightTheme(),
      child: Scaffold(
        backgroundColor: MomentColors.card,
        body: Stack(
          children: <Widget>[
            ListView(
              padding: EdgeInsets.zero,
              children: <Widget>[
                MomentCover(coverPath: _assets.cover),
                MomentPanel(
                  avatarName: widget.author,
                  avatarPath: _assets.avatar,
                  onLongPressAvatar: _canPost ? _showAvatarMenu : null,
                  child: _posts.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 60),
                          child: Center(
                            child: Text(
                              '还没有动态',
                              style: TextStyle(
                                fontSize: 14,
                                color: MomentColors.secondaryText,
                              ),
                            ),
                          ),
                        )
                      : Column(
                          children: <Widget>[
                            for (final post in _posts)
                              MomentPostCard(
                                post: post,
                                avatarPath: _assets.avatar,
                              ),
                            const SizedBox(height: 24),
                          ],
                        ),
                ),
              ],
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: MomentTopBar(
                onBack: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 贴着手指弹的小菜单，只有「发布」这一项。
  Future<void> _showAvatarMenu(Offset position) async {
    final size = MediaQuery.sizeOf(context);
    final left = position.dx > size.width / 2 ? position.dx - 150 : position.dx;
    final action = await showMenu<String>(
      context: context,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      position: RelativeRect.fromLTRB(
        left,
        position.dy,
        size.width - left - 140,
        size.height - position.dy,
      ),
      items: const <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: '发布',
          height: 44,
          child: Text(
            '发布',
            style: TextStyle(fontSize: 14, color: MomentColors.primaryText),
          ),
        ),
      ],
    );
    if (action != '发布' || !mounted) return;
    await _composeAsAuthor();
  }

  /// 替这个角色发一条：字是你写的，署名和头像是他。
  Future<void> _composeAsAuthor() async {
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
          author: widget.author,
          createdAt: DateTime.now(),
          text: text,
          hasImage: result.withImage,
        ),
      );
      if (!mounted) return;
      setState(_load);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('没发出去，再试一次'),
            duration: Duration(seconds: 3),
          ),
        );
    }
  }
}
