import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:markstream/markstream.dart';
import 'package:provider/provider.dart';

import '../../core/services/chat/chat_service.dart';
import '../../core/services/workspace/file_link_resolver.dart';
import '../../features/workspace/workspace_file_navigation.dart';
import '../../icons/lucide_adapter.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/sandbox_path_resolver.dart';
import '../markdown/link_image_handlers.dart';

/// A stack of images for role-play scenes: transparent character PNGs layered
/// over a background. Syntax (one image per line, top line = frontmost):
///
/// ```
/// ![L](/storage/.../char_left.png)
/// ![C](/storage/.../char_center.png)
/// ![240](/workspace/scenes/room.webp)   <- last line = scene/canvas
/// ```
///
/// Tag: L/C/R = character (height fills the scene, width follows aspect,
/// aligned left/center/right). A number = the scene, that value is its height.
/// Empty tag on the last line = scene at natural aspect. Only local absolute
/// paths and workspace guest paths are accepted.
class LayeredImageBlock extends StatefulWidget {
  const LayeredImageBlock({
    super.key,
    required this.code,
    required this.lines,
    required this.theme,
  });

  final String code;
  final List<_LayerSpec> lines;
  final MarkstreamTheme theme;

  @override
  State<LayeredImageBlock> createState() => _LayeredImageBlockState();
}

enum _LayerAlign { left, center, right }

class _LayerSpec {
  const _LayerSpec({
    required this.path,
    this.align,
    this.sceneHeight,
  });

  final String path;
  final _LayerAlign? align;
  final double? sceneHeight;

  bool get isScene => align == null;
}

class _ResolvedLayer {
  const _ResolvedLayer(this.spec, this.file, this.aspect);
  final _LayerSpec spec;
  final File file;

  /// width / height of the decoded image.
  final double? aspect;
}

/// Parse the code body into layer specs. Returns null on any invalid line.
/// The last row is the scene; all earlier rows are L/C/R characters.
List<_LayerSpec>? parseLayeredImageBody(String body) {
  final rows = <_LayerSpec>[];
  for (final raw in body.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final m = RegExp(r'^!\[([^\]]*)\]\((.*)\)$').firstMatch(line);
    if (m == null) return null;
    final tag = m.group(1)!.trim();
    final path = m.group(2)!.trim();
    if (path.isEmpty || !_isAllowedPath(path)) return null;

    final num = double.tryParse(tag);
    if (num != null && num > 0 && num <= 10000) {
      rows.add(_LayerSpec(path: path, sceneHeight: num));
      continue;
    }
    if (tag.isEmpty) {
      // Allowed only as the scene row (enforced below).
      rows.add(_LayerSpec(path: path));
      continue;
    }
    final align = switch (tag.toUpperCase()) {
      'L' => _LayerAlign.left,
      'C' => _LayerAlign.center,
      'R' => _LayerAlign.right,
      _ => null,
    };
    if (align == null) return null;
    rows.add(_LayerSpec(path: path, align: align));
  }
  if (rows.isEmpty) return null;
  // Exactly one scene row, and it must be the last one.
  for (var i = 0; i < rows.length - 1; i++) {
    if (rows[i].isScene) return null;
  }
  if (!rows.last.isScene) return null;
  return rows;
}

bool _isAllowedPath(String path) {
  final lower = path.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) return false;
  if (lower.startsWith('data:')) return false;
  if (lower.startsWith('kelivo://')) return true;
  if (path.startsWith('/workspace/') || path == '/workspace') return true;
  if (path.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)) {
    return true;
  }
  return false;
}

class _LayeredImageBlockState extends State<LayeredImageBlock> {
  Future<List<_ResolvedLayer?>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _resolveAll(widget.lines);
  }

  @override
  void didUpdateWidget(covariant LayeredImageBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code) {
      _future = _resolveAll(widget.lines);
    }
  }

  Future<File?> _resolveOne(
    _LayerSpec spec,
    String? conversationId,
  ) async {
    final path = spec.path;
    if (path.startsWith('kelivo://') ||
        path.startsWith('/workspace/') ||
        path == '/workspace') {
      final link = path.startsWith('kelivo://')
          ? path
          : 'kelivo://workspace/${KelivoLink.encodePath(path == '/workspace' ? '' : path.substring('/workspace/'.length))}';
      return resolveWorkspaceLinkedFile(
        context,
        link,
        conversationId: conversationId,
      );
    }
    try {
      final file = File(SandboxPathResolver.fix(path));
      return file.existsSync() ? file : null;
    } catch (_) {
      return null;
    }
  }

  Future<double?> _readAspect(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final w = frame.image.width;
      final h = frame.image.height;
      frame.image.dispose();
      codec.dispose();
      if (w <= 0 || h <= 0) return null;
      return w / h;
    } catch (_) {
      return null;
    }
  }

  Future<List<_ResolvedLayer?>> _resolveAll(List<_LayerSpec> lines) async {
    // Read context-derived values synchronously, before any await.
    final conversationId = MarkdownLinkScope.read(context)?.conversationId ??
        context.read<ChatService?>()?.currentConversationId;
    final out = <_ResolvedLayer?>[];
    for (final spec in lines) {
      final file = await _resolveOne(spec, conversationId);
      if (file == null) {
        out.add(null);
        continue;
      }
      final aspect = await _readAspect(file);
      out.add(_ResolvedLayer(spec, file, aspect));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<List<_ResolvedLayer?>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final layers = snapshot.data;
        if (layers == null || layers.isEmpty || layers.last == null) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: widget.theme.colors.fillBlock,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Lucide.ImageOff, size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  l10n?.workspaceFileMissing ?? 'Scene image not found',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
              ],
            ),
          );
        }

        final scene = layers.last!;
        final characters = layers
            .take(layers.length - 1)
            .whereType<_ResolvedLayer>()
            .toList();

        return LayoutBuilder(
          builder: (context, constraints) {
            final maxW = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 360.0;
            final sceneAspect = scene.aspect ?? 4 / 3;
            double width;
            double height;
            final requested = scene.spec.sceneHeight;
            if (requested != null) {
              width = requested * sceneAspect;
              height = requested;
              if (width > maxW) {
                width = maxW;
                height = maxW / sceneAspect;
              }
            } else {
              width = maxW;
              height = maxW / sceneAspect;
            }
            return ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: width,
                height: height,
                child: _buildStack(scene, characters, width, height),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStack(
    _ResolvedLayer scene,
    List<_ResolvedLayer> characters,
    double width,
    double height,
  ) {
    final layers = <Widget>[
      Positioned.fill(
        child: Image.file(scene.file, fit: BoxFit.fill),
      ),
    ];
    for (final layer in characters) {
      layers.add(
        Positioned.fill(
          child: Align(
            alignment: switch (layer.spec.align!) {
              _LayerAlign.left => Alignment.centerLeft,
              _LayerAlign.center => Alignment.center,
              _LayerAlign.right => Alignment.centerRight,
            },
            child: Image.file(layer.file, height: height, fit: BoxFit.contain),
          ),
        ),
      );
    }
    return Stack(children: layers);
  }
}
