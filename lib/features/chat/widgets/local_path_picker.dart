import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../core/services/path_picker_store.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/custom_bottom_sheet.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../workspace/widgets/files/file_browser.dart';
import 'path_favorites_sheet.dart' show showPathFavoritesSheet;

/// Root shown by the local path pickers. Android exposes shared storage here;
/// the app holds MANAGE_EXTERNAL_STORAGE, so dart:io can walk it directly.
///
/// The system file picker is deliberately not used: it hands back a content
/// URI plus a copy inside the app cache, never the real path.
const String kLocalPathBrowseRoot = '/storage/emulated/0';

/// What the user asked to insert.
enum LocalPathKind { image, file, folder }

/// Extensions the chat renderer can actually display inline.
bool isLocalImagePath(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.bmp') ||
      lower.endsWith('.heic') ||
      lower.endsWith('.heif');
}

/// Text inserted into the composer for a picked path.
///
/// Images use Markdown so the chat renders them without uploading anything;
/// Markdown image destinations keep spaces and CJK characters intact.
String localPathInsertion(LocalPathKind kind, String path) {
  return kind == LocalPathKind.image ? '![]($path)' : path;
}

/// True when the directory exists and can actually be listed.
///
/// Without "all files access" Android still answers existsSync for the root but
/// returns an empty listing, which would look like an empty folder.
Future<bool> _canRead(Directory directory) async {
  try {
    if (!directory.existsSync()) return false;
    await directory.list(followLinks: false).take(1).toList();
    return true;
  } catch (_) {
    return false;
  }
}

/// Opens the in-app browser rooted at [kLocalPathBrowseRoot] and returns an
/// absolute path, or null when the user backs out.
Future<String?> pickLocalPath(
  BuildContext context, {
  required LocalPathKind kind,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final root = Directory(kLocalPathBrowseRoot);
  if (!await _canRead(root)) {
    showAppSnackBar(
      context,
      message: '读不到手机存储：请到系统设置里给 Kelivo 开启「所有文件访问」',
      type: NotificationType.error,
    );
    return null;
  }
  final title = switch (kind) {
    LocalPathKind.image => '选择图片',
    LocalPathKind.file => '选择文件',
    LocalPathKind.folder => '选择文件夹',
  };
  const rootLabel = '手机存储';
  final scope = PathPickerStore.localScope(kLocalPathBrowseRoot);
  final store = PathPickerStore.instance;
  // 上次停留的目录，作为这次打开的起点；失效目录 FileBrowser 会自己忽略。
  final lastRel = await store.lastDir(scope);
  final currentDir = ValueNotifier<String>(lastRel ?? '');
  final browserKey = GlobalKey<FileBrowserState>();

  return showCustomBottomSheet<String>(
    context: context,
    title: title,
    partialHeightFactor: 0.9,
    expandedHeightFactor: 0.9,
    closeSemanticLabel: l10n.workspacePreviewBack,
    headerActions: [
      Builder(
        builder: (ctx) => SizedBox(
          width: 24,
          height: 24,
          child: Tooltip(
            message: '收藏夹',
            child: IosIconButton(
              icon: Lucide.Bookmark,
              size: 18,
              padding: EdgeInsets.zero,
              color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.62),
              semanticLabel: '收藏夹',
              onTap: () => showPathFavoritesSheet(
                context: ctx,
                scope: scope,
                root: root,
                rootLabel: rootLabel,
                currentDir: currentDir,
                browserKey: browserKey,
              ),
            ),
          ),
        ),
      ),
    ],
    builder: (sheetCtx, scrollController) {
      final pickingFolder = kind == LocalPathKind.folder;
      return PathPickerDisposeGuard(
        onDispose: currentDir.dispose,
        child: FileBrowser(
          key: browserKey,
          root: root,
          rootLabel: rootLabel,
          modelPathOf: (host) => host,
          readOnly: true,
          scrollController: scrollController,
          pickDirectoryMode: pickingFolder,
          initialRelativePath: lastRel,
          onDirectoryChanged: (relative) {
            currentDir.value = relative;
            unawaited(store.setLastDir(scope, relative));
          },
          onPickDirectory: pickingFolder
              ? (relative) => Navigator.of(
                  sheetCtx,
                ).pop(p.posix.join(kLocalPathBrowseRoot, relative))
              : null,
          onOpenFile: pickingFolder
              ? null
              : (file) async {
                  if (kind == LocalPathKind.image &&
                      !isLocalImagePath(file.path)) {
                    showAppSnackBar(
                      sheetCtx,
                      message: '这不是图片文件，请重新选择',
                      type: NotificationType.warning,
                    );
                    return;
                  }
                  Navigator.of(sheetCtx).pop(file.path);
                },
        ),
      );
    },
  );
}

/// sheet 关闭时释放函数作用域里创建的 notifier，避免每次选择都泄漏一个。
class PathPickerDisposeGuard extends StatefulWidget {
  const PathPickerDisposeGuard({required this.onDispose, required this.child});

  final VoidCallback onDispose;
  final Widget child;

  @override
  State<PathPickerDisposeGuard> createState() => PathPickerDisposeGuardState();
}

class PathPickerDisposeGuardState extends State<PathPickerDisposeGuard> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
