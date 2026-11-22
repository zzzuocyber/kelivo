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
  /// [summaryText] 是我手写的剧情概括：摘要模式下若给了，就用它替代规则压缩，
  /// 三场景共用同一份，不再各压各的。
  /// [timeLine] 是可覆盖的故事时间句；默认读 [store] 的故事时钟，让模型明确知道
  /// 现在是星期几、上午还是晚上。离线补算传消息发生那一刻的故事时间。
  static BuiltContext build({
    required String name,
    required String scene,
    required List<String> memoryLines,
    required String where,
    required SocialStore store,
    String topic = '',
    String summaryText = '',
    String? timeLine,
    String affinityLine = '',
    List<String> groupPulseLines = const <String>[],
  }) {
    final sections = <String>[];

    final time = (timeLine ?? store.storyTimeLine).trim();
    if (time.isNotEmpty) {
      sections.add('【时间】\n$time');
    }

    final whereTrimmed = where.trim();
    if (whereTrimmed.isNotEmpty) {
      sections.add('【此刻】\n$whereTrimmed');
    }

    final topicTrimmed = topic.trim();
    if (topicTrimmed.isNotEmpty) {
      sections.add('【最近大家在聊】\n$topicTrimmed');
    }

    // 跟「我」的关系：好感拉满就该明显更护着我、愿意出头，
    // 不能只用来算粘人概率而模型全程看不见。
    final affinityTrimmed = affinityLine.trim();
    if (affinityTrimmed.isNotEmpty) {
      sections.add('【你和「我」的关系】\n$affinityTrimmed');
    }

    // 群里此刻正在发生的事（别人说的），补私聊记忆只捞本人发言的缺口。
    final pulses = groupPulseLines
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (pulses.isNotEmpty) {
      sections.add('【群里最近发生的事（别人说的）】\n${pulses.join('\n')}');
    }

    final lines = memoryLines
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final mode = store.contextMode(scene);
    final manual = summaryText.trim();
    if (mode.isSummary && manual.isNotEmpty) {
      // 摘要模式 + 我写了概括：整段用我这份，三场景共用，不再规则压缩。
      sections.add('【剧情概括（我写的）】\n$manual');
    } else if (lines.isNotEmpty) {
      // 完整模式照旧给全量记录；摘要模式没写概括时才退回规则压缩。
      final body = mode.isSummary ? socialSummarize(lines) : lines.join('\n');
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
