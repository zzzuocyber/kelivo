import 'dart:convert';

import 'chat_bubble_style.dart';

/// A saved bubble color scheme: the user's bubble style paired with the
/// assistant's bubble style. Schemes live in a shared library and can be
/// selected by individual assistants.
class BubbleColorScheme {
  const BubbleColorScheme({
    required this.id,
    required this.name,
    this.userOverrides = const ChatBubbleStyleOverrides(),
    this.assistantOverrides = const ChatBubbleStyleOverrides(),
    this.thinkingToolOverrides = const ChatBubbleStyleOverrides(),
  });

  final String id;
  final String name;
  final ChatBubbleStyleOverrides userOverrides;
  final ChatBubbleStyleOverrides assistantOverrides;
  final ChatBubbleStyleOverrides thinkingToolOverrides;

  BubbleColorScheme copyWith({
    String? id,
    String? name,
    ChatBubbleStyleOverrides? userOverrides,
    ChatBubbleStyleOverrides? assistantOverrides,
    ChatBubbleStyleOverrides? thinkingToolOverrides,
  }) {
    return BubbleColorScheme(
      id: id ?? this.id,
      name: name ?? this.name,
      userOverrides: userOverrides ?? this.userOverrides,
      assistantOverrides: assistantOverrides ?? this.assistantOverrides,
      thinkingToolOverrides: thinkingToolOverrides ?? this.thinkingToolOverrides,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'user': userOverrides.toJson(),
    'assistant': assistantOverrides.toJson(),
    'thinkingTool': thinkingToolOverrides.toJson(),
  };

  factory BubbleColorScheme.fromJson(Map<String, dynamic> json) {
    return BubbleColorScheme(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      userOverrides: _readOverrides(json['user']),
      assistantOverrides: _readOverrides(json['assistant']),
      thinkingToolOverrides: _readOverrides(json['thinkingTool']),
    );
  }

  static ChatBubbleStyleOverrides _readOverrides(Object? value) {
    if (value is Map<String, dynamic>) {
      return ChatBubbleStyleOverrides.fromJson(value);
    }
    if (value is Map) {
      return ChatBubbleStyleOverrides.fromJson(
        Map<String, dynamic>.from(value),
      );
    }
    return const ChatBubbleStyleOverrides();
  }

  /// Encode a whole library for text export / settings persistence.
  static String encodeList(List<BubbleColorScheme> schemes) =>
      jsonEncode(schemes.map((s) => s.toJson()).toList());

  static List<BubbleColorScheme> decodeJsonText(String text) {
    try {
      return decodeList(jsonDecode(text));
    } catch (_) {
      return const <BubbleColorScheme>[];
    }
  }

  static List<BubbleColorScheme> decodeList(Object? value) {
    if (value is! List) return const <BubbleColorScheme>[];
    final result = <BubbleColorScheme>[];
    for (final item in value) {
      if (item is Map<String, dynamic>) {
        result.add(BubbleColorScheme.fromJson(item));
      } else if (item is Map) {
        result.add(BubbleColorScheme.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    return result;
  }
}
