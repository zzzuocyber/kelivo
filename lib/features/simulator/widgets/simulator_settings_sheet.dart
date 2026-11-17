import 'package:flutter/material.dart';

import 'package:Kelivo/theme/app_semantic_colors.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../theme/design_tokens.dart';
import '../../chat/widgets/tools_sheet_row.dart';

/// ⚙ 点开的五行面板。每一行都接到聊天页现成的东西上，不另开新流程：
/// 模型走会话级模型选择，「临时系统提示词」就是对话系统提示词那个编辑器，
/// 世界书 / 指令注入复用对话面板，导出复用现有会话导出。
class SimulatorSettingsSheet extends StatelessWidget {
  const SimulatorSettingsSheet({
    super.key,
    required this.onModel,
    required this.onSystemPrompt,
    required this.onWorldBook,
    required this.onInjection,
    required this.onExport,
  });

  final VoidCallback onModel;
  final VoidCallback onSystemPrompt;
  final VoidCallback onWorldBook;
  final VoidCallback onInjection;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final chevron = ToolsSheetRow.chevron(context);
    Widget row({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: ToolsSheetRow(
          icon: icon,
          label: label,
          onTap: onTap,
          trailing: chevron,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row(icon: Lucide.Bot, label: '模型', onTap: onModel),
          row(icon: Lucide.FileText, label: '临时系统提示词', onTap: onSystemPrompt),
          row(icon: Lucide.BookOpen, label: '世界书', onTap: onWorldBook),
          row(icon: Lucide.Layers, label: '指令注入', onTap: onInjection),
          row(icon: Lucide.Download, label: '导出这条记录', onTap: onExport),
        ],
      ),
    );
  }
}

/// 弹出面板；每行先收起面板，再调用调用方的现成入口。
Future<void> showSimulatorSettingsSheet(
  BuildContext context, {
  required VoidCallback onModel,
  required VoidCallback onSystemPrompt,
  required VoidCallback onWorldBook,
  required VoidCallback onInjection,
  required VoidCallback onExport,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.overlaySurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) {
      Future<void> pick(VoidCallback action) async {
        await Navigator.of(sheetCtx).maybePop();
        action();
      }

      return SafeArea(
        top: false,
        child: SimulatorSettingsSheet(
          onModel: () => pick(onModel),
          onSystemPrompt: () => pick(onSystemPrompt),
          onWorldBook: () => pick(onWorldBook),
          onInjection: () => pick(onInjection),
          onExport: () => pick(onExport),
        ),
      );
    },
  );
}
