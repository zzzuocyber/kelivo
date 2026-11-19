import 'package:flutter/material.dart';

import '../../icons/lucide_adapter.dart';
import 'moment_models.dart';
import 'moment_widgets.dart';

/// 天意改动的回调：传角色名 = 开启或切换，传 null = 关闭。
/// 返回 false 表示没存上，弹窗那边就不改自己的显示。
typedef DivineChangeCallback = Future<bool> Function(String? name);

/// 「已生效天意」那一行的底色：白卡上淡一档，看得出来但不刺眼。
const Color _divineRowTint = Color(0xFFF2F3F5);

/// 左下角那个悬浮圆钮点开的通讯录：屏幕中间一个圆角方框，带投影。
/// 点里面的角色 → 关掉弹窗 → 由调用方负责跳到那个人的主页。
/// 长按任意角色 → 开 / 切 / 关天意。改完**弹窗留着**，可以连着操作。
class MomentContactsOutcome {
  const MomentContactsOutcome.open(this.openAuthor);

  /// 点了某个人，去看他的主页。
  final String openAuthor;
}

Future<MomentContactsOutcome?> showMomentContactsDialog(
  BuildContext context, {
  required List<MomentCharacter> characters,
  required Map<String, MomentAssets> assets,
  String? divineName,
  DivineChangeCallback? onDivineChanged,
}) {
  return showDialog<MomentContactsOutcome>(
    context: context,
    barrierColor: const Color(0x66000000),
    builder: (_) => _MomentContactsDialog(
      characters: characters,
      assets: assets,
      divineName: divineName,
      onDivineChanged: onDivineChanged,
    ),
  );
}

class _MomentContactsDialog extends StatefulWidget {
  const _MomentContactsDialog({
    required this.characters,
    required this.assets,
    this.divineName,
    this.onDivineChanged,
  });

  final List<MomentCharacter> characters;
  final Map<String, MomentAssets> assets;

  /// 打开弹窗那一刻，天意开着谁；null = 没开。
  final String? divineName;

  /// 实时写库。不走返回值，因为改完不关窗。
  final DivineChangeCallback? onDivineChanged;

  @override
  State<_MomentContactsDialog> createState() => _MomentContactsDialogState();
}

class _MomentContactsDialogState extends State<_MomentContactsDialog> {
  /// 弹窗自己记一份：改完不关窗，灰底和菜单得立刻跟着变。
  String? _divineName;

  /// 正在写库，这期间不再接长按，免得连点写乱。
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _divineName = widget.divineName;
  }

  String get _currentDivine => (_divineName ?? '').trim();

  bool _isUsing(MomentCharacter character) {
    final name = character.name.trim();
    final current = _currentDivine;
    return current.isNotEmpty && current == name;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Theme(
      data: momentLightTheme(),
      child: Material(
        type: MaterialType.transparency,
        child: Center(
          child: Container(
            width: size.width - 72,
            constraints: BoxConstraints(maxHeight: size.height * 0.62),
            decoration: BoxDecoration(
              color: MomentColors.card,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 28,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 8, 6),
                  child: Row(
                    children: <Widget>[
                      const Text(
                        '通讯录',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: MomentColors.primaryText,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Lucide.X,
                          size: 18,
                          color: MomentColors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.characters.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(18, 8, 18, 28),
                    child: Text(
                      '还没有加角色',
                      style: TextStyle(
                        fontSize: 13,
                        color: MomentColors.secondaryText,
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 12),
                      itemCount: widget.characters.length,
                      itemBuilder: (_, index) =>
                          _contactRow(widget.characters[index]),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _contactRow(MomentCharacter character) {
    final usingThis = _isUsing(character);
    final assetsFor = widget.assets[character.name];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // 天意开着别人的时候，这张卡也有菜单（切换 / 关闭），不再「长按没反应」。
      onLongPressStart: _saving
          ? null
          : (details) => _handleLongPress(character, details.globalPosition),
      child: Ink(
        decoration: BoxDecoration(color: usingThis ? _divineRowTint : null),
        child: InkWell(
          onTap: () => Navigator.of(
            context,
          ).pop(MomentContactsOutcome.open(character.name)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: <Widget>[
                MomentAvatar(
                  name: character.name,
                  size: 36,
                  imagePath: assetsFor?.avatar,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    character.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
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
        ),
      ),
    );
  }

  Future<void> _handleLongPress(
    MomentCharacter character,
    Offset position,
  ) async {
    if (_saving) return;
    final name = character.name.trim();
    if (name.isEmpty) return;

    final usingThis = _isUsing(character);
    final hasDivine = _currentDivine.isNotEmpty;
    final entries = <_DivineMenuEntry>[];
    if (!hasDivine) {
      entries.add(const _DivineMenuEntry(_actionUse, '开启天意'));
    } else if (usingThis) {
      entries.add(const _DivineMenuEntry(_actionClose, '关闭天意'));
    } else {
      entries.add(_DivineMenuEntry(_actionUse, '切换天意：$name'));
      entries.add(const _DivineMenuEntry(_actionClose, '关闭天意'));
    }

    final picked = await _showAnchorMenu(position, entries);
    if (picked == null || !mounted) return;
    await _applyDivine(picked == _actionClose ? null : name);
  }

  /// 写库交给页面那边（它拿着 store），成功后弹窗自己更新显示。
  Future<void> _applyDivine(String? name) async {
    final clean = (name ?? '').trim();
    final next = clean.isEmpty ? null : clean;
    final callback = widget.onDivineChanged;
    if (callback == null) {
      setState(() => _divineName = next);
      return;
    }
    setState(() => _saving = true);
    var ok = false;
    try {
      ok = await callback(next);
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) _divineName = next;
    });
  }

  /// 贴着手指弹的小菜单，跟动态那边同一套尺寸。
  /// 两项的时候会自动往上让，免得贴着屏幕底边被切掉。
  Future<String?> _showAnchorMenu(
    Offset position,
    List<_DivineMenuEntry> entries,
  ) {
    final size = MediaQuery.sizeOf(context);
    const menuWidth = 150.0;
    final menuHeight = 16.0 + entries.length * 44.0;
    final maxLeft = size.width - menuWidth - 8;
    var left = position.dx > size.width / 2
        ? position.dx - menuWidth
        : position.dx;
    left = left.clamp(8.0, maxLeft < 8.0 ? 8.0 : maxLeft);
    var top = position.dy;
    final lowest = size.height - menuHeight - 12;
    if (top > lowest) top = lowest;
    if (top < 12) top = 12;
    return showMenu<String>(
      context: context,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      position: RelativeRect.fromLTRB(
        left,
        top,
        size.width - left - menuWidth,
        size.height - top,
      ),
      items: <PopupMenuEntry<String>>[
        for (final entry in entries)
          PopupMenuItem<String>(
            value: entry.value,
            height: 44,
            child: Text(
              entry.label,
              style: const TextStyle(
                fontSize: 14,
                color: MomentColors.primaryText,
              ),
            ),
          ),
      ],
    );
  }
}

const String _actionUse = 'use';
const String _actionClose = 'close';

class _DivineMenuEntry {
  const _DivineMenuEntry(this.value, this.label);

  final String value;
  final String label;
}
