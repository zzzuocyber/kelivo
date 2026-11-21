import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../core/models/workspace.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/custom_bottom_sheet.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../workspace/widgets/files/file_browser.dart';
import 'local_path_picker.dart' show LocalPathKind, isLocalImagePath;

/// Picks a path inside a bound workspace and returns it in the model's
/// vocabulary: a path relative to the workspace root, e.g. `素材库/图.png`.
///
/// The caller decides how to render it:
/// - chat composer images need a `kelivo://workspace/...` link so the chat
///   bubble resolves it to a real file (a bare `/workspace/...` is a broken
///   image outside layers blocks);
/// - prompt fields need dead `/workspace/...` text for layer stacking.
///
/// Only the in-app FileBrowser is used, read-only, mirroring the local path
/// picker. Android-only at the call sites, like its local counterpart.
Future<String?> pickWorkspacePath(
  BuildContext context, {
  required LocalPathKind kind,
  required Workspace workspace,
}) async {
  final hostPath = workspace.hostPath;
  if (hostPath == null || hostPath.isEmpty) {
    showAppSnackBar(
      context,
      message: '这个工作区没有可用的文件夹路径',
      type: NotificationType.error,
    );
    return null;
  }
  final root = Directory(hostPath);
  try {
    if (!root.existsSync()) {
      showAppSnackBar(
        context,
        message: '工作区文件夹不存在：$hostPath',
        type: NotificationType.error,
      );
      return null;
    }
    await root.list(followLinks: false).take(1).toList();
  } catch (_) {
    showAppSnackBar(
      context,
      message: '读不到工作区文件夹：$hostPath',
      type: NotificationType.error,
    );
    return null;
  }

  final l10n = AppLocalizations.of(context)!;
  final title = switch (kind) {
    LocalPathKind.image => '选择工作区图片',
    LocalPathKind.file => '选择工作区文件',
    LocalPathKind.folder => '选择工作区文件夹',
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
        rootLabel: workspace.name,
        // Return the model-visible path (relative to the workspace root), not
        // the host path, so callers can build /workspace and kelivo links.
        modelPathOf: (host) => _relativeToWorkspace(host, hostPath),
        readOnly: true,
        scrollController: scrollController,
        pickDirectoryMode: pickingFolder,
        onPickDirectory: pickingFolder
            ? (relative) => Navigator.of(sheetCtx).pop(relative)
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
                Navigator.of(
                  sheetCtx,
                ).pop(_relativeToWorkspace(file.path, hostPath));
              },
      );
    },
  );
}

/// Workspace-relative model path using forward slashes, no leading slash.
String _relativeToWorkspace(String hostPath, String rootPath) {
  final relative = p.relative(hostPath, from: rootPath);
  return relative.replaceAll(r'\', '/');
}

/// Text inserted into the chat composer for a picked workspace path.
///
/// Images use a `kelivo://workspace/...` markdown link so the chat bubble
/// resolves and displays the real image. Files and folders are dead
/// `/workspace/...` text (no upload, model-readable).
String workspaceChatInsertion(LocalPathKind kind, String relativePath) {
  final clean = relativePath.replaceAll(r'\', '/');
  if (kind == LocalPathKind.image) {
    return '![](kelivo://workspace/$clean)';
  }
  return '/workspace/$clean';
}

/// Text inserted into a prompt field (system prompt / world book / injection).
///
/// Images are dead `/workspace/...` paths wrapped in the layer-stack tag form
/// `![240](/workspace/...)`. The caller selects `240` so it can be typed over
/// with a real height number or L/C/R placement without retyping the wrapper.
String workspacePromptInsertion(LocalPathKind kind, String relativePath) {
  final clean = relativePath.replaceAll(r'\', '/');
  if (kind == LocalPathKind.image) {
    return '![240](/workspace/$clean)';
  }
  return '/workspace/$clean';
}

/// Same as [workspacePromptInsertion] but for a local absolute path, used by
/// the local path group inside prompt fields.
String localPromptInsertion(LocalPathKind kind, String absolutePath) {
  if (kind == LocalPathKind.image) {
    return '![240]($absolutePath)';
  }
  return absolutePath;
}
