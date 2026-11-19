import 'package:flutter/material.dart';

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
class WechatAvatarText extends StatelessWidget {
  const WechatAvatarText({super.key, required this.name, this.size = 38});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: wechatAvatarColor(name),
        borderRadius: BorderRadius.circular(size * 0.12),
      ),
      alignment: Alignment.center,
      child: Text(
        wechatInitialOf(name),
        style: TextStyle(
          fontSize: size * 0.36,
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
