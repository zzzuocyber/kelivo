import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart' as lucide;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../core/database/chat_database_repository.dart'
    show ComposerAssetEntry;
import '../../../core/models/chat_input_data.dart';
import '../../../core/services/api/chat_api_helpers.dart' show mimeFromPath;
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';
import '../../../theme/app_semantic_colors.dart';

enum _AssetKind { images, files }

/// Picker over attachments that earlier messages already used, so they can be
/// sent again without uploading a second copy. Files pasted as text
/// (`pasted_*.txt`) and anything the AI wrote outside the chat upload folder are
/// deliberately absent.
Future<void> showComposerAssetPicker(
  BuildContext context, {
  required String conversationId,
  required ValueChanged<List<String>> onInsertImages,
  required ValueChanged<List<DocumentAttachment>> onInsertDocuments,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.overlaySurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _AssetPickerSheet(
      conversationId: conversationId,
      onInsertImages: onInsertImages,
      onInsertDocuments: onInsertDocuments,
    ),
  );
}

class _AssetItem {
  _AssetItem({
    required this.entry,
    required this.title,
    required this.subtitle,
  });

  final ComposerAssetEntry entry;
  final String title;
  final String subtitle;
}

class _AssetPickerSheet extends StatefulWidget {
  const _AssetPickerSheet({
    required this.conversationId,
    required this.onInsertImages,
    required this.onInsertDocuments,
  });

  final String conversationId;
  final ValueChanged<List<String>> onInsertImages;
  final ValueChanged<List<DocumentAttachment>> onInsertDocuments;

  @override
  State<_AssetPickerSheet> createState() => _AssetPickerSheetState();
}

class _AssetPickerSheetState extends State<_AssetPickerSheet> {
  static const int _limit = 400;

  _AssetKind _tab = _AssetKind.images;
  final Map<_AssetKind, List<_AssetItem>> _items = {};
  final Map<_AssetKind, Set<String>> _selected = {
    _AssetKind.images: <String>{},
    _AssetKind.files: <String>{},
  };
  final Set<_AssetKind> _loading = <_AssetKind>{};

  @override
  void initState() {
    super.initState();
    _load(_AssetKind.images);
  }

  Future<void> _load(_AssetKind kind) async {
    if (_items.containsKey(kind) || _loading.contains(kind)) return;
    setState(() => _loading.add(kind));
    final chat = context.read<ChatService>();
    List<_AssetItem> loaded = const [];
    try {
      final entries = await chat.listComposerAssets(
        kind: kind == _AssetKind.images ? 'image' : 'file',
        limit: _limit,
      );
      final items = <_AssetItem>[];
      for (final entry in entries) {
        final name = p.basename(entry.path);
        if (name.isEmpty) continue;
        if (kind == _AssetKind.files && name.startsWith('pasted_')) continue;
        if (!await File(entry.path).exists()) continue;
        final conversationId = entry.conversationId;
        final title = conversationId == null
            ? ''
            : (chat.getConversation(conversationId)?.title.trim() ?? '');
        items.add(
          _AssetItem(
            entry: entry,
            title: name,
            subtitle: title.isEmpty ? '对话已删除' : title,
          ),
        );
      }
      loaded = items;
    } catch (_) {
      loaded = const [];
    }
    if (!mounted) return;
    setState(() {
      _items[kind] = loaded;
      _loading.remove(kind);
    });
  }

  void _switchTab(_AssetKind kind) {
    if (_tab == kind) return;
    Haptics.light();
    setState(() => _tab = kind);
    _load(kind);
  }

  void _toggle(_AssetItem item) {
    Haptics.light();
    final set = _selected[_tab]!;
    setState(() {
      if (!set.remove(item.entry.path)) set.add(item.entry.path);
    });
  }

  int get _selectedCount =>
      _selected[_AssetKind.images]!.length +
      _selected[_AssetKind.files]!.length;

  void _insert() {
    final images = _selected[_AssetKind.images]!.toList(growable: false);
    final files = _selected[_AssetKind.files]!
        .map(
          (path) => DocumentAttachment(
            path: path,
            fileName: p.basename(path),
            mime: mimeFromPath(path),
          ),
        )
        .toList(growable: false);
    if (images.isNotEmpty) widget.onInsertImages(images);
    if (files.isNotEmpty) widget.onInsertDocuments(files);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final height = MediaQuery.sizeOf(context).height * 0.78;
    final items = _items[_tab];
    final loading = _loading.contains(_tab);

    return SafeArea(
      top: false,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Lucide.Library,
                    size: 20,
                    color: cs.onSurface.withValues(alpha: 0.8),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '资产',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: AppFontWeights.semibold,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(
                      Lucide.X,
                      size: 20,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _TabPill(
                    label: '图片',
                    active: _tab == _AssetKind.images,
                    onTap: () => _switchTab(_AssetKind.images),
                  ),
                  const SizedBox(width: 8),
                  _TabPill(
                    label: '文件',
                    active: _tab == _AssetKind.files,
                    onTap: () => _switchTab(_AssetKind.files),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: loading
                    ? const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : items == null || items.isEmpty
                    ? Center(
                        child: Text(
                          _tab == _AssetKind.images ? '还没有用过的图片' : '还没有用过的文件',
                          style: TextStyle(
                            fontSize: 14,
                            color: cs.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                      )
                    : ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final selected = _selected[_tab]!.contains(
                            item.entry.path,
                          );
                          return _AssetRow(
                            item: item,
                            isImage: _tab == _AssetKind.images,
                            selected: selected,
                            onTap: () => _toggle(item),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 46,
                child: FilledButton(
                  onPressed: _selectedCount == 0 ? null : _insert,
                  child: Text(
                    _selectedCount == 0 ? '选择要插入的资产' : '插入（$_selectedCount）',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? cs.primary.withValues(alpha: 0.14)
              : cs.onSurface.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: active
                ? AppFontWeights.semibold
                : AppFontWeights.medium,
            color: active ? cs.primary : cs.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}

class _AssetRow extends StatelessWidget {
  const _AssetRow({
    required this.item,
    required this.isImage,
    required this.selected,
    required this.onTap,
  });

  final _AssetItem item;
  final bool isImage;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final preview = isImage
        ? (item.entry.thumbnailPath ?? item.entry.path)
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: selected
                ? cs.primary.withValues(alpha: 0.12)
                : cs.onSurface.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? cs.primary.withValues(alpha: 0.55)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: preview == null
                      ? Container(
                          color: cs.onSurface.withValues(alpha: 0.06),
                          child: Icon(
                            Lucide.FileText,
                            size: 22,
                            color: cs.onSurface.withValues(alpha: 0.55),
                          ),
                        )
                      : Image.file(
                          File(preview),
                          fit: BoxFit.cover,
                          cacheWidth: 144,
                          errorBuilder: (errorContext, error, stack) =>
                              Container(
                                color: cs.onSurface.withValues(alpha: 0.06),
                                child: Icon(
                                  Lucide.Image,
                                  size: 22,
                                  color: cs.onSurface.withValues(alpha: 0.55),
                                ),
                              ),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: cs.onSurface.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected ? Lucide.CheckCircle : lucide.LucideIcons.circle,
                size: 20,
                color: selected
                    ? cs.primary
                    : cs.onSurface.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
