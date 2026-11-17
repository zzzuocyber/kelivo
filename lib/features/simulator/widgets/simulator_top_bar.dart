import 'package:flutter/material.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/ios_tactile.dart';

/// 模拟器自己的窄栏：只有返回、标题、重新生成、设置四样。
///
/// 聊天页那套抽屉键、小地图、新建对话都不搬过来；草图顶上那排彩色小胶囊是
/// 调试开关，真机上不存在。
class SimulatorTopBar extends StatelessWidget implements PreferredSizeWidget {
  const SimulatorTopBar({
    super.key,
    required this.title,
    required this.onBack,
    required this.onRegenerate,
    required this.onSettings,
    this.canRegenerate = true,
  });

  /// 比聊天页的 56 窄一档，留给正文。
  static const double barHeight = 44;

  /// 栏底色块在屏幕上占到的总高度（含状态栏）。
  ///
  /// Scaffold 只要挂了 appBar，就会把正文 MediaQuery 的顶部内边距抹掉，
  /// 所以正文里的 `MediaQuery.paddingOf(context).top` 读不到状态栏高度；
  /// 这里退回真实视图的 padding 去补。
  static double clearanceOf(BuildContext context) {
    final fromMediaQuery = MediaQuery.paddingOf(context).top;
    final statusBar = fromMediaQuery > 0
        ? fromMediaQuery
        : View.of(context).padding.top / View.of(context).devicePixelRatio;
    return barHeight + statusBar;
  }

  final Widget title;
  final VoidCallback onBack;
  final VoidCallback onRegenerate;
  final VoidCallback onSettings;
  final bool canRegenerate;

  @override
  Size get preferredSize => const Size.fromHeight(barHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: barHeight,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 0,
      centerTitle: true,
      leadingWidth: 48,
      leading: IosIconButton(
        size: 20,
        minSize: 40,
        icon: Lucide.ChevronLeft,
        onTap: onBack,
        semanticLabel: '返回模拟器列表',
      ),
      title: title,
      actions: [
        IosIconButton(
          size: 18,
          minSize: 40,
          icon: Lucide.RefreshCw,
          enabled: canRegenerate,
          onTap: onRegenerate,
          semanticLabel: '重新生成本轮剧情',
        ),
        IosIconButton(
          size: 19,
          minSize: 40,
          icon: Lucide.Settings,
          onTap: onSettings,
          semanticLabel: '模拟器设置',
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}
