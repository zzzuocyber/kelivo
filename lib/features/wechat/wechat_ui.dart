import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/social_affinity.dart';
import '../../icons/lucide_adapter.dart';
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
    this.allowFollow = false,
  });

  final WechatIntervalPreset preset;
  final int customMin;
  final int customMax;

  /// 改完（点预设、或者数字框提交）回传三个值。
  final void Function(WechatIntervalPreset preset, int min, int max) onChanged;

  /// 底下那行灰字说明，不同场景写的不一样。
  final String? note;

  /// 是否多给一档「跟随全局」。群设置和私聊开，全局自己那处不开。
  final bool allowFollow;

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
              for (final item
                  in allowFollow
                      ? WechatIntervalPreset.values
                      : WechatIntervalPresetX.own)
                _chip(item),
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

/// 相邻两条消息隔了这么久，中间就插一条时间（跟微信差不多）。
const Duration wechatTimeDividerGap = Duration(minutes: 5);

/// 时间分隔上写什么。
///
/// 今天只写 `21:03`；昨天写 `昨天 21:03`；今年写 `11月18日 21:03`；
/// 更早带上年份。跨年那几条一眼能分出来。
String wechatTimeDividerLabel(int millis, {DateTime? now}) {
  if (millis <= 0) return '';
  final time = DateTime.fromMillisecondsSinceEpoch(millis);
  final base = now ?? DateTime.now();
  String two(int value) => value < 10 ? '0$value' : '$value';
  final clock = '${two(time.hour)}:${two(time.minute)}';
  final day = DateTime(time.year, time.month, time.day);
  final today = DateTime(base.year, base.month, base.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return clock;
  if (diff == 1) return '昨天 $clock';
  if (time.year == base.year) return '${time.month}月${time.day}日 $clock';
  return '${time.year}年${time.month}月${time.day}日 $clock';
}

/// 居中的那条时间（灰字，没有底色）。
class WechatTimeDivider extends StatelessWidget {
  const WechatTimeDivider({super.key, required this.millis});

  final int millis;

  @override
  Widget build(BuildContext context) {
    final label = wechatTimeDividerLabel(millis);
    if (label.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(fontSize: 11.5, color: Color(0xFFA6A6A6)),
        ),
      ),
    );
  }
}

/// 编辑一条消息的小弹窗（群聊、私聊共用）。
///
/// 做成有状态组件是为了自己管 controller 并在卸载时 dispose：
/// 直接在 dialog 闭包里建 controller 再 dispose，会撞上退场动画还在读它。
class WechatEditMessageDialog extends StatefulWidget {
  const WechatEditMessageDialog({super.key, required this.initial});

  final String initial;

  @override
  State<WechatEditMessageDialog> createState() =>
      _WechatEditMessageDialogState();
}

class _WechatEditMessageDialogState extends State<WechatEditMessageDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Text(
        '编辑这条消息',
        style: TextStyle(fontSize: 16, color: wechatMenuInk),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 1,
        maxLines: 6,
        style: const TextStyle(fontSize: 15, color: WechatColors.primaryText),
        decoration: const InputDecoration(
          hintText: '改点什么',
          hintStyle: TextStyle(color: WechatColors.secondaryText),
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            '取消',
            style: TextStyle(color: WechatColors.secondaryText),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('保存', style: TextStyle(color: WechatColors.green)),
        ),
      ],
    );
  }
}

/// 控制剧情走向：直接手写一段剧情，作为最高指令喂给模型这一次。
/// 取消返回 null，确定返回非空文字。
class WechatPlotDialog extends StatefulWidget {
  const WechatPlotDialog({super.key});

  @override
  State<WechatPlotDialog> createState() => _WechatPlotDialogState();
}

class _WechatPlotDialogState extends State<WechatPlotDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    Navigator.of(context).pop(value.isEmpty ? null : value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Text(
        '控制剧情走向',
        style: TextStyle(fontSize: 16, color: wechatMenuInk),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: TextField(
          controller: _controller,
          autofocus: true,
          minLines: 4,
          maxLines: 10,
          style: const TextStyle(fontSize: 15, color: WechatColors.primaryText),
          decoration: const InputDecoration(
            hintText:
                '直接写要发生的剧情：旁白、某个角色在想什么做什么、'
                '话题怎么转、要不要收尾……自由度最高。',
            hintStyle: TextStyle(color: WechatColors.secondaryText),
            border: OutlineInputBorder(),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            '取消',
            style: TextStyle(color: WechatColors.secondaryText),
          ),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text('定下这条剧情', style: TextStyle(color: WechatColors.green)),
        ),
      ],
    );
  }
}

/// 冷场多久：手动填分钟数。取消返回 null，确定返回正数分钟。
class WechatMinutesDialog extends StatefulWidget {
  const WechatMinutesDialog({super.key, this.initial = 1});

  final double initial;

  @override
  State<WechatMinutesDialog> createState() => _WechatMinutesDialogState();
}

class _WechatMinutesDialogState extends State<WechatMinutesDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: '${widget.initial}',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = double.tryParse(_controller.text.trim());
    Navigator.of(context).pop(value != null && value > 0 ? value : null);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Text(
        '冷场多久',
        style: TextStyle(fontSize: 16, color: wechatMenuInk),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(fontSize: 15, color: WechatColors.primaryText),
        decoration: const InputDecoration(
          hintText: '填分钟数，例如 2 或 0.5',
          hintStyle: TextStyle(color: WechatColors.secondaryText),
          suffixText: '分钟',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            '取消',
            style: TextStyle(color: WechatColors.secondaryText),
          ),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text('确定', style: TextStyle(color: WechatColors.green)),
        ),
      ],
    );
  }
}

// ============================================================
// 好感度面板：私聊三点菜单「看好感度」弹出。
// 上半显示分数/颜值/状态/粘人概率/变因/公式，下半是作弊（改分数、颜值、
// 状态、特殊状态、跳段）。保存返回新的 SocialAffinity，取消返回 null。
// ============================================================

/// 打开好感度面板。返回 null 表示没改。
Future<SocialAffinity?> showAffinityDialog(
  BuildContext context, {
  required SocialAffinity affinity,
}) {
  return showDialog<SocialAffinity>(
    context: context,
    builder: (_) => WechatAffinityDialog(affinity: affinity),
  );
}

// ============================================================
// 心声偷看：长按消息 → 菜单「偷看心声」弹出的只读卡片。
// 心声是生成时就存好的私货，这里只展示，不改、不重新问 AI。
// ============================================================

/// [who] 是谁的心声，[text] 是当时存下的那段。
Future<void> showHeartVoiceDialog(
  BuildContext context, {
  required String who,
  required String text,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Row(
        children: <Widget>[
          const Icon(Lucide.Heart, size: 18, color: WechatColors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$who 的心声',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      content: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          color: wechatMenuInk,
          height: 1.5,
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogCtx).pop(),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}

class WechatAffinityDialog extends StatefulWidget {
  const WechatAffinityDialog({super.key, required this.affinity});

  final SocialAffinity affinity;

  @override
  State<WechatAffinityDialog> createState() => _WechatAffinityDialogState();
}

class _WechatAffinityDialogState extends State<WechatAffinityDialog> {
  late double _score;
  late int _beauty;
  late final TextEditingController _status;
  late final Set<String> _specials;

  static const List<String> _allSpecials = <String>[
    '🩸 偏执',
    '💤 爱不自知',
    '🫧 错觉',
    '🔥 又爱又恨',
  ];

  @override
  void initState() {
    super.initState();
    _score = widget.affinity.score;
    _beauty = widget.affinity.beauty;
    _status = TextEditingController(text: widget.affinity.manualStatus);
    _specials = <String>{...widget.affinity.specials};
  }

  @override
  void dispose() {
    _status.dispose();
    super.dispose();
  }

  void _save() {
    final updated = widget.affinity.copyWith(
      score: _score.clamp(-100, 100).toDouble(),
      beauty: _beauty.clamp(1, 10),
      manualStatus: _status.text.trim(),
      specials: _specials.toList(growable: false),
      lastReason: '手动调整',
      lastFormula: '',
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    Navigator.of(context).pop(updated);
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 62,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12.5, color: WechatColors.secondaryText),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, color: WechatColors.primaryText),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 预览用临时值算，所见即所得。
    final preview = widget.affinity.copyWith(
      score: _score,
      beauty: _beauty,
      manualStatus: _status.text.trim(),
      specials: _specials.toList(growable: false),
    );
    return AlertDialog(
      backgroundColor: Colors.white,
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      title: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '${widget.affinity.name} 的好感度',
              style: const TextStyle(fontSize: 16, color: wechatMenuInk),
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.close, size: 20, color: WechatColors.secondaryText),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _row('分数', _score.toStringAsFixed(1)),
              _row('状态', preview.status),
              _row('粘人概率', '${(preview.chance * 100).round()}%'),
              _row('最近变因', widget.affinity.lastReason.isEmpty
                  ? '（暂无）'
                  : widget.affinity.lastReason),
              if (widget.affinity.lastFormula.isNotEmpty)
                _row('算式', widget.affinity.lastFormula),
              const Divider(height: 18),
              const Text(
                '作弊 · 直接改数值',
                style: TextStyle(fontSize: 13, color: wechatMenuInk),
              ),
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  const SizedBox(
                    width: 62,
                    child: Text(
                      '分数',
                      style: TextStyle(fontSize: 12.5, color: WechatColors.secondaryText),
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      min: -100,
                      max: 100,
                      value: _score,
                      activeColor: WechatColors.green,
                      onChanged: (value) => setState(() => _score = value),
                    ),
                  ),
                  Text(
                    _score.round().toString(),
                    style: const TextStyle(fontSize: 12, color: WechatColors.secondaryText),
                  ),
                ],
              ),
              Row(
                children: <Widget>[
                  const SizedBox(
                    width: 62,
                    child: Text(
                      '颜值',
                      style: TextStyle(fontSize: 12.5, color: WechatColors.secondaryText),
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      min: 1,
                      max: 10,
                      divisions: 9,
                      value: _beauty.toDouble(),
                      activeColor: WechatColors.green,
                      onChanged: (value) => setState(() => _beauty = value.round()),
                    ),
                  ),
                  Text(
                    '$_beauty',
                    style: const TextStyle(fontSize: 12, color: WechatColors.secondaryText),
                  ),
                ],
              ),
              TextField(
                controller: _status,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: '状态标签（留空=按分数自动）',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: <Widget>[
                  for (final tag in _allSpecials)
                    FilterChip(
                      label: Text(tag, style: const TextStyle(fontSize: 11.5)),
                      selected: _specials.contains(tag),
                      onSelected: (on) => setState(() {
                        if (on) {
                          _specials.add(tag);
                        } else {
                          _specials.remove(tag);
                        }
                      }),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            '取消',
            style: TextStyle(color: WechatColors.secondaryText),
          ),
        ),
        TextButton(
          onPressed: _save,
          child: const Text('保存', style: TextStyle(color: WechatColors.green)),
        ),
      ],
    );
  }
}

// ============================================================
// 发图：跟朋友圈同一套 emoji 拼图逻辑
// ============================================================
//
// 不接生图接口——按这句话里的词挑 emoji，摆成一张图。
// 表是从 moment_emoji.dart 复制过来的（那边被 moment_phone_page 引用，
// 反向 import 会成环），两边保持一致即可。

const Map<String, String> wechatEmojiTable = <String, String>{
  '烧烤': '🍢',
  '烤串': '🍢',
  '火锅': '🍲',
  '面条': '🍜',
  '拉面': '🍜',
  '泡面': '🍜',
  '加面': '🍜',
  '米饭': '🍚',
  '外卖': '🥡',
  '便当': '🍱',
  '早饭': '🥐',
  '早餐': '🥐',
  '饺子': '🥟',
  '包子': '🥟',
  '馒头': '🍞',
  '面包': '🍞',
  '鸡蛋': '🥚',
  '土豆': '🥔',
  '葱': '🌿',
  '蔬菜': '🥬',
  '水果': '🍎',
  '苹果': '🍎',
  '香蕉': '🍌',
  '西瓜': '🍉',
  '橘子': '🍊',
  '蛋糕': '🍰',
  '冰棍': '🍦',
  '雪糕': '🍦',
  '奶茶': '🧋',
  '咖啡': '☕',
  '啤酒': '🍺',
  '酒': '🍶',
  '茶': '🍵',
  '牛奶': '🥛',
  '糖': '🍬',
  '辣': '🌶️',
  '下雨': '🌧️',
  '雨': '🌧️',
  '雪': '❄️',
  '晴': '☀️',
  '太阳': '☀️',
  '晒': '☀️',
  '风': '🌬️',
  '台风': '🌪️',
  '云': '☁️',
  '雷': '⛈️',
  '热': '🥵',
  '冷': '🥶',
  '晚上': '🌙',
  '夜': '🌙',
  '早上': '🌅',
  '月': '🌙',
  '灯': '💡',
  '风扇': '🌀',
  '空调': '❄️',
  '手机': '📱',
  '耳机': '🎧',
  '电视': '📺',
  '书': '📖',
  '鞋': '👞',
  '皮鞋': '👞',
  '伞': '☂️',
  '包': '👜',
  '钱包': '👛',
  '钥匙': '🔑',
  '快递': '📦',
  '床': '🛏️',
  '椅子': '🪑',
  '衣服': '👕',
  '帽子': '🧢',
  '眼镜': '👓',
  '相机': '📷',
  '信': '✉️',
  '笔': '✒️',
  '纸': '📄',
  '超市': '🛒',
  '市场': '🏪',
  '菜市场': '🏪',
  '家': '🏠',
  '回家': '🏠',
  '街': '🛣️',
  '路上': '🛣️',
  '公司': '🏢',
  '办公室': '🏢',
  '上班': '🏢',
  '下班': '🌆',
  '学校': '🏫',
  '医院': '🏥',
  '公园': '🌳',
  '车站': '🚉',
  '地铁': '🚇',
  '公交': '🚌',
  '车': '🚗',
  '自行车': '🚲',
  '飞机': '✈️',
  '猫': '🐱',
  '狗': '🐶',
  '鸟': '🐦',
  '鱼': '🐟',
  '蚊子': '🦟',
  '孩子': '🧒',
  '老板': '🧑',
  '朋友': '🧑',
  '钱': '💰',
  '涨价': '📈',
  '便宜': '🏷️',
  '穷': '💸',
  '累': '😩',
  '困': '😴',
  '笑': '😄',
  '哭': '😢',
  '生气': '😠',
  '烦': '😑',
  '无聊': '😑',
  '音乐': '🎵',
  '电影': '🎬',
  '游戏': '🎮',
  '照片': '🖼️',
  '生日': '🎂',
  '礼物': '🎁',
};

const List<String> _wechatEmojiPool = <String>[
  '🌿',
  '🍃',
  '🌤️',
  '🌙',
  '✨',
  '🎈',
  '🧸',
  '🪴',
  '📷',
  '🎧',
  '🍀',
  '🕯️',
  '🧵',
  '🪁',
  '🍋',
  '🌰',
  '🐚',
  '🪶',
  '🌾',
  '☕',
];

/// 按正文和消息 id 生成 1~3 个 emoji，同样的输入永远同样的图。
List<String> wechatEmojisFor(String text, String seed) {
  final picked = <String>[];
  final body = text.replaceAll(RegExp(r'\s+'), '');
  final keys = wechatEmojiTable.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final key in keys) {
    if (!body.contains(key)) continue;
    final emoji = wechatEmojiTable[key]!;
    if (picked.contains(emoji)) continue;
    picked.add(emoji);
    if (picked.length >= 3) break;
  }
  if (picked.isEmpty) {
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) % 99991;
    }
    for (var i = 0; i < 3; i++) {
      final emoji = _wechatEmojiPool[(hash + i * 7) % _wechatEmojiPool.length];
      if (!picked.contains(emoji)) picked.add(emoji);
    }
  }
  return picked;
}

/// 微信消息配图：白底圆角，一个大 emoji + 最多两个小的，位置按消息 id 定死。
class WechatEmojiImage extends StatelessWidget {
  const WechatEmojiImage({
    super.key,
    required this.text,
    required this.seed,
    this.width = 168,
  });

  /// 拿正文里的词挑 emoji，所以图跟这句话是对得上的。
  final String text;

  /// 消息 id：保证同一条消息每次打开图都一样。
  final String seed;

  final double width;

  @override
  Widget build(BuildContext context) {
    final emojis = wechatEmojisFor(text, seed);
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) % 99991;
    }
    final main = emojis.isEmpty ? '🌿' : emojis[0];
    final second = emojis.length > 1 ? emojis[1] : null;
    final third = emojis.length > 2 ? emojis[2] : null;
    return Container(
      width: width,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: WechatColors.hairline),
      ),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Stack(
          children: <Widget>[
            Align(
              alignment: const Alignment(0, 0.18),
              child: Text(
                main,
                style: const TextStyle(fontSize: 62, height: 1.1),
              ),
            ),
            if (second != null)
              Align(
                alignment: const Alignment(0.62, -0.62),
                child: Transform.rotate(
                  angle: (hash % 7 - 3) / 100.0,
                  child: Text(
                    second,
                    style: const TextStyle(fontSize: 30, height: 1.1),
                  ),
                ),
              ),
            if (third != null)
              Align(
                alignment: const Alignment(-0.66, 0.72),
                child: Transform.rotate(
                  angle: (hash % 5 - 2) / 90.0,
                  child: Text(
                    third,
                    style: const TextStyle(fontSize: 24, height: 1.1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
