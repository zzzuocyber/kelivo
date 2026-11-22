import '../utils/token_estimator.dart';
import 'social_store.dart';

/// 三场景上下文联动的构建器（纯函数，不碰数据库）。
///
/// 调用方把「别的场景里跟某个角色有关的记录」整理成若干行传进来，
/// 这里按摘要/完整开关压好、加上这个角色此刻的去处，拼成一段给模型看的话，
/// 同时算出这段上下文的 token 数，交给调用方累计。
class SocialContextBuilder {
  SocialContextBuilder._();

  /// [memoryLines] 是别的场景里跟 [name] 有关的记录（一行一件事）。
  /// [scene] 是当前场景，用来取对应的摘要/完整开关。
  /// [where] 是这个人此刻的去处（可以是 SocialWhereabouts.promptLine）。
  /// [topic] 是当前话题（可选），有就一起注入，保证三处话题感一致。
  static BuiltContext build({
    required String name,
    required String scene,
    required List<String> memoryLines,
    required String where,
    required SocialStore store,
    String topic = '',
  }) {
    final sections = <String>[];

    final whereTrimmed = where.trim();
    if (whereTrimmed.isNotEmpty) {
      sections.add('【此刻】\n$whereTrimmed');
    }

    final topicTrimmed = topic.trim();
    if (topicTrimmed.isNotEmpty) {
      sections.add('【最近大家在聊】\n$topicTrimmed');
    }

    final lines = memoryLines
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.isNotEmpty) {
      final mode = store.contextMode(scene);
      final body = mode.isSummary
          ? socialSummarize(lines)
          : lines.join('\n');
      final label = mode.isSummary ? '别处提过（大意）' : '别处聊过';
      sections.add('【$name 在$label】\n$body');
    }

    final text = sections.join('\n\n');
    return BuiltContext(
      text: text,
      tokens: estimateTokens(text),
    );
  }
}

class BuiltContext {
  const BuiltContext({required this.text, required this.tokens});

  final String text;
  final int tokens;
  bool get isEmpty => text.trim().isEmpty;
}
