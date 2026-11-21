import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/chat/chat_service.dart';
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

  /// 占位图标点了只提示，不跳页。
  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
      );
  }

  /// 16 个图标按文件名顺序摆。只有朋友圈/微信/设置是能点的真入口，
  /// 其余都是占位，点了给一句提示。
  List<Widget> _buildIcons(Color labelColor, List<Shadow> labelShadow) {
    // 顺序即 icon 文件命名顺序：1朋友圈 … 16设置。
    const labels = <String>[
      '朋友圈',
      '微信',
      '相机',
      '浏览器',
      'QQ',
      '微博',
      '电话',
      '短信',
      '哔哩哔哩',
      '知乎',
      '淘宝',
      '抖音',
      '日记',
      '起点小说',
      '相册',
      '设置',
    ];
    final icons = <Widget>[];
    for (var i = 0; i < labels.length; i++) {
      final index = i + 1;
      final label = labels[i];
      final asset = 'assets/icons/phone_${index.toString().padLeft(2, '0')}.webp';
      final VoidCallback onTap;
      switch (index) {
        case 1: // 朋友圈：召唤名单 + 首字母索引
          onTap = () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const MomentPage(),
                ),
              );
          break;
        case 2: // 微信：群聊 @ + 私聊已读不回都在里面
          onTap = () => openWechat(context);
          break;
        case 16: // 设置：小手机自己的主题/壁纸页
          onTap = _openSettings;
          break;
        default: // 占位
          onTap = () => _toast('$label 还没做');
          break;
      }
      icons.add(
        _AppIcon(
          label: label,
          asset: asset,
          labelColor: labelColor,
          labelShadow: labelShadow,
          onTap: onTap,
        ),
      );
    }
    return icons;
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
                  children: _buildIcons(labelColor, labelShadow),
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
    required this.asset,
    required this.onTap,
    required this.labelColor,
    required this.labelShadow,
  });

  final String label;

  /// 系统图标资源（assets 里的 webp），不进沙盒扫描，不会出现在资产面板。
  final String asset;
  final VoidCallback onTap;
  final Color labelColor;
  final List<Shadow> labelShadow;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // 图本身是透明底彩色 iOS 图标，直接铺开，不再套白底容器。
          Image.asset(
            asset,
            width: 56,
            height: 56,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox(
              width: 56,
              height: 56,
            ),
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
