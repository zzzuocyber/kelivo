import 'package:flutter/material.dart';

import '../../icons/lucide_adapter.dart';
import 'moment_page.dart';
import 'moment_widgets.dart';

/// 打开小手机桌面。侧栏罗盘调的就是它。
Future<void> openMomentPhone(BuildContext context) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (_) => const MomentPhonePage()),
  );
}

/// 罗盘点进来先到这块「模拟手机屏幕」：一块桌面，上面摆 app 图标。
/// 现在只摆一个朋友圈。UI 先粗着来，以后再美化。
class MomentPhonePage extends StatelessWidget {
  const MomentPhonePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: momentLightTheme(),
      child: Scaffold(
        backgroundColor: const Color(0xFFEFF1F5),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 36, 20, 20),
            child: GridView.count(
              crossAxisCount: 4,
              mainAxisSpacing: 22,
              crossAxisSpacing: 18,
              childAspectRatio: 0.82,
              children: <Widget>[
                _AppIcon(
                  label: '朋友圈',
                  icon: Lucide.Sparkles,
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(builder: (_) => const MomentPage()),
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

class _AppIcon extends StatelessWidget {
  const _AppIcon({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: MomentColors.hairline),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 10,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, size: 26, color: MomentColors.name),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: MomentColors.primaryText,
            ),
          ),
        ],
      ),
    );
  }
}
