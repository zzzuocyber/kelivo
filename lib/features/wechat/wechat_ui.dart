import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'wechat_models.dart';

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

/// 发言间隔选择器：一排预设 + 自定义时的两个数字框。
///
/// 三处共用同一份（全局默认 / 单个群 / 单个角色私聊），
/// 以前群设置里自己写了一份，现在抽出来，别再各写一遍。
class WechatIntervalPicker extends StatelessWidget {
  const WechatIntervalPicker({
    super.key,
    required this.preset,
    required this.customMin,
    required this.customMax,
    required this.onChanged,
    this.note,
  });

  final WechatIntervalPreset preset;
  final int customMin;
  final int customMax;

  /// 改完（点预设、或者数字框提交）回传三个值。
  final void Function(WechatIntervalPreset preset, int min, int max) onChanged;

  /// 底下那行灰字说明，不同场景写的不一样。
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final item in WechatIntervalPreset.values) _chip(item),
            ],
          ),
        ),
        if (preset == WechatIntervalPreset.custom)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: <Widget>[
                _NumberField(
                  label: '最短',
                  value: customMin,
                  onDone: (value) => onChanged(
                    preset,
                    value,
                    value > customMax ? value : customMax,
                  ),
                ),
                const SizedBox(width: 14),
                _NumberField(
                  label: '最长',
                  value: customMax,
                  onDone: (value) => onChanged(
                    preset,
                    value < customMin ? customMin : value,
                    value,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  '秒',
                  style: TextStyle(
                    fontSize: 13,
                    color: WechatColors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        if (note != null)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            alignment: Alignment.centerLeft,
            child: Text(
              note!,
              style: const TextStyle(
                fontSize: 11.5,
                color: WechatColors.secondaryText,
                height: 1.6,
              ),
            ),
          ),
      ],
    );
  }

  Widget _chip(WechatIntervalPreset item) {
    final active = preset == item;
    return GestureDetector(
      onTap: () => onChanged(item, customMin, customMax),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFE7F8EE) : const Color(0xFFF2F2F2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? WechatColors.green : Colors.transparent,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              item.label,
              style: TextStyle(
                fontSize: 13,
                color: active ? WechatColors.green : WechatColors.primaryText,
                fontWeight: active ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              item.hint,
              style: const TextStyle(
                fontSize: 9.5,
                color: WechatColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 间隔里的秒数输入框。
///
/// 必须是有状态的：直接拿 TextField 受父级 setState 重建会把光标顶回开头。
class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.onDone,
  });

  final String label;
  final int value;
  final void Function(int value) onDone;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _controller = TextEditingController(
    text: '${widget.value}',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commit(String text) {
    final parsed = int.tryParse(text.trim());
    if (parsed == null || parsed < 0) return;
    widget.onDone(parsed > 3600 ? 3600 : parsed);
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: <Widget>[
          Text(
            widget.label,
            style: const TextStyle(
              fontSize: 13,
              color: WechatColors.secondaryText,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onSubmitted: _commit,
                onEditingComplete: () => _commit(_controller.text),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
