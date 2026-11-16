import 'package:markstream/markstream_core.dart';

/// 找出 Markdown 里属于「代码」的区间，供视觉正则跳过。
///
/// 覆盖两类：
/// 1. 围栏代码块：``` 与 ~~~，允许最多 3 个前导空格，未闭合时保护到文本末尾
/// 2. 行内代码：`x`、``x`` 这类反引号包裹，按反引号长度配对
///
/// 缩进代码块（4 空格缩进）暂不识别：列表续行也用缩进，误判风险高于收益。
List<SourceSpan> markdownCodeSpans(String text) {
  if (text.isEmpty) return const <SourceSpan>[];
  final fences = _fenceSpans(text);
  final inline = _inlineCodeSpans(text, fences);
  if (inline.isEmpty) return fences;
  return <SourceSpan>[...fences, ...inline];
}

class _Line {
  const _Line(this.start, this.end);
  final int start;
  final int end;
}

List<_Line> _lines(String text) {
  final result = <_Line>[];
  var start = 0;
  for (var i = 0; i <= text.length; i++) {
    final atEnd = i == text.length;
    if (!atEnd && text.codeUnitAt(i) != 10) continue;
    var end = i;
    if (end > start && text.codeUnitAt(end - 1) == 13) end--;
    result.add(_Line(start, end));
    start = i + 1;
  }
  return result;
}

class _Fence {
  const _Fence(this.character, this.length);
  final int character;
  final int length;
}

/// 判断一行是否是围栏代码块的起始行。
_Fence? _fenceOpen(String text, _Line line) {
  var i = line.start;
  var indent = 0;
  while (i < line.end && text.codeUnitAt(i) == 32 && indent < 4) {
    i++;
    indent++;
  }
  if (indent > 3 || i >= line.end) return null;
  final character = text.codeUnitAt(i);
  if (character != 96 && character != 126) return null;
  var length = 0;
  while (i < line.end && text.codeUnitAt(i) == character) {
    i++;
    length++;
  }
  if (length < 3) return null;
  // 反引号围栏的 info string 里不能出现反引号，否则不是围栏。
  if (character == 96) {
    for (var j = i; j < line.end; j++) {
      if (text.codeUnitAt(j) == 96) return null;
    }
  }
  return _Fence(character, length);
}

bool _fenceClose(String text, _Line line, _Fence open) {
  var i = line.start;
  var indent = 0;
  while (i < line.end && text.codeUnitAt(i) == 32 && indent < 4) {
    i++;
    indent++;
  }
  if (indent > 3) return false;
  var length = 0;
  while (i < line.end && text.codeUnitAt(i) == open.character) {
    i++;
    length++;
  }
  if (length < open.length) return false;
  while (i < line.end) {
    final unit = text.codeUnitAt(i);
    if (unit != 32 && unit != 9) return false;
    i++;
  }
  return true;
}

List<SourceSpan> _fenceSpans(String text) {
  final lines = _lines(text);
  final spans = <SourceSpan>[];
  var index = 0;
  while (index < lines.length) {
    final line = lines[index];
    final open = _fenceOpen(text, line);
    if (open == null) {
      index++;
      continue;
    }
    var cursor = index + 1;
    int? end;
    while (cursor < lines.length) {
      if (_fenceClose(text, lines[cursor], open)) {
        end = lines[cursor].end;
        break;
      }
      cursor++;
    }
    if (end == null) {
      // 还在流式输出里没闭合：保护到当前末尾，避免半截代码被改写。
      spans.add(SourceSpan(line.start, text.length));
      break;
    }
    spans.add(SourceSpan(line.start, end));
    index = cursor + 1;
  }
  return spans;
}

bool _insideAny(List<SourceSpan> spans, int offset) {
  for (final span in spans) {
    if (offset >= span.start && offset < span.end) return true;
  }
  return false;
}

int _backtickRun(String text, int start, int limit) {
  var i = start;
  while (i < limit && text.codeUnitAt(i) == 96) {
    i++;
  }
  return i - start;
}

bool _escaped(String text, int index) {
  var backslashes = 0;
  var i = index - 1;
  while (i >= 0 && text.codeUnitAt(i) == 92) {
    backslashes++;
    i--;
  }
  return backslashes.isOdd;
}

List<SourceSpan> _inlineCodeSpans(String text, List<SourceSpan> fences) {
  final spans = <SourceSpan>[];
  var i = 0;
  while (i < text.length) {
    if (text.codeUnitAt(i) != 96) {
      i++;
      continue;
    }
    if (_insideAny(fences, i) || _escaped(text, i)) {
      i++;
      continue;
    }
    final length = _backtickRun(text, i, text.length);
    var cursor = i + length;
    int? close;
    while (cursor < text.length) {
      if (text.codeUnitAt(cursor) != 96) {
        cursor++;
        continue;
      }
      final run = _backtickRun(text, cursor, text.length);
      if (run == length) {
        close = cursor;
        break;
      }
      cursor += run;
    }
    if (close == null) {
      i += length;
      continue;
    }
    spans.add(SourceSpan(i, close + length));
    i = close + length;
  }
  return spans;
}
