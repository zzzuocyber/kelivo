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
        appBar: AppBar(titleSpacing: 0, title: const SizedBox.shrink()),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 12),
          children: <Widget>[
            MomentAuthorHeader(name: widget.author, postCount: _posts.length),
            if (_posts.isEmpty)
              const Padding(
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
              ),
            for (final post in _posts) MomentPostCard(post: post),
          ],
        ),
      ),
    );
  }
}
