import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';

/// The toolbar and its reserved area share the same collapse animation. Native
/// viewport insets provide that reservation without resizing the WebView.
class BrowserMobileLayout extends StatelessWidget {
  const BrowserMobileLayout({
    super.key,
    required this.content,
    required this.toolbar,
    required this.viewPadding,
    this.agentStatus,
    this.transitionOverlay,
    this.findBar,
    this.onViewportHeight,
    this.keyboardInset = 0,
    this.viewportResizesForKeyboard = true,
    this.underlapStatusBar = false,
    this.bottomContentInset = 0,
    this.underlapToolbar = false,
    this.fadeBehindToolbar = false,
    this.topBar,
    this.immersive = false,
  });
  final Widget content;
  final Widget toolbar;

  /// Tab-flight pixels use the route's full-screen coordinates, independently
  /// of the native viewport's asynchronously applied status-bar inset.
  final Widget? transitionOverlay;

  /// Read above Scaffold. Its resized body subtracts the keyboard from
  /// viewPadding, which must not change the dock's collapsed geometry.
  final EdgeInsets viewPadding;
  final Widget? agentStatus;
  final Widget? findBar;
  final ValueChanged<double>? onViewportHeight;
  final double keyboardInset;
  final bool viewportResizesForKeyboard;
  final bool underlapStatusBar;
  final double bottomContentInset;
  final bool underlapToolbar;
  final bool fadeBehindToolbar;

  /// Edge 风格顶部地址栏。给定时，网页内容从它下方开始。
  final Widget? topBar;

  /// 最大化：藏起顶栏与底栏，网页铺满整个浏览器页面。
  final bool immersive;
  static const double topBarHeight = 56;
  static const double bottomBarHeight = 72;
  static const double expandedChromeHeight = 54;

  static double collapseDropFor(double bottomSafeInset) =>
      bottomSafeInset.clamp(
        0.0,
        defaultTargetPlatform == TargetPlatform.android ? 16.0 : 20.0,
      );

  static double get toolbarBottomGap =>
      defaultTargetPlatform == TargetPlatform.android ? 16 : 10;

  static double controlHeightFor(double collapseProgress) =>
      48 - 14 * collapseProgress;

  /// Follow the controls' height and downward travel, retaining six points of
  /// clearance above them. A form keyboard replaces the home-indicator inset.
  static double contentBottomInsetFor({
    required double bottomSafeInset,
    required double keyboardInset,
    required bool viewportResizesForKeyboard,
    required double collapseProgress,
  }) =>
      controlHeightFor(collapseProgress) +
      6 -
      collapseDropFor(bottomSafeInset) * collapseProgress +
      toolbarBottomGap +
      (viewportResizesForKeyboard
          ? math.max(0.0, bottomSafeInset - keyboardInset)
          : bottomSafeInset);

  @override
  Widget build(BuildContext context) {
    final padding = viewPadding;
    // The keyboard already shortened a webpage-form viewport; address editing
    // keeps the full scene behind it. Both paths share the same screen-space
    // lower boundary and stop at the home-indicator inset during dismissal.
    final dockInset =
        math.max(padding.bottom, keyboardInset) -
        (viewportResizesForKeyboard ? keyboardInset : 0);
    // Edge 风格底栏不透明，网页底部要让出它的高度（最大化时不用让）。
    final viewportBottom = immersive
        ? 0.0
        : (underlapToolbar
            ? bottomContentInset
            : (bottomContentInset > 0 ? bottomContentInset : bottomBarHeight));
    // Edge 风格：有顶栏时网页从它下方开始；最大化时顶栏底栏都藏起，网页铺满。
    final topInset = immersive
        ? 0.0
        : topBar != null
        ? padding.top + topBarHeight
        : (underlapStatusBar ? 0.0 : padding.top);
    return LayoutBuilder(
      builder: (context, constraints) {
        onViewportHeight?.call(
          constraints.maxHeight - topInset - viewportBottom,
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              key: const ValueKey('browserMobileViewportSlot'),
              top: topInset,
              bottom: viewportBottom,
              child: content,
            ),
            if (transitionOverlay != null)
              Positioned.fill(
                key: const ValueKey('browserTabReturnCoverSlot'),
                child: transitionOverlay!,
              ),
            // 顶栏：Edge 风格常驻地址栏。最大化时隐藏；输入地址时也要显示。
            if (topBar != null && !immersive)
              Positioned(
                key: const ValueKey('browserEdgeTopBarSlot'),
                top: 0,
                left: 0,
                right: 0,
                height: padding.top + topBarHeight,
                child: topBar!,
              ),
            if (agentStatus != null)
              Positioned(
                key: const ValueKey('browserMobileOverlaySlot'),
                top: padding.top + 8,
                left: 12,
                right: 12,
                child: agentStatus!,
              ),
            // 底栏 Edge 风格：最大化时藏起。
            if (!immersive)
              AnimatedPositioned(
                key: const ValueKey('browserMobileToolbarSlot'),
                duration: Duration(
                  milliseconds:
                      defaultTargetPlatform == TargetPlatform.android &&
                          !MediaQuery.disableAnimationsOf(context)
                      ? 240
                      : 0,
                ),
                curve: Curves.easeOutCubic,
                left: 0,
                right: 0,
                bottom: 0,
                child: toolbar,
              ),
            if (findBar != null)
              Positioned(
                key: const ValueKey('browserMobileFindSlot'),
                left: 16,
                right: 16,
                bottom: dockInset + 10,
                child: findBar!,
              ),
          ],
        );
      },
    );
  }
}

/// Direction changes retarget a critically damped spring from its current
/// position and velocity. Coalesced native events cannot jump the geometry.
class BrowserChromeTransition extends StatefulWidget {
  const BrowserChromeTransition({
    super.key,
    required this.progress,
    this.animate = false,
    required this.reducedMotion,
    required this.builder,
    this.onProgress,
  }) : assert(progress >= 0 && progress <= 1);

  final double progress;
  final bool animate;
  final bool reducedMotion;
  final Widget Function(BuildContext, double) builder;
  final ValueChanged<double>? onProgress;

  @override
  State<BrowserChromeTransition> createState() =>
      _BrowserChromeTransitionState();
}

class _BrowserChromeTransitionState extends State<BrowserChromeTransition>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController.unbounded(
    vsync: this,
    value: widget.progress,
  )..addListener(_reportProgress);

  void _reportProgress() =>
      widget.onProgress?.call(_motion.value.clamp(0.0, 1.0));

  @override
  void didUpdateWidget(BrowserChromeTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.progress == oldWidget.progress &&
        widget.animate == oldWidget.animate &&
        widget.reducedMotion == oldWidget.reducedMotion) {
      return;
    }
    final target = widget.progress;
    if (!widget.animate || widget.reducedMotion) {
      _motion.value = target;
    } else {
      _motion.animateWith(
        SpringSimulation(
          SpringDescription.withDampingRatio(mass: 1, stiffness: 400, ratio: 1),
          _motion.value,
          target,
          _motion.velocity,
          tolerance: const Tolerance(distance: .0005, velocity: .005),
          snapToEnd: true,
        ),
      );
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _motion,
    builder: (context, _) => widget.builder(context, _motion.value.clamp(0, 1)),
  );
}
