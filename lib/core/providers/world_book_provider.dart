import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../database/business_preferences.dart';
import '../models/world_book.dart';
import '../models/world_book_grouping.dart';
import '../models/world_book_grouping_rules.dart';
import '../services/world_book_store.dart';

class WorldBookProvider with ChangeNotifier {
  WorldBookProvider({required BusinessPreferences preferences})
    : _store = WorldBookStore(preferences);

  final WorldBookStore _store;
  List<WorldBook> _books = const <WorldBook>[];
  bool _initialized = false;
  Future<void>? _initializationFuture;
  Future<void> _bookOperationTail = Future<void>.value();
  Map<String, List<String>> _activeIdsByAssistant =
      const <String, List<String>>{};
  Map<String, bool> _collapsedBooks = const <String, bool>{};
  WorldBookGrouping _grouping = const WorldBookGrouping();

  List<WorldBook> get books => List<WorldBook>.unmodifiable(_books);

  Map<String, String> get groups => Map.unmodifiable(_grouping.names);

  String? groupIdForBook(String bookId) => _grouping.memberships[bookId];

  List<WorldBook> booksInGroup(String? groupId) => [
    for (final book in _books)
      if (groupIdForBook(book.id) == groupId) book,
  ];

  bool isGroupNameAvailable(String name, {String? exceptId}) {
    final normalized = name.trim().toLowerCase();
    return normalized.isNotEmpty &&
        !_grouping.names.entries.any(
          (entry) =>
              entry.key != exceptId && entry.value.toLowerCase() == normalized,
        );
  }

  Future<String> createGroup(String name) => _serializeBookOperation(() async {
    final id = const Uuid().v4();
    final validated = _validateGroupName(name);
    await _saveGrouping(
      WorldBookGrouping(
        names: {id: validated, ..._grouping.names},
        memberships: _grouping.memberships,
      ),
    );
    return id;
  });

  Future<void> renameGroup(String id, String name) =>
      _serializeBookOperation(() async {
        if (!_grouping.names.containsKey(id)) return;
        final validated = _validateGroupName(name, exceptId: id);
        await _saveGrouping(
          WorldBookGrouping(
            names: {..._grouping.names, id: validated},
            memberships: _grouping.memberships,
          ),
        );
      });

  Future<void> deleteGroup(String id) => _serializeBookOperation(() async {
    if (!_grouping.names.containsKey(id)) return;
    await _saveGrouping(
      WorldBookGrouping(
        names: Map.of(_grouping.names)..remove(id),
        memberships: Map.of(_grouping.memberships)
          ..removeWhere((_, groupId) => groupId == id),
      ),
    );
  });

  Future<void> moveBooksToGroup(Set<String> bookIds, String? groupId) =>
      _serializeBookOperation(() async {
        final grouping = _groupingAfterMove(bookIds, groupId);
        if (grouping != null) await _saveGrouping(grouping);
      });

  WorldBookGrouping? _groupingAfterMove(Set<String> bookIds, String? groupId) {
    if (groupId != null && !_grouping.names.containsKey(groupId)) {
      throw ArgumentError.value(groupId);
    }
    final memberships = Map.of(_grouping.memberships);
    for (final book in _books) {
      if (!bookIds.contains(book.id)) continue;
      if (groupId == null) {
        memberships.remove(book.id);
      } else {
        memberships[book.id] = groupId;
      }
    }
    if (mapEquals(memberships, _grouping.memberships)) return null;
    return WorldBookGrouping(names: _grouping.names, memberships: memberships);
  }

  String _validateGroupName(String name, {String? exceptId}) {
    if (!isGroupNameAvailable(name, exceptId: exceptId)) {
      throw ArgumentError.value(name);
    }
    return name.trim();
  }

  Future<void> _saveGrouping(WorldBookGrouping grouping) async {
    await _store.saveGrouping(grouping);
    _grouping = grouping;
    notifyListeners();
  }

  WorldBook? getById(String id) {
    try {
      return _books.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  List<String> activeBookIdsFor(String? assistantId) {
    final key = WorldBookStore.assistantKey(assistantId);
    if (_activeIdsByAssistant.containsKey(key)) {
      return List<String>.unmodifiable(_activeIdsByAssistant[key]!);
    }
    final fallback =
        _activeIdsByAssistant[WorldBookStore.assistantKey(null)] ??
        const <String>[];
    return List<String>.unmodifiable(fallback);
  }

  bool isBookActive(String id, {String? assistantId}) =>
      activeBookIdsFor(assistantId).contains(id);

  /// Group labels in display order. Ungrouped (empty) comes first, then the
  /// groups in the order stored by the upstream grouping model.
  ///
  /// Bridge: our UI keeps reading group *labels*, while the grouping data now
  /// lives in the upstream [WorldBookGrouping] (id -> name + book -> id).
  List<String> get groupNames {
    final labels = <String>{''};
    for (final name in _grouping.names.values) {
      labels.add(name.trim());
    }
    return labels.toList()..sort(compareWorldBookGroups);
  }

  /// Books split by group label, in display order.
  ///
  /// Bridge: resolve each book's group via the upstream membership table
  /// instead of the legacy `book.group` free-text field.
  Map<String, List<WorldBook>> get groupedBooks {
    final grouped = <String, List<WorldBook>>{};
    for (final book in _books) {
      final groupId = groupIdForBook(book.id);
      final label = groupId == null ? '' : (_grouping.names[groupId] ?? '');
      (grouped[normalizeWorldBookGroup(label)] ??= <WorldBook>[]).add(book);
    }
    return grouped;
  }

  List<WorldBook> activeBooksFor(String? assistantId, {List<String>? bookIds}) {
    final ids = (bookIds ?? activeBookIdsFor(assistantId)).toSet();
    final selected = _books
        .where((book) => book.enabled && ids.contains(book.id))
        .toList(growable: false);
    // Injection order mirrors the visible grouping: group label first, then the
    // order dragged inside each group. Priority still wins over this (entries
    // are sorted by priority later).
    final grouped = groupedBooks;
    final ordered = <WorldBook>[];
    for (final label in groupNames) {
      for (final book in grouped[label] ?? const <WorldBook>[]) {
        if (selected.contains(book)) ordered.add(book);
      }
    }
    return ordered;
  }

  bool isBookCollapsed(String id) => _collapsedBooks[id] ?? false;

  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    return _initializationFuture ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      await loadAll();
      _initialized = true;
    } finally {
      _initializationFuture = null;
    }
  }

  Future<T> _serializeBookOperation<T>(Future<T> Function() operation) {
    final result = _bookOperationTail.then((_) => operation());
    _bookOperationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> loadAll() => _serializeBookOperation(_loadAll);

  /// One-time bridge from the legacy `book.group` free-text field to the
  /// upstream [WorldBookGrouping] table. Returns null when there is nothing to
  /// migrate. Kept so existing users do not lose their groups after the switch.
  WorldBookGrouping? _migrateLegacyBookGroups(List<WorldBook> books) {
    final names = <String, String>{};
    final memberships = <String, String>{};
    for (final book in books) {
      final label = normalizeWorldBookGroup(book.group);
      if (label.isEmpty) continue;
      var groupId = names.entries
          .where((entry) => entry.value == label)
          .map((entry) => entry.key)
          .firstOrNull;
      if (groupId == null) {
        groupId = const Uuid().v4();
        names[groupId] = label;
      }
      memberships[book.id] = groupId;
    }
    if (names.isEmpty) return null;
    return WorldBookGrouping(names: names, memberships: memberships);
  }

  Future<void> _loadAll() async {
    try {
      _books = await _store.getAll();
      _grouping = await _store.getGrouping();
      // Bridge: migrate the legacy per-book `group` labels into the upstream
      // grouping table once, so books keep their groups after the switch.
      if (_grouping.names.isEmpty) {
        final migrated = _migrateLegacyBookGroups(_books);
        if (migrated != null) {
          await _store.saveGrouping(migrated);
          _grouping = migrated;
        }
      }
      _activeIdsByAssistant = await _store.getActiveIdsByAssistant();
      final collapsed = await _store.getCollapsedBooksMap();
      final knownIds = _books.map((e) => e.id).toSet();
      final cleanedCollapsed = <String, bool>{
        for (final entry in collapsed.entries)
          if (knownIds.contains(entry.key)) entry.key: entry.value,
      };
      _collapsedBooks = cleanedCollapsed;

      if (cleanedCollapsed.length != collapsed.length) {
        await _store.setCollapsedMap(cleanedCollapsed);
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load world books: $e');
      _books = const <WorldBook>[];
      _activeIdsByAssistant = const <String, List<String>>{};
      _collapsedBooks = const <String, bool>{};
      _grouping = const WorldBookGrouping();
      notifyListeners();
    }
  }

  Future<void> addBook(WorldBook book, {String? groupId}) =>
      _serializeBookOperation(() async {
        await _store.add(book, groupId: groupId);
        await _loadAll();
      });

  Future<void> updateBook(
    String id,
    WorldBook Function(WorldBook current) update, {
    ({String? groupId})? group,
  }) => _serializeBookOperation(() async {
    final current = getById(id);
    if (current == null) return;
    final book = update(current);
    final grouping = group == null
        ? null
        : _groupingAfterMove({id}, group.groupId);
    await _store.update(book, grouping: grouping);
    if (!book.enabled) {
      try {
        await _store.removeBookFromBindings(book.id);
      } catch (_) {}
    }
    await _loadAll();
  });

  Future<void> deleteBook(String id) => _serializeBookOperation(() async {
    await _store.delete(id);
    await _loadAll();
  });

  Future<void> setEntryEnabled(String bookId, String entryId, bool enabled) =>
      _serializeBookOperation(() async {
        final index = _books.indexWhere((book) => book.id == bookId);
        if (index < 0) return;
        final book = _books[index];
        final next = book.copyWith(
          entries: [
            for (final entry in book.entries)
              entry.id == entryId ? entry.copyWith(enabled: enabled) : entry,
          ],
        );
        _books = List<WorldBook>.from(_books)..[index] = next;
        notifyListeners();
        await _store.save(_books);
      });

  Future<void> clear() => _serializeBookOperation(() async {
    await _store.clear();
    _books = const <WorldBook>[];
    _activeIdsByAssistant = const <String, List<String>>{};
    _collapsedBooks = const <String, bool>{};
    _grouping = const WorldBookGrouping();
    notifyListeners();
  });

  Future<void> reorderBooks({
    required int oldIndex,
    required int newIndex,
    ({String? id})? group,
  }) => _serializeBookOperation(() async {
    final previous = _books;
    final members = group == null ? List.of(previous) : booksInGroup(group.id);
    if (oldIndex == newIndex || oldIndex < 0 || oldIndex >= members.length) {
      return;
    }
    if (newIndex < 0 || newIndex >= members.length) return;
    members.insert(newIndex, members.removeAt(oldIndex));

    // Keep the positions of books in other folders in the injection order.
    var memberIndex = 0;
    _books = group == null
        ? members
        : [
            for (final book in previous)
              if (groupIdForBook(book.id) == group.id)
                members[memberIndex++]
              else
                book,
          ];
    notifyListeners();
    try {
      await _store.save(_books);
    } catch (_) {
      _books = previous;
      notifyListeners();
      rethrow;
    }
  });

  /// Reorders books inside one group only, mirroring the instruction
  /// injection behaviour: the group buckets keep their stored order and only
  /// the target group's own slots are rewritten.
  /// Bridge: our group cards call this with a group *label*; the real
  /// membership now lives in the upstream [WorldBookGrouping]. Resolve the
  /// label to a group id and delegate to the upstream reorder implementation.
  Future<void> reorderBooksWithinGroup({
    required String group,
    required int oldIndex,
    required int newIndex,
  }) {
    final target = normalizeWorldBookGroup(group);
    final groupId = target.isEmpty
        ? null
        : _grouping.names.entries
            .where((entry) => normalizeWorldBookGroup(entry.value) == target)
            .map((entry) => entry.key)
            .firstOrNull;
    // A named group with no matching id would be "ungrouped" in our old model;
    // fall back to the ungrouped bucket only when the label is empty, otherwise
    // drop the reorder to avoid silently moving books into the wrong folder.
    if (target.isNotEmpty && groupId == null) return Future<void>.value();
    return reorderBooks(
      oldIndex: oldIndex,
      newIndex: newIndex,
      group: (id: groupId),
    );
  }

  Future<void> reorderEntries({
    required String bookId,
    required int oldIndex,
    required int newIndex,
  }) => _serializeBookOperation(() async {
    final bookIndex = _books.indexWhere((e) => e.id == bookId);
    if (bookIndex == -1) return;
    final book = _books[bookIndex];
    final entries = List<WorldBookEntry>.from(book.entries);
    if (entries.isEmpty) return;
    if (oldIndex < 0 || oldIndex >= entries.length) return;
    if (newIndex < 0 || newIndex >= entries.length) return;
    final item = entries.removeAt(oldIndex);
    entries.insert(newIndex, item);
    final nextBook = book.copyWith(entries: entries);
    final nextBooks = List<WorldBook>.from(_books);
    nextBooks[bookIndex] = nextBook;
    _books = nextBooks;
    notifyListeners();
    await _store.save(_books);
  });

  Future<void> transferEntries({
    required String sourceBookId,
    required String targetBookId,
    required Set<String> entryIds,
    required bool copy,
  }) {
    final ids = Set<String>.of(entryIds);
    return _serializeBookOperation(
      () => _transferEntries(
        sourceBookId: sourceBookId,
        targetBookId: targetBookId,
        entryIds: ids,
        copy: copy,
      ),
    );
  }

  Future<void> _transferEntries({
    required String sourceBookId,
    required String targetBookId,
    required Set<String> entryIds,
    required bool copy,
  }) async {
    if (entryIds.isEmpty || (!copy && sourceBookId == targetBookId)) return;
    final sourceIndex = _books.indexWhere((book) => book.id == sourceBookId);
    final targetIndex = _books.indexWhere((book) => book.id == targetBookId);
    if (sourceIndex < 0 || targetIndex < 0) {
      throw StateError('World book no longer exists');
    }
    final source = _books[sourceIndex];
    final target = _books[targetIndex];
    final entries = source.entries.where(
      (entry) => entryIds.contains(entry.id),
    );
    if (entries.length != entryIds.length) {
      throw StateError('World book entries have changed');
    }
    final usedIds = target.entries.map((entry) => entry.id).toSet();
    final transferred = <WorldBookEntry>[];
    for (final entry in entries) {
      var id = entry.id;
      if (copy || usedIds.contains(id)) {
        do {
          id = const Uuid().v4();
        } while (usedIds.contains(id));
      }
      usedIds.add(id);
      transferred.add(
        entry.copyWith(id: id, keywords: List.of(entry.keywords)),
      );
    }
    final previous = _books;
    final next = List<WorldBook>.from(_books);
    if (!copy) {
      next[sourceIndex] = source.copyWith(
        entries: source.entries
            .where((entry) => !entryIds.contains(entry.id))
            .toList(),
      );
    }
    next[targetIndex] = target.copyWith(
      entries: [...target.entries, ...transferred],
    );
    // Save both books together; never persist a removal on its own.
    _books = next;
    notifyListeners();
    try {
      await _store.save(next);
    } catch (_) {
      if (identical(_books, next)) {
        _books = previous;
        notifyListeners();
      }
      rethrow;
    }
  }

  Future<void> setBookCollapsed(String id, bool collapsed) async {
    final key = id.trim();
    if (key.isEmpty) return;

    final next = Map<String, bool>.from(_collapsedBooks);
    next[key] = collapsed;
    _collapsedBooks = next;
    notifyListeners();
    await _store.setCollapsed(key, collapsed);
  }

  Future<void> toggleBookCollapsed(String id) async {
    await setBookCollapsed(id, !isBookCollapsed(id));
  }

  Future<void> setActiveBookIds(List<String> ids, {String? assistantId}) =>
      updateActiveBookIds((_) => ids, assistantId: assistantId);

  Future<void> updateActiveBookIds(
    List<String>? Function(List<String>) update, {
    String? assistantId,
  }) => _serializeBookOperation(() async {
    _activeIdsByAssistant = await _store.updateActiveIds(
      update,
      assistantId: assistantId,
    );
    notifyListeners();
  });

  Future<void> toggleActiveBookId(String id, {String? assistantId}) =>
      updateActiveBookIds((ids) {
        final next = ids.toSet();
        if (next.remove(id)) return next.toList();
        if (getById(id)?.enabled != true) return null;
        return [...next, id];
      }, assistantId: assistantId);
}
