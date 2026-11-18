import 'package:flutter/material.dart';

import '../../icons/lucide_adapter.dart';
import 'moment_models.dart';
import 'moment_widgets.dart';

/// 左下角那个悬浮圆钮点开的通讯录：屏幕中间一个圆角方框，带投影。
/// 点里面的角色 → 关掉弹窗 → 由调用方负责跳到那个人的主页。
Future<void> showMomentContactsDialog(
  BuildContext context, {
  required List<MomentCharacter> characters,
  required Map<String, MomentAssets> assets,
  required void Function(String name) onOpen,
}) async {
  final picked = await showDialog<String>(
    context: context,
    barrierColor: const Color(0x66000000),
    builder: (_) =>
        _MomentContactsDialog(characters: characters, assets: assets),
  );
  if (picked == null || !context.mounted) return;
  onOpen(picked);
}

class _MomentContactsDialog extends StatelessWidget {
  const _MomentContactsDialog({required this.characters, required this.assets});

  final List<MomentCharacter> characters;
  final Map<String, MomentAssets> assets;

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
                        final assetsFor = assets[character.name];
                        return InkWell(
                          onTap: () =>
                              Navigator.of(context).pop(character.name),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
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
                        );
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
}
