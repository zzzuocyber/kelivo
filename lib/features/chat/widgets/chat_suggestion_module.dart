import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/chat/conversation_suggestion_settings.dart';
import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/app_font_weights.dart';
import '../../model/widgets/model_select_sheet.dart';
import 'chat_suggestion_settings_sheet.dart';

/// Chat suggestion block for the composer sheet, sitting under the reasoning
/// slider. The switch, model and prompt are stored on the conversation itself
/// and only fall back to the global defaults while untouched.
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
    final chat = context.watch<ChatService>();
    final settings = context.watch<SettingsProvider>();
    final conversation = chat.getConversation(id);
    final overrides = ConversationSuggestionSettings.fromConversation(
      conversation,
    );
    final cs = Theme.of(context).colorScheme;
    final enabled = overrides.effectiveEnabled(settings);
    final horizontal = compact ? 14.0 : 28.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 6),
        Divider(
          height: 0.6,
          thickness: 0.6,
          indent: horizontal,
          endIndent: horizontal,
          color: cs.outlineVariant.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontal),
          child: Row(
            children: [
              Icon(
                Lucide.MessagesSquare,
                size: compact ? 18 : 20,
                color: cs.onSurface.withValues(alpha: enabled ? 0.8 : 0.55),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '聊天建议模型',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 14 : 15,
                    fontWeight: AppFontWeights.medium,
                    color: cs.onSurface.withValues(alpha: 0.92),
                  ),
                ),
              ),
              IosSwitch(
                value: enabled,
                semanticLabel: '聊天建议模型',
                onChanged: (value) async {
                  Haptics.soft();
                  await _save(
                    context,
                    (current) => current.copyWith(enabled: value),
                  );
                },
              ),
              const SizedBox(width: 2),
              _GearButton(
                compact: compact,
                onTap: () => showChatSuggestionSettingsSheet(
                  context,
                  conversationId: id,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontal - 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _pickModel(context, settings, overrides),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  Text(
                    '模型选择',
                    style: TextStyle(
                      fontSize: compact ? 13 : 14,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _modelLabel(settings, overrides),
                      maxLines: 1,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 13 : 14,
                        color: cs.onSurface.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Lucide.ChevronRight,
                    size: 16,
                    color: cs.onSurface.withValues(alpha: 0.4),
                  ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(height: compact ? 4 : 10),
      ],
    );
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
    await _save(
      context,
      (current) => current.copyWith(
        enabled: true,
        providerKey: selection.providerKey,
        modelId: selection.modelId,
      ),
    );
  }

  Future<void> _save(
    BuildContext context,
    ConversationSuggestionSettings Function(ConversationSuggestionSettings)
    update,
  ) async {
    final id = conversationId;
    if (id == null) return;
    try {
      await context.read<ChatService>().updateConversationExtras(
        id,
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
}

class _GearButton extends StatelessWidget {
  const _GearButton({required this.onTap, this.compact = false});

  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkResponse(
      onTap: onTap,
      radius: 20,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          Lucide.Settings2,
          size: compact ? 17 : 18,
          color: cs.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
