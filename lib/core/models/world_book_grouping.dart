import 'world_book.dart';

/// Shared grouping rules for world books.
///
/// A book's group is free text; books with the same trimmed label form one
/// group. Ungrouped books (empty label) always come first, the remaining
/// groups are ordered by lower-cased label. Inside a group the stored list
/// order wins, which is the order the user dragged them into.
///
/// The same rule drives both the UI grouping and the injection order, so what
/// the list shows is what gets sent.

/// Trimmed label used as the grouping key. Empty string means "ungrouped".
String normalizeWorldBookGroup(String group) => group.trim();

/// Orders two group labels: ungrouped first, then case-insensitive label order.
int compareWorldBookGroups(String a, String b) {
  final aa = normalizeWorldBookGroup(a);
  final bb = normalizeWorldBookGroup(b);
  if (aa.isEmpty && bb.isNotEmpty) return -1;
  if (aa.isNotEmpty && bb.isEmpty) return 1;
  return aa.toLowerCase().compareTo(bb.toLowerCase());
}

/// Group labels present in [books], in display order.
List<String> worldBookGroupNames(Iterable<WorldBook> books) {
  final names = <String>{};
  for (final book in books) {
    names.add(normalizeWorldBookGroup(book.group));
  }
  return names.toList(growable: false)..sort(compareWorldBookGroups);
}

/// Books grouped by label. Each bucket keeps the incoming order untouched.
Map<String, List<WorldBook>> groupWorldBooks(Iterable<WorldBook> books) {
  final grouped = <String, List<WorldBook>>{};
  for (final book in books) {
    final key = normalizeWorldBookGroup(book.group);
    (grouped[key] ??= <WorldBook>[]).add(book);
  }
  return grouped;
}

/// Flat list ordered exactly as the books are sent: group label first,
/// then the stored order inside each group.
List<WorldBook> orderWorldBooksByGroup(Iterable<WorldBook> books) {
  final grouped = groupWorldBooks(books);
  final names = grouped.keys.toList(growable: false)
    ..sort(compareWorldBookGroups);
  return <WorldBook>[for (final name in names) ...grouped[name]!];
}
