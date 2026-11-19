import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart' as lucide;
import 'package:provider/provider.dart';

import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/chat/conversation_background.dart';
import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/app_font_weights.dart';
import '../../../theme/app_semantic_colors.dart';
import 'tools_sheet_row.dart';

/// Second-level sheet for this conversation's background image. The composer
/// sheet no longer carries an inline switch; the follow-assistant choice lives
/// here instead.
Future<void> showConversationBackgroundSheet(
  BuildContext context, {
  required String conversationId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.overlaySurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) =>
        _ConversationBackgroundSheet(conversationId: conversationId),
  );
}

class _ConversationBackgroundSheet extends StatefulWidget {
  const _ConversationBackgroundSheet({required this.conversationId});

  final String conversationId;

  @override
  State<_ConversationBackgroundSheet> createState() =>
      _ConversationBackgroundSheetState();
}

class _ConversationBackgroundSheetState
    extends State<_ConversationBackgroundSheet> {
  bool _saving = false;

  Future<void> _pick() async {
    if (_saving) return;
    final chat = context.read<ChatService>();
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        imageQuality: 85,
      );
      if (file == null || !mounted) return;
      setState(() => _saving = true);
      await ConversationBackgroundService(
        chat,
      ).setImage(widget.conversationId, file.path);
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: '已设置对话背景图',
        type: NotificationType.success,
      );
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: '设置失败：$error',
        type: NotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clear() async {
    if (_saving) return;
    final chat = context.read<ChatService>();
    setState(() => _saving = true);
    try {
      await ConversationBackgroundService(chat).clear(widget.conversationId);
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: '已删除对话背景图，恢复助手背景',
        type: NotificationType.success,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final chat = context.watch<ChatService>();
    final conversation = chat.getConversation(widget.conversationId);
    final follows = ConversationBackground.followsAssistant(conversation);
    final path = ConversationBackground.pathOf(conversation);

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
              '对话背景图',
              style: TextStyle(
                fontSize: 17,
                fontWeight: AppFontWeights.semibold,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            ToolsSheetRow(
              icon: Lucide.Link2,
              label: '跟随助手背景',
              selected: follows,
              onTap: _saving
                  ? null
                  : () {
                      Haptics.light();
                      if (follows) {
                        _pick();
                      } else {
                        _clear();
                      }
                    },
              trailing: Icon(
                follows ? Lucide.CheckCircle : lucide.LucideIcons.circle,
                size: 20,
                color: follows
                    ? cs.primary
                    : cs.onSurface.withValues(alpha: 0.3),
              ),
            ),
            const SizedBox(height: 8),
            ToolsSheetRow(
              icon: Lucide.Image,
              label: path == null ? '选择背景图' : '更换背景图',
              subtitle: path == null ? null : '已使用本对话自己的图片',
              onTap: _saving ? null : _pick,
              trailing: path == null
                  ? ToolsSheetRow.chevron(context)
                  : const Icon(Lucide.Check, size: 18),
            ),
            if (path != null) ...[
              const SizedBox(height: 8),
              ToolsSheetRow(
                icon: Lucide.Trash2,
                label: '删除背景图',
                onTap: _saving ? null : _clear,
              ),
            ],
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
