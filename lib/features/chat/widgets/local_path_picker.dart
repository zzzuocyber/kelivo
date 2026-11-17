import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/custom_bottom_sheet.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../workspace/widgets/files/file_browser.dart';

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
  return showCustomBottomSheet<String>(
    context: context,
    title: title,
    partialHeightFactor: 0.9,
    expandedHeightFactor: 0.9,
    closeSemanticLabel: l10n.workspacePreviewBack,
    builder: (sheetCtx, scrollController) {
      final pickingFolder = kind == LocalPathKind.folder;
      return FileBrowser(
        root: root,
        rootLabel: '手机存储',
        modelPathOf: (host) => host,
        readOnly: true,
        scrollController: scrollController,
        pickDirectoryMode: pickingFolder,
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
      );
    },
  );
}
