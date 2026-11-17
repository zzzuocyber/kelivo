/// Reads the other blocks an assistant can write inside a simulation.
///
/// Same marker shape as the options block:
///
/// ```
/// :::状态
/// ### 沈川 · 在场
/// - 体力 62%　左肩受伤
/// :::
/// ```
abstract final class SimulatorBlocks {
  static const String statusName = '状态';
  static const String endingName = '结局';

  /// Content between `:::<name>` and the closing `:::`, or null when the block
  /// is absent or still streaming (no closing marker yet).
  static String? innerOf(String text, String name) {
    final open = ':::$name';
    final start = text.lastIndexOf(open);
    if (start < 0) return null;
    final bodyStart = text.indexOf('\n', start);
    if (bodyStart < 0) return null;
    final close = text.indexOf(':::', bodyStart);
    if (close < 0) return null;
    final inner = text.substring(bodyStart + 1, close).trim();
    return inner.isEmpty ? null : inner;
  }

  /// Removes complete blocks of the given names, so the fixed panels can show
  /// them instead of the message body repeating them.
  static String strip(String text, List<String> names) {
    var result = text;
    for (final name in names) {
      final open = ':::$name';
      final start = result.lastIndexOf(open);
      if (start < 0) continue;
      final bodyStart = result.indexOf('\n', start);
      if (bodyStart < 0) continue;
      final close = result.indexOf(':::', bodyStart);
      if (close < 0) continue;
      var end = close + 3;
      if (end < result.length && result[end] == '\n') end++;
      result = result.replaceRange(start, end, '');
    }
    return result.trimRight();
  }

  /// Splits a status block into sections by its `###` headings. Content without
  /// any heading becomes a single untitled section.
  static List<SimulatorStatusSection> statusSections(String inner) {
    final sections = <SimulatorStatusSection>[];
    String? title;
    final body = StringBuffer();

    void flush() {
      final text = body.toString().trim();
      if (text.isEmpty && title == null) return;
      sections.add(SimulatorStatusSection(title: title, body: text));
      body.clear();
    }

    for (final line in inner.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('###')) {
        flush();
        title = trimmed.substring(3).trim();
        continue;
      }
      if (trimmed.startsWith('##')) {
        flush();
        title = trimmed.replaceFirst(RegExp(r'^#+\s*'), '').trim();
        continue;
      }
      body.writeln(line);
    }
    flush();
    return sections;
  }

  /// Renders the sections as nested `<details>`, which is what the app's
  /// markdown renderer already draws as collapsible cards (light surface even
  /// in dark mode, the same treatment as chat code and tables).
  static String statusDetailsMarkdown(List<SimulatorStatusSection> sections) {
    final buffer = StringBuffer();
    buffer.writeln('<details><summary>🗂 状态 · 点开分人查</summary>');
    buffer.writeln();
    for (final section in sections) {
      final title = section.title ?? '状态';
      buffer.writeln('<details><summary>$title</summary>');
      buffer.writeln();
      if (section.body.isNotEmpty) buffer.writeln(section.body);
      buffer.writeln();
      buffer.writeln('</details>');
      buffer.writeln();
    }
    buffer.writeln('</details>');
    return buffer.toString();
  }
}

class SimulatorStatusSection {
  const SimulatorStatusSection({required this.title, required this.body});

  final String? title;
  final String body;
}
