import 'package:flutter/material.dart';

import '../../icons/lucide_adapter.dart';
import 'moment_models.dart';
import 'moment_widgets.dart';

/// 左下角那个悬浮圆钮点开的通讯录：屏幕中间一个圆角方框，带投影。
/// 点里面的角色 → 关掉弹窗 → 由调用方负责跳到那个人的主页。
/// 长按卡片 → 开启 / 关闭天意（人在用的时候，别人的卡片长按没反应）。
class MomentContactsOutcome {
  const MomentContactsOutcome._({
    this.openAuthor,
    this.divineName,
    this.closeDivine = false,
  });

  /// 点了某个人，去看他的主页。
  const MomentContactsOutcome.open(String name) : this._(openAuthor: name);

  /// 长按卡片，开启天意。
  const MomentContactsOutcome.divine(String name) : this._(divineName: name);

  /// 长按正在用的那张卡，关闭天意。
  const MomentContactsOutcome.closeDivine() : this._(closeDivine: true);

  final String? openAuthor;
  final String? divineName;
  final bool closeDivine;
}

Future<MomentContactsOutcome?> showMomentContactsDialog(
  BuildContext context, {
  required List<MomentCharacter> characters,
  required Map<String, MomentAssets> assets,
  String? divineName,
}) {
  return showDialog<MomentContactsOutcome>(
    context: context,
    barrierColor: const Color(0x66000000),
    builder: (_) => _MomentContactsDialog(
      characters: characters,
      assets: assets,
      divineName: divineName,
    ),
  );
}

class _MomentContactsDialog extends StatelessWidget {
  const _MomentContactsDialog({
    required this.characters,
    required this.assets,
    this.divineName,
  });

  final List<MomentCharacter> characters;
  final Map<String, MomentAssets> assets;

  /// 现在开着天意的那个人；null = 没开。
  final String? divineName;

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
                if (characters.isEmpty)
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
                      itemCount: characters.length,
                      itemBuilder: (_, index) {
                        final character = characters[index];
                        return _contactRow(context, character);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _contactRow(BuildContext context, MomentCharacter character) {
    final name = character.name.trim();
    final usingThis = divineName != null && divineName!.trim() == name;
    // 天意开着别人的时候，这一张卡长按什么都不出。
    final canToggle = divineName == null || usingThis;
    final assetsFor = assets[character.name];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: canToggle
          ? (details) => _toggleDivine(
              context,
              character,
              usingThis,
              details.globalPosition,
            )
          : null,
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
    );
  }

  Future<void> _toggleDivine(
    BuildContext context,
    MomentCharacter character,
    bool usingThis,
    Offset position,
  ) async {
    final label = usingThis ? '关闭天意' : '开启天意';
    final picked = await _showAnchorMenu(context, position, label);
    if (picked == null || !context.mounted) return;
    Navigator.of(context).pop(
      usingThis
          ? const MomentContactsOutcome.closeDivine()
          : MomentContactsOutcome.divine(character.name),
    );
  }

  /// 贴着手指弹的小菜单，跟动态那边同一套尺寸。
  Future<String?> _showAnchorMenu(
    BuildContext context,
    Offset position,
    String label,
  ) {
    final size = MediaQuery.sizeOf(context);
    final left = position.dx > size.width / 2 ? position.dx - 150 : position.dx;
    final top = position.dy;
    return showMenu<String>(
      context: context,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      position: RelativeRect.fromLTRB(
        left,
        top,
        size.width - left - 140,
        size.height - top,
      ),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: label,
          height: 44,
          child: Text(
            label,
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
