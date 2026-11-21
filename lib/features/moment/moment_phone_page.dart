import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/services/chat/chat_service.dart';
import '../../icons/lucide_adapter.dart';
import '../../utils/sandbox_path_resolver.dart';
import '../wechat/wechat_page.dart';
import 'moment_page.dart';
import 'moment_phone_settings_page.dart';
import 'moment_phone_theme_store.dart';
import 'moment_widgets.dart';

/// 打开小手机桌面。侧栏罗盘调的就是它。
Future<void> openMomentPhone(BuildContext context) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (_) => const MomentPhonePage()),
  );
}

/// 罗盘点进来先到这块「模拟手机屏幕」：一块桌面，上面摆 app 图标。
class MomentPhonePage extends StatefulWidget {
  const MomentPhonePage({super.key});

  @override
  State<MomentPhonePage> createState() => _MomentPhonePageState();
}

class _MomentPhonePageState extends State<MomentPhonePage> {
  late final PhoneThemeStore _themeStore;
  late PhoneTheme _theme;

  @override
  void initState() {
    super.initState();
    _themeStore = PhoneThemeStore(context.read<ChatService>());
    _theme = _themeStore.read();
  }

  /// 从设置页返回时重新读一次主题，壁纸/深浅/压暗立即生效。
  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const MomentPhoneSettingsPage(),
      ),
    );
    if (!mounted) return;
    setState(() => _theme = _themeStore.read());
  }

  bool get _hasWallpaper {
    final path = _theme.wallpaperPath;
    return path.isNotEmpty &&
        File(SandboxPathResolver.fix(path)).existsSync();
  }

  @override
  Widget build(BuildContext context) {
    final dark = _theme.dark;
    final wallpaper = _hasWallpaper;

    // 图标文字：深色主题用浅色字、浅色主题用深色字，自动反色；都带一层淡投影。
    final labelColor = dark ? Colors.white : const Color(0xFF1B1C1E);
    final labelShadow = <Shadow>[
      Shadow(
        color: dark ? Colors.black54 : Colors.white70,
        blurRadius: 4,
        offset: const Offset(0, 1),
      ),
    ];

    return Theme(
      data: momentLightTheme(),
      child: Scaffold(
        backgroundColor: dark ? const Color(0xFF121417) : const Color(0xFFEFF1F5),
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // 壁纸 + 可调黑色正片叠底 + 顶部固定渐变（保信号栏看得清）。
            if (wallpaper) ...<Widget>[
              Positioned.fill(
                child: Image.file(
                  File(SandboxPathResolver.fix(_theme.wallpaperPath)),
                  fit: BoxFit.cover,
                ),
              ),
              Positioned.fill(
                child: ColoredBox(
                  color: Color.fromRGBO(0, 0, 0, _theme.dim),
                ),
              ),
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 96,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        Color(0x66000000),
                        Color(0x00000000),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 36, 20, 20),
                child: GridView.count(
                  crossAxisCount: 4,
                  mainAxisSpacing: 22,
                  crossAxisSpacing: 18,
                  childAspectRatio: 0.82,
                  children: <Widget>[
                    _AppIcon(
                      label: '朋友圈',
                      icon: Lucide.Sparkles,
                      labelColor: labelColor,
                      labelShadow: labelShadow,
                      onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => const MomentPage(),
                        ),
                      ),
                    ),
                    _AppIcon(
                      label: '微信',
                      icon: Lucide.MessagesSquare,
                      tint: const Color(0xFF07C160),
                      labelColor: labelColor,
                      labelShadow: labelShadow,
                      onTap: () => openWechat(context),
                    ),
                    _AppIcon(
                      label: '设置',
                      icon: Lucide.Settings2,
                      labelColor: labelColor,
                      labelShadow: labelShadow,
                      onTap: _openSettings,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.labelColor,
    required this.labelShadow,
    this.tint,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color labelColor;
  final List<Shadow> labelShadow;

  /// 图标颜色，不传就跟朋友圈那个一致。
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: MomentColors.hairline),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 10,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, size: 26, color: tint ?? MomentColors.name),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: labelColor,
              shadows: labelShadow,
            ),
          ),
        ],
      ),
    );
  }
}
