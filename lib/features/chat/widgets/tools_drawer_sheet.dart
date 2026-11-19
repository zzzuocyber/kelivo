import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';
import '../../../theme/app_semantic_colors.dart';
import '../../model/widgets/ocr_prompt_sheet.dart';
import 'conversation_background_sheet.dart';
import 'tools_sheet_row.dart';

/// Drawer for features that are used less often or do not fit a group.
/// Keeping them here leaves room in the main tools sheet.
Future<void> showToolsDrawerSheet(
  BuildContext context, {
  String? conversationId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.overlaySurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _ToolsDrawerSheet(conversationId: conversationId),
  );
}

class _ToolsDrawerSheet extends StatelessWidget {
  const _ToolsDrawerSheet({this.conversationId});

  final String? conversationId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    final hasOcrModel =
        settings.ocrModelProvider != null && settings.ocrModelId != null;
    final hasConversation = conversationId != null;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '抽屉',
              style: TextStyle(
                fontSize: 17,
                fontWeight: AppFontWeights.semibold,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            if (hasOcrModel)
              ToolsSheetRow(
                icon: Lucide.Eye,
                label: 'OCR 识别',
                selected: settings.ocrEnabled,
                onTap: () async {
                  Haptics.light();
                  await context.read<SettingsProvider>().setOcrEnabled(
                    !settings.ocrEnabled,
                  );
                  if (context.mounted) Navigator.of(context).maybePop();
                },
                onLongPress: () {
                  Haptics.light();
                  showOcrPromptSheet(context);
                },
              ),
            if (hasOcrModel && hasConversation) const SizedBox(height: 8),
            if (hasConversation)
              ToolsSheetRow(
                icon: Lucide.Image,
                label: '对话背景图',
                onTap: () {
                  Haptics.light();
                  showConversationBackgroundSheet(
                    context,
                    conversationId: conversationId!,
                  );
                },
                trailing: ToolsSheetRow.chevron(context),
              ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
