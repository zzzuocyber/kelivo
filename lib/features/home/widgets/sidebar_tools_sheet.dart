import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../theme/app_semantic_colors.dart';
import '../../moment/moment_phone_page.dart';
import '../../translate/pages/translate_page.dart';

/// 侧栏底部工具按钮点开的原生风格面板：翻译 / 罗盘（小手机）两个并列入口。
/// 罗盘就是朋友圈那套小手机界面的入口，之前上游合入时丢了，这里放回。
void showSidebarToolsSheet(BuildContext context) {
  unawaited(
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.overlaySurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => const SidebarToolsSheet(),
    ),
  );
}

class SidebarToolsSheet extends StatelessWidget {
  const SidebarToolsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final bg = context.overlaySurface;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final cardColor = sheetTileColor(context);

    Widget action({
      required IconData icon,
      required String label,
      required void Function(BuildContext navigatorContext) onTap,
    }) {
      return Expanded(
        child: SizedBox(
          height: 84,
          child: IosCardPress(
            baseColor: cardColor,
            borderRadius: BorderRadius.circular(14),
            pressedScale: 0.98,
            duration: const Duration(milliseconds: 260),
            onTap: () {
              Haptics.light();
              final navigatorContext = Navigator.of(context).context;
              Navigator.of(context).pop();
              onTap(navigatorContext);
            },
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 26, color: onSurface),
                  const SizedBox(height: 8),
                  Text(label, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: onSurface.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              action(
                icon: Lucide.Languages,
                label: '翻译',
                onTap: (navigatorContext) => Navigator.of(
                  navigatorContext,
                ).push<void>(
                  MaterialPageRoute(
                    builder: (_) => const TranslatePage(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              action(
                icon: Lucide.Compass,
                label: '罗盘',
                onTap: (navigatorContext) =>
                    unawaited(openMomentPhone(navigatorContext)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
