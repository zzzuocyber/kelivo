import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../utils/avatar_files.dart';
import '../../../utils/sandbox_path_resolver.dart';
import '../../core/services/chat/chat_service.dart';
import 'moment_phone_theme_store.dart';
import 'moment_widgets.dart';

/// 小手机桌面上的「设置」图标点进来。以后世界书之类的都挂这里，
/// 现在只有「主题」一项。
class MomentPhoneSettingsPage extends StatelessWidget {
  const MomentPhoneSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: momentLightTheme(),
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: const Text(
            '设置',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: <Widget>[
            _SettingsRow(
              icon: Lucide.Palette,
              label: '主题',
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const MomentPhoneThemePage(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 19, color: MomentColors.primaryText),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  color: MomentColors.primaryText,
                ),
              ),
            ),
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

/// 主题二级菜单：壁纸、深色/浅色、压暗程度。
class MomentPhoneThemePage extends StatefulWidget {
  const MomentPhoneThemePage({super.key});

  @override
  State<MomentPhoneThemePage> createState() => _MomentPhoneThemePageState();
}

class _MomentPhoneThemePageState extends State<MomentPhoneThemePage> {
  late final PhoneThemeStore _store;
  late PhoneTheme _theme;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _store = PhoneThemeStore(context.read<ChatService>());
    _theme = _store.read();
  }

  Future<void> _pickWallpaper() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        imageQuality: 88,
      );
      if (file == null || !mounted) return;
      // 存进 avatars 目录（小手机图片那一类）。文件名前缀沿用 importAvatarFile，
      // 分类靠「路径出现在 moment. 前缀的 extras 里」判定，不看文件名。
      final stored = await importAvatarFile(file.path);
      await _store.setWallpaper(stored);
      if (!mounted) return;
      setState(() {
        _theme = PhoneTheme(
          wallpaperPath: stored,
          dark: _theme.dark,
          dim: _theme.dim,
        );
      });
    } catch (_) {
      // 选图失败就保持原样，不打扰用户。
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _clearWallpaper() async {
    await _store.clearWallpaper();
    if (!mounted) return;
    setState(() {
      _theme = PhoneTheme(
        wallpaperPath: '',
        dark: _theme.dark,
        dim: _theme.dim,
      );
    });
  }

  Future<void> _setDark(bool dark) async {
    await _store.setDark(dark);
    if (!mounted) return;
    setState(() {
      _theme = PhoneTheme(
        wallpaperPath: _theme.wallpaperPath,
        dark: dark,
        dim: _theme.dim,
      );
    });
  }

  Future<void> _setDim(double dim) async {
    setState(() {
      _theme = PhoneTheme(
        wallpaperPath: _theme.wallpaperPath,
        dark: _theme.dark,
        dim: dim,
      );
    });
    await _store.setDim(dim);
  }

  @override
  Widget build(BuildContext context) {
    final hasWallpaper = _theme.wallpaperPath.isNotEmpty &&
        File(SandboxPathResolver.fix(_theme.wallpaperPath)).existsSync();

    return Theme(
      data: momentLightTheme(),
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: const Text(
            '主题',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: <Widget>[
            // 壁纸预览 + 选择 / 移除
            Container(
              color: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    '壁纸',
                    style: TextStyle(
                      fontSize: 15,
                      color: MomentColors.primaryText,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 132,
                      width: double.infinity,
                      color: const Color(0xFFEFF1F5),
                      child: hasWallpaper
                          ? Image.file(
                              File(
                                SandboxPathResolver.fix(
                                  _theme.wallpaperPath,
                                ),
                              ),
                              fit: BoxFit.cover,
                            )
                          : const Center(
                              child: Text(
                                '未设置壁纸',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: MomentColors.secondaryText,
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _picking ? null : _pickWallpaper,
                          icon: const Icon(Lucide.Image, size: 16),
                          label: Text(hasWallpaper ? '更换壁纸' : '选择壁纸'),
                        ),
                      ),
                      if (hasWallpaper) ...<Widget>[
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _clearWallpaper,
                            icon: const Icon(Lucide.Trash2, size: 16),
                            label: const Text('移除'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // 深色 / 浅色，默认深色，不跟随系统
            Container(
              color: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    '模式',
                    style: TextStyle(
                      fontSize: 15,
                      color: MomentColors.primaryText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '默认深色，不跟随系统',
                    style: TextStyle(
                      fontSize: 12,
                      color: MomentColors.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    segments: const <ButtonSegment<bool>>[
                      ButtonSegment<bool>(
                        value: true,
                        label: Text('深色'),
                        icon: Icon(Lucide.Moon, size: 16),
                      ),
                      ButtonSegment<bool>(
                        value: false,
                        label: Text('浅色'),
                        icon: Icon(Lucide.Sun, size: 16),
                      ),
                    ],
                    selected: <bool>{_theme.dark},
                    onSelectionChanged: (Set<bool> values) {
                      if (values.isEmpty) return;
                      _setDark(values.first);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // 压暗程度 0~80%
            Container(
              color: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Text(
                        '壁纸压暗',
                        style: TextStyle(
                          fontSize: 15,
                          color: MomentColors.primaryText,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${(_theme.dim * 100).round()}%',
                        style: const TextStyle(
                          fontSize: 13,
                          color: MomentColors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '壁纸上一层黑色遮罩，字看得更清；最高 80%，再黑就没壁纸的意思了',
                    style: TextStyle(
                      fontSize: 12,
                      color: MomentColors.secondaryText,
                    ),
                  ),
                  Slider(
                    value: _theme.dim,
                    min: 0,
                    max: maxPhoneWallpaperDim,
                    divisions: 16,
                    onChanged: _setDim,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
