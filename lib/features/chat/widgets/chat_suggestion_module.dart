import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/chat/conversation_suggestion_settings.dart';
import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/app_semantic_colors.dart';
import '../../model/widgets/model_select_sheet.dart';
import 'chat_suggestion_settings_sheet.dart';
import 'tools_sheet_row.dart';

/// Entry row for the chat suggestion settings, sitting under the reasoning
/// slider. The switch, model and prompt live one level down in
/// [showChatSuggestionSheet], so the composer sheet stays a short list of
/// one-line entries instead of stacking controls in place.
class ChatSuggestionModule extends StatelessWidget {
  const ChatSuggestionModule({
    super.key,
    required this.conversationId,
    this.compact = false,
  });

  final String? conversationId;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final id = conversationId;
    if (id == null) return const SizedBox.shrink();
    return Padding(
      key: const ValueKey('chat-suggestion-entry'),
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 16,
        4,
        compact ? 12 : 16,
        compact ? 4 : 12,
      ),
      child: ToolsSheetRow(
        icon: Lucide.MessagesSquare,
        label: '其他设置',
        onTap: () => showChatSuggestionSheet(context, conversationId: id),
        trailing: ToolsSheetRow.chevron(context),
      ),
    );
  }
}

/// Second level of the composer sheet: the suggestion switch, its model and its
/// prompt. Rows reuse [ToolsSheetRow] so this reads as the same kind of card as
/// the world book / instruction entries.
Future<void> showChatSuggestionSheet(
  BuildContext context, {
  required String conversationId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.overlaySurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ChatSuggestionSheet(conversationId: conversationId),
  );
}

class _ChatSuggestionSheet extends StatelessWidget {
  const _ChatSuggestionSheet({required this.conversationId});

  final String conversationId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final chat = context.watch<ChatService>();
    final settings = context.watch<SettingsProvider>();
    final overrides = ConversationSuggestionSettings.fromConversation(
      chat.getConversation(conversationId),
    );
    final enabled = overrides.effectiveEnabled(settings);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 14),
            ToolsSheetRow(
              key: const ValueKey('chat-suggestion-switch'),
              icon: Lucide.Lightbulb,
              label: '聊天建议',
              trailing: IosSwitch(
                value: enabled,
                semanticLabel: '聊天建议',
                onChanged: (value) async {
                  Haptics.soft();
                  await _saveSuggestion(
                    context,
                    conversationId,
                    (current) => current.copyWith(enabled: value),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            ToolsSheetRow(
              key: const ValueKey('chat-suggestion-model'),
              icon: Lucide.Brain,
              label: '模型选择',
              detail: _modelLabel(settings, overrides),
              trailing: ToolsSheetRow.chevron(context),
              onTap: () =>
                  _pickModel(context, settings, overrides, conversationId),
            ),
            const SizedBox(height: 8),
            ToolsSheetRow(
              key: const ValueKey('chat-suggestion-prompt'),
              icon: Lucide.Settings2,
              label: '提示词',
              trailing: ToolsSheetRow.chevron(context),
              onTap: () => showChatSuggestionSettingsSheet(
                context,
                conversationId: conversationId,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _modelLabel(
  SettingsProvider settings,
  ConversationSuggestionSettings overrides,
) {
  final provider = overrides.providerKey ?? settings.suggestionModelProvider;
  final model = overrides.modelId ?? settings.suggestionModelId;
  if (provider == null || model == null) return '使用当前聊天模型';
  final config = settings.getProviderConfig(provider);
  final override = config.modelOverrides[model];
  if (override is Map) {
    final name = (override['name'] as String?)?.trim();
    if (name != null && name.isNotEmpty) return name;
  }
  return model;
}

Future<void> _pickModel(
  BuildContext context,
  SettingsProvider settings,
  ConversationSuggestionSettings overrides,
  String conversationId,
) async {
  final selection = await showModelSelectorWithCurrentChatFallback(
    context,
    initialProviderKey:
        overrides.providerKey ?? settings.suggestionModelProvider,
    initialModelId: overrides.modelId ?? settings.suggestionModelId,
  );
  if (selection == null) return;
  if (selection.providerKey.isEmpty || selection.modelId.isEmpty) return;
  if (!context.mounted) return;
  await _saveSuggestion(
    context,
    conversationId,
    (current) => current.copyWith(
      enabled: true,
      providerKey: selection.providerKey,
      modelId: selection.modelId,
    ),
  );
}

Future<void> _saveSuggestion(
  BuildContext context,
  String conversationId,
  ConversationSuggestionSettings Function(ConversationSuggestionSettings)
  update,
) async {
  try {
    await context.read<ChatService>().updateConversationExtras(
      conversationId,
      (extras) => ConversationSuggestionSettings.writeExtras(
        extras,
        update(ConversationSuggestionSettings.fromExtras(extras)),
      ),
    );
  } catch (_) {
    if (context.mounted) {
      showAppSnackBar(
        context,
        message: '聊天建议设置保存失败',
        type: NotificationType.error,
      );
    }
  }
}
