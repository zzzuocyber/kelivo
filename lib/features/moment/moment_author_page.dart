import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/chat/chat_service.dart';
import 'moment_models.dart';
import 'moment_store.dart';
import 'moment_widgets.dart';

/// 点帖子上的头像进来：只看这个人自己发的动态。
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

  @override
  void initState() {
    super.initState();
    _store = MomentStore(context.read<ChatService>());
    _load();
  }

  void _load() {
    final conversation = _store.findConversation();
    _assets =
        momentAssetsOf(conversation)[widget.author] ?? const MomentAssets();
    final posts = <MomentPost>[...momentPostsOf(conversation)]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _posts = posts
        .where((p) => p.author == widget.author)
        .toList(growable: false);
  }

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
                MomentCover(
                  name: widget.author,
                  subtitle: '${_posts.length} 条动态',
                  avatarPath: _assets.avatar,
                  coverPath: _assets.cover,
                ),
                Container(
                  decoration: const BoxDecoration(
                    color: MomentColors.card,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(18),
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Color(0x1F000000),
                        blurRadius: 18,
                        offset: Offset(0, -6),
                      ),
                    ],
                  ),
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
}
