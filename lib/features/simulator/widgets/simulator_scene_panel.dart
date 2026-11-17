import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../theme/design_tokens.dart';

/// Scene artwork at the top of a simulation: a collapsible that is open by
/// default, exactly like the layout memo says. Without a path it shows a slim
/// placeholder that asks for one instead of reserving empty height.
class SimulatorScenePanel extends StatefulWidget {
  const SimulatorScenePanel({
    super.key,
    required this.path,
    required this.onEdit,
  });

  final String? path;
  final VoidCallback onEdit;

  @override
  State<SimulatorScenePanel> createState() => _SimulatorScenePanelState();
}

class _SimulatorScenePanelState extends State<SimulatorScenePanel> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasImage = widget.path != null && widget.path!.trim().isNotEmpty;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
        0,
      ),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.xs,
                AppSpacing.xs,
                AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '🖼 场景图',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: cs.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '填图片路径',
                    onPressed: widget.onEdit,
                    icon: Icon(
                      Lucide.Image,
                      size: 16,
                      color: cs.onSurface.withValues(alpha: 0.55),
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 28,
                    ),
                  ),
                  Icon(
                    _open ? Lucide.ChevronUp : Lucide.ChevronDown,
                    size: 16,
                    color: cs.onSurface.withValues(alpha: 0.4),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: hasImage
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(
                        File(widget.path!),
                        height: 150,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stack) =>
                            _missing(context),
                      ),
                    )
                  : _placeholder(context),
            ),
        ],
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: widget.onEdit,
      child: Container(
        height: 120,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.onSurface.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.onSurface.withValues(alpha: 0.10)),
        ),
        child: Text(
          '点这里填图片路径',
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurface.withValues(alpha: 0.45),
          ),
        ),
      ),
    );
  }

  Widget _missing(BuildContext context) {
    return Container(
      height: 90,
      alignment: Alignment.center,
      child: const Text('图片找不到', style: TextStyle(fontSize: 12)),
    );
  }
}
