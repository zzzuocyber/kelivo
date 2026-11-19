import '../../models/conversation.dart';
import '../../providers/settings_provider.dart';

/// Per-conversation chat suggestion overrides.
///
/// Everything is stored inside `conversations.extras_json` under
/// [extrasKey]; the database schema is never touched. A null field means
/// "follow the global setting".
class ConversationSuggestionSettings {
  const ConversationSuggestionSettings({
    this.enabled,
    this.providerKey,
    this.modelId,
    this.prompt,
  });

  static const String extrasKey = 'chatSuggestion';

  /// null follows the global suggestion switch.
  final bool? enabled;

  /// Suggestion model for this conversation; null follows the global model,
  /// which in turn falls back to the conversation's chat model.
  final String? providerKey;
  final String? modelId;

  /// null follows the global suggestion prompt.
  final String? prompt;

  static ConversationSuggestionSettings fromConversation(
    Conversation? conversation,
  ) => fromExtras(conversation?.extras ?? const <String, dynamic>{});

  static ConversationSuggestionSettings fromExtras(
    Map<String, dynamic> extras,
  ) {
    final raw = extras[extrasKey];
    if (raw is! Map) return const ConversationSuggestionSettings();
    final enabled = raw['enabled'];
    final provider = raw['provider'];
    final model = raw['model'];
    final prompt = raw['prompt'];
    return ConversationSuggestionSettings(
      enabled: enabled is bool ? enabled : null,
      providerKey: provider is String && provider.isNotEmpty ? provider : null,
      modelId: model is String && model.isNotEmpty ? model : null,
      prompt: prompt is String && prompt.trim().isNotEmpty ? prompt : null,
    );
  }

  bool effectiveEnabled(SettingsProvider settings) =>
      enabled ?? settings.isSuggestionGenerationEnabled;

  String effectivePrompt(SettingsProvider settings) =>
      prompt ?? settings.suggestionPrompt;

  String? get modelKey => (providerKey != null && modelId != null)
      ? '$providerKey::$modelId'
      : null;

  bool get hasOwnModel => modelKey != null;

  ConversationSuggestionSettings copyWith({
    bool? enabled,
    String? providerKey,
    String? modelId,
    String? prompt,
    bool clearModel = false,
    bool clearPrompt = false,
  }) {
    return ConversationSuggestionSettings(
      enabled: enabled ?? this.enabled,
      providerKey: clearModel ? null : (providerKey ?? this.providerKey),
      modelId: clearModel ? null : (modelId ?? this.modelId),
      prompt: clearPrompt ? null : (prompt ?? this.prompt),
    );
  }

  Map<String, dynamic> toExtrasMap() {
    final map = <String, dynamic>{};
    if (enabled != null) map['enabled'] = enabled;
    if (providerKey != null && modelId != null) {
      map['provider'] = providerKey;
      map['model'] = modelId;
    }
    if (prompt != null) map['prompt'] = prompt;
    return map;
  }

  /// Returns the new extras map with [next] written in. An empty result
  /// removes the key entirely so untouched conversations stay clean.
  static Map<String, dynamic> writeExtras(
    Map<String, dynamic> extras,
    ConversationSuggestionSettings next,
  ) {
    final merged = {...extras};
    final encoded = next.toExtrasMap();
    if (encoded.isEmpty) {
      merged.remove(extrasKey);
    } else {
      merged[extrasKey] = encoded;
    }
    return merged;
  }
}
