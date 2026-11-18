import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/services/chat/chat_service.dart';
import '../../icons/lucide_adapter.dart';
import '../../utils/avatar_files.dart';
import 'moment_models.dart';
import 'moment_store.dart';
import 'moment_widgets.dart';

/// 角色管理：给每个角色（还有我的马甲）换头像和背景图。
/// 图会复制进 Kelivo 的 avatars 目录，也就是图片页里的「头像与背景」分类。
class MomentAssetsPage extends StatefulWidget {
  const MomentAssetsPage({super.key});

  @override
  State<MomentAssetsPage> createState() => _MomentAssetsPageState();
}

class _MomentAssetsPageState extends State<MomentAssetsPage> {
  late final MomentStore _store;
  List<MomentCharacter> _characters = const <MomentCharacter>[];
  Map<String, MomentAssets> _assets = const <String, MomentAssets>{};
  String _persona = '我';

  @override
  void initState() {
    super.initState();
    _store = MomentStore(context.read<ChatService>());
    _reload();
  }

  void _reload() {
    final conversation = _store.findConversation();
    _characters = momentCharactersOf(conversation);
    _assets = momentAssetsOf(conversation);
    final name = context.read<SettingsProvider>().momentPersonaName.trim();
    _persona = name.isEmpty ? '我' : name;
  }

  Future<void> _edit(String key, String name) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _AssetSheet(
        store: _store,
        assetKey: key,
        name: name,
        initial: _assets[key] ?? const MomentAssets(),
      ),
    );
    if (!mounted) return;
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: momentLightTheme(),
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: const Text(
            '角色管理',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(vertical: 6),
          children: <Widget>[
            _row(key: MomentAssets.personaKey, name: _persona, label: '我的马甲'),
            for (final character in _characters)
              _row(key: character.name, name: character.name),
          ],
        ),
      ),
    );
  }

  Widget _row({required String key, required String name, String? label}) {
    final assets = _assets[key] ?? const MomentAssets();
    final path = (assets.avatar ?? '').trim();
    return InkWell(
      onTap: () => _edit(key, name),
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: <Widget>[
            MomentAvatar(name: name, size: 44, imagePath: path),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 15,
                      color: MomentColors.primaryText,
                    ),
                  ),
                  if (label != null)
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: MomentColors.secondaryText,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              assets.cover == null ? Lucide.ImageOff : Lucide.Image,
              size: 16,
              color: MomentColors.secondaryText,
            ),
            const SizedBox(width: 8),
            const Icon(
              Lucide.ChevronRight,
              size: 16,
              color: MomentColors.secondaryText,
            ),
          ],
        ),
      ),
    );
  }
}

class _AssetSheet extends StatefulWidget {
  const _AssetSheet({
    required this.store,
    required this.assetKey,
    required this.name,
    required this.initial,
  });

  final MomentStore store;
  final String assetKey;
  final String name;
  final MomentAssets initial;

  @override
  State<_AssetSheet> createState() => _AssetSheetState();
}

class _AssetSheetState extends State<_AssetSheet> {
  late String? _avatar = widget.initial.avatar;
  late String? _cover = widget.initial.cover;
  bool _busy = false;

  Future<void> _pickAvatar() async {
    final path = await _pick();
    if (path == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final stored = await importAvatarFile(path);
      await widget.store.saveAssets(widget.assetKey, avatar: stored);
      if (!mounted) return;
      setState(() {
        _avatar = stored;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast('头像没存上，再试一次');
    }
  }

  Future<void> _pickCover() async {
    final path = await _pick();
    if (path == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final stored = await importAvatarFile(path);
      await widget.store.saveAssets(widget.assetKey, cover: stored);
      if (!mounted) return;
      setState(() {
        _cover = stored;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast('背景图没存上，再试一次');
    }
  }

  Future<String?> _pick() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        imageQuality: 85,
      );
      return file?.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _removeAvatar() async {
    await widget.store.saveAssets(widget.assetKey, clearAvatar: true);
    if (!mounted) return;
    setState(() => _avatar = null);
  }

  Future<void> _removeCover() async {
    await widget.store.saveAssets(widget.assetKey, clearCover: true);
    if (!mounted) return;
    setState(() => _cover = null);
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final avatarPath = (_avatar ?? '').trim();
    final coverPath = (_cover ?? '').trim();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              widget.name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: MomentColors.primaryText,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                MomentAvatar(
                  name: widget.name,
                  size: 64,
                  imagePath: avatarPath,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        '头像',
                        style: TextStyle(
                          fontSize: 13,
                          color: MomentColors.secondaryText,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: <Widget>[
                          _action('换一张', _busy ? null : _pickAvatar),
                          if (avatarPath.isNotEmpty)
                            _action('移除', _busy ? null : _removeAvatar),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '背景图',
              style: TextStyle(fontSize: 13, color: MomentColors.secondaryText),
            ),
            const SizedBox(height: 8),
            AspectRatio(
              aspectRatio: coverPath.isEmpty ? 4 / 3 : 16 / 7,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: coverPath.isEmpty
                    ? Container(
                        color: const Color(0xFFF4F5F7),
                        alignment: Alignment.center,
                        child: const Text(
                          '还没设置',
                          style: TextStyle(
                            fontSize: 13,
                            color: MomentColors.secondaryText,
                          ),
                        ),
                      )
                    : Image.file(
                        File(coverPath),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: const Color(0xFFF4F5F7),
                          alignment: Alignment.center,
                          child: const Text(
                            '图片读不到',
                            style: TextStyle(
                              fontSize: 13,
                              color: MomentColors.secondaryText,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                _action('换一张', _busy ? null : _pickCover),
                if (coverPath.isNotEmpty)
                  _action('移除', _busy ? null : _removeCover),
                const Spacer(),
                if (_busy)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _action(String label, VoidCallback? onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: MomentColors.hairline),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: onTap == null
                  ? MomentColors.secondaryText
                  : MomentColors.name,
            ),
          ),
        ),
      ),
    );
  }
}
