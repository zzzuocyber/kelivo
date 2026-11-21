import 'package:flutter/material.dart';

/// 让「内容自适应高度」的面板也能像迷你地图那样往上拉变大。
///
/// 把面板头部（把手 + 标题）包进来即可：拖动时按像素位移换算成
/// [DraggableScrollableSheet] 的比例。身体部分不接滚动控制器，所以只能靠
/// 这块热区拉，输入框里的手势不会互相打架。
class SheetDragRegion extends StatelessWidget {
  const SheetDragRegion({
    super.key,
    required this.controller,
    required this.height,
    required this.minSize,
    required this.maxSize,
    required this.child,
  });

  final DraggableScrollableController controller;

  /// 面板可用高度（像素），用来把 dy 换算成比例。
  final double height;
  final double minSize;
  final double maxSize;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    void onUpdate(DragUpdateDetails details) {
      if (height <= 0 || !controller.isAttached) return;
      final next = (controller.size - details.delta.dy / height)
          .clamp(minSize, maxSize)
          .toDouble();
      controller.jumpTo(next);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: onUpdate,
      child: child,
    );
  }
}
