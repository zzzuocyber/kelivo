import 'dart:io';

import 'package:flutter/material.dart';

/// 底部弹出菜单里的字色。微信一律浅色，这里的字必须够深，
/// 不然夜间模式下会浅到看不清。
const Color wechatMenuInk = Color(0xFF1A1A1A);

/// 头像路径统一存朋友圈那份（`moment.assets`，键是同名），
/// 这里只负责把名字翻成路径，读不到就给 null 走首字色块。
typedef WechatAvatarLookup = String? Function(String name);

/// 微信一律浅色，进来就把主题换掉，不跟夜间模式走。
ThemeData wechatLightTheme() {
  return ThemeData(
    brightness: Brightness.light,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF07C160),
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: WechatColors.chatBg,
    canvasColor: Colors.white,
  );
}

class WechatColors {
  const WechatColors._();

  static const Color chatBg = Color(0xFFEDEDED);
  static const Color navBg = Color(0xFFEDEDED);
  static const Color listBg = Colors.white;
  static const Color mineBubble = Color(0xFF95EC69);
  static const Color otherBubble = Colors.white;
  static const Color primaryText = Color(0xFF191919);
  static const Color secondaryText = Color(0xFF999999);
  static const Color hairline = Color(0xFFDCDCDC);
  static const Color red = Color(0xFFFA5151);
  static const Color link = Color(0xFF576B95);
  static const Color green = Color(0xFF07C160);
}

/// 按名字固定一个头像色，同一个人每次进来颜色都一样。
Color wechatAvatarColor(String name) {
  var hash = 7;
  for (final unit in name.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  final hue = (hash % 360).toDouble();
  return HSLColor.fromAHSL(1, hue, 0.34, 0.46).toColor();
}

String wechatInitialOf(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';
  return trimmed.substring(0, 1);
}

/// 方角头像——微信是 4.5 左右的小圆角，不是圆的。
///
/// [imagePath] 传的是朋友圈那份头像（`moment.assets` 里同名那条）。
/// 两边共用同一份文件，所以哪边上传都同步；读不到就退回首字色块。
class WechatAvatarText extends StatelessWidget {
  const WechatAvatarText({
    super.key,
    required this.name,
    this.size = 38,
    this.imagePath,
  });

  final String name;
  final double size;
  final String? imagePath;

  @override
  Widget build(BuildContext context) {
    final path = (imagePath ?? '').trim();
    final radius = BorderRadius.circular(size * 0.12);
    final fallback = Text(
      wechatInitialOf(name),
      style: TextStyle(
        fontSize: size * 0.36,
        color: Colors.white,
        fontWeight: FontWeight.w500,
      ),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: wechatAvatarColor(name),
        borderRadius: radius,
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: path.isEmpty
          ? fallback
          : Image.file(
              File(path),
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: (size * 3).round(),
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}
