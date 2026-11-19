import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/chat/conversation_suggestion_settings.dart';
import '../../../theme/app_font_weights.dart';
import '../../../theme/app_semantic_colors.dart';

/// Per-conversation chat suggestion settings: only the prompt for now, saved
/// on the conversation itself. Falls back to the global prompt until edited.
Future<void> showChatSuggestionSettingsSheet(
  BuildContext context, {
  required String conversationId,
}) async {
  final cs = Theme.of(context).colorScheme;
  final settings = context.read<SettingsProvider>();
  final chat = context.read<ChatService>();
  final overrides = ConversationSuggestionSettings.fromConversation(
    chat.getConversation(conversationId),
  );
  final controller = TextEditingController(
    text: overrides.effectivePrompt(settings),
  );
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.overlaySurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
                '提示词',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: AppFontWeights.semibold,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                maxLines: 8,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: ctx.appColors.surfaceFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: cs.primary.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  TextButton(
                    onPressed: () async {
                      await _save(chat, conversationId, (current) {
                        return current.copyWith(clearPrompt: true);
                      });
                      if (!ctx.mounted) return;
                      controller.text = settings.suggestionPrompt;
                    },
                    child: const Text('恢复默认'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () async {
                      final text = controller.text.trim();
                      await _save(chat, conversationId, (current) {
                        return text.isEmpty
                            ? current.copyWith(clearPrompt: true)
                            : current.copyWith(prompt: text);
                      });
                      if (ctx.mounted) Navigator.of(ctx).maybePop();
                    },
                    child: const Text('保存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> _save(
  ChatService chat,
  String conversationId,
  ConversationSuggestionSettings Function(ConversationSuggestionSettings)
  update,
) async {
  await chat.updateConversationExtras(
    conversationId,
    (extras) => ConversationSuggestionSettings.writeExtras(
      extras,
      update(ConversationSuggestionSettings.fromExtras(extras)),
    ),
  );
}
