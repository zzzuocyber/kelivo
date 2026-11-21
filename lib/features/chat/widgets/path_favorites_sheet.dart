import 'dart:io';

import 'package:flutter/material.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../theme/app_font_weights.dart';
import '../../../core/services/path_picker_store.dart';
import '../../workspace/widgets/files/file_browser.dart';

/// 路径选择器标题行那个书签按钮点开的收藏夹。
///
/// 一个面板里做三件事：收藏当前文件夹、点已收藏目录跳转、取消收藏。
/// [currentDir] 由 FileBrowser 的 onDirectoryChanged 持续更新，
/// 所以「收藏当前」永远存的是用户此刻看着的那个目录。
Future<void> showPathFavoritesSheet({
  required BuildContext context,
  required String scope,
  required Directory root,
  required String rootLabel,
  required ValueNotifier<String> currentDir,
  required GlobalKey<FileBrowserState> browserKey,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _FavoritesSheet(
      scope: scope,
      root: root,
      rootLabel: rootLabel,
      currentDir: currentDir,
      browserKey: browserKey,
    ),
  );
}

class _FavoritesSheet extends StatefulWidget {
  const _FavoritesSheet({
    required this.scope,
    required this.root,
    required this.rootLabel,
    required this.currentDir,
    required this.browserKey,
  });

  final String scope;
  final Directory root;
  final String rootLabel;
  final ValueNotifier<String> currentDir;
  final GlobalKey<FileBrowserState> browserKey;

  @override
  State<_FavoritesSheet> createState() => _FavoritesSheetState();
}

class _FavoritesSheetState extends State<_FavoritesSheet> {
  late Future<List<String>> _favorites;

  @override
  void initState() {
    super.initState();
    _favorites = PathPickerStore.instance.favorites(widget.scope);
  }

  Future<void> _reload() async {
    final value = await PathPickerStore.instance.favorites(widget.scope);
    if (!mounted) return;
    setState(() => _favorites = Future<List<String>>.value(value));
  }

  /// 收藏 / 取消收藏当前目录。
  Future<void> _toggleCurrent() async {
    final current = widget.currentDir.value;
    await PathPickerStore.instance.toggleFavorite(widget.scope, current);
    await _reload();
  }

  Future<void> _remove(String relative) async {
    // toggle 会对已存在的项做移除；先确认它确实在列表里，避免误加。
    final list = await PathPickerStore.instance.favorites(widget.scope);
    if (list.contains(relative)) {
      await PathPickerStore.instance.toggleFavorite(widget.scope, relative);
    }
    await _reload();
  }

  void _jump(String relative) {
    // 先关收藏夹，再让底下的 FileBrowser 跳过去。
    Navigator.of(context).pop();
    widget.browserKey.currentState?.jumpToRelative(relative);
  }

  String _label(String relative) {
    if (relative.isEmpty) return widget.rootLabel;
    return relative.split('/').last;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '收藏夹',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: AppFontWeights.emphasis,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  IosIconButton(
                    icon: Lucide.X,
                    size: 18,
                    padding: EdgeInsets.zero,
                    color: cs.onSurface.withValues(alpha: 0.62),
                    semanticLabel: '关闭',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // 「收藏当前文件夹」永远排第一，跟着当前目录实时变文案。
            ValueListenableBuilder<String>(
              valueListenable: widget.currentDir,
              builder: (context, current, _) {
                return FutureBuilder<List<String>>(
                  future: _favorites,
                  builder: (context, snapshot) {
                    final saved = snapshot.data ?? const <String>[];
                    final isSaved = saved.contains(current);
                    return ListTile(
                      leading: Icon(
                        isSaved ? Lucide.Bookmark : Lucide.Bookmark,
                        size: 20,
                        color: isSaved ? cs.primary : cs.onSurface,
                      ),
                      title: Text(
                        isSaved ? '取消收藏当前文件夹' : '收藏当前文件夹',
                        style: TextStyle(fontSize: 14, color: cs.onSurface),
                      ),
                      subtitle: Text(
                        '${widget.rootLabel}${current.isEmpty ? '' : '/$current'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      onTap: _toggleCurrent,
                    );
                  },
                );
              },
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<String>>(
                future: _favorites,
                builder: (context, snapshot) {
                  final list = snapshot.data ?? const <String>[];
                  if (list.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Center(
                        child: Text(
                          '还没有收藏，点上面把当前文件夹存进来',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: cs.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final relative = list[index];
                      return ListTile(
                        leading: Icon(
                          Lucide.Folder,
                          size: 20,
                          color: cs.onSurface.withValues(alpha: 0.75),
                        ),
                        title: Text(
                          _label(relative),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, color: cs.onSurface),
                        ),
                        subtitle: relative.isEmpty
                            ? null
                            : Text(
                                relative,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: cs.onSurface.withValues(alpha: 0.55),
                                ),
                              ),
                        onTap: () => _jump(relative),
                        trailing: SizedBox(
                          width: 32,
                          height: 32,
                          child: IosIconButton(
                            icon: Lucide.Bookmark,
                            size: 17,
                            padding: EdgeInsets.zero,
                            color: cs.primary,
                            semanticLabel: '取消收藏',
                            onTap: () => _remove(relative),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
