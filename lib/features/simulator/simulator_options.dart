/// Reads the option block out of an assistant reply.
///
/// The model writes it as a fenced-looking block so nothing else in the text
/// can be mistaken for an option:
///
/// ```
/// :::选项
/// A. 推门进仓库
/// B. 转身离开码头
/// :::
/// ```
abstract final class SimulatorOptions {
  static const String openMarker = ':::选项';
  static const String closeMarker = ':::';

  /// Letters that become the fixed square keys. `E` is the free-text field,
  /// so a line the model labels `E` stays inside the folded original text and
  /// never becomes a button.
  static const List<String> buttonLetters = <String>['A', 'B', 'C', 'D'];

  static final RegExp _line = RegExp(
    r'^\s*([A-Da-d])\s*[.、,，:：)）]?\s*(.+?)\s*$',
  );

  /// Options of the last complete block. Empty while the block is still
  /// streaming (no closing marker yet).
  static List<SimulatorOption> parse(String text) {
    final block = _locate(text);
    if (block == null) return const <SimulatorOption>[];
    final found = <String, String>{};
    for (final line
        in text.substring(block.innerStart, block.innerEnd).split('\n')) {
      final match = _line.firstMatch(line);
      if (match == null) continue;
      final letter = match.group(1)!.toUpperCase();
      final body = match.group(2)!.trim();
      if (body.isEmpty) continue;
      found.putIfAbsent(letter, () => body);
    }
    return <SimulatorOption>[
      for (final letter in buttonLetters)
        if (found[letter] != null)
          SimulatorOption(letter: letter, text: found[letter]!),
    ];
  }

  /// Replaces the block with a folded copy, so the raw lines do not show twice
  /// (once as text, once as the square keys). The text itself is untouched --
  /// folding it keeps it readable for anyone who taps the summary.
  static String collapseForDisplay(String text) {
    final block = _locate(text);
    if (block == null) return text;
    final inner = text.substring(block.innerStart, block.innerEnd).trim();
    if (inner.isEmpty) {
      return text.replaceRange(block.start, block.end, '').trimRight();
    }
    final replacement =
        '<details><summary>选项</summary>\n\n$inner\n\n</details>';
    return text.replaceRange(block.start, block.end, replacement);
  }

  static _Block? _locate(String text) {
    final open = text.lastIndexOf(openMarker);
    if (open < 0) return null;
    final firstBreak = text.indexOf('\n', open);
    if (firstBreak < 0) return null;
    final close = text.indexOf(closeMarker, firstBreak);
    if (close < 0) return null;
    var end = close + closeMarker.length;
    if (end < text.length && text[end] == '\n') end++;
    return _Block(
      start: open,
      end: end,
      innerStart: firstBreak + 1,
      innerEnd: close,
    );
  }
}

class SimulatorOption {
  const SimulatorOption({required this.letter, required this.text});

  final String letter;
  final String text;
}

class _Block {
  const _Block({
    required this.start,
    required this.end,
    required this.innerStart,
    required this.innerEnd,
  });

  final int start;
  final int end;
  final int innerStart;
  final int innerEnd;
}
