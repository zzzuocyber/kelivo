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

  @override
  void initState() {
    super.initState();
    _store = MomentStore(context.read<ChatService>());
    _load();
  }

  void _load() {
    final conversation = _store.findConversation();
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
        body: Column(
          children: <Widget>[
            MomentCover(
              name: widget.author,
              subtitle: '${_posts.length} 条动态',
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: const BoxDecoration(
                  color: MomentColors.card,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                ),
                child: _posts.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
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
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 16),
                        itemCount: _posts.length,
                        itemBuilder: (_, index) =>
                            MomentPostCard(post: _posts[index]),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
