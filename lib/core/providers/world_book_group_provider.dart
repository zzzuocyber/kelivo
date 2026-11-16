import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../database/business_preferences.dart';

/// Stores UI collapse state for world book groups.
///
/// Groups are keyed by their normalized (trimmed) label. The ungrouped bucket
/// uses a stable special key so its collapse state is remembered too. This is
/// separate from `world_books_collapsed_v1`, which remembers whether a single
/// book's entry list is expanded.
class WorldBookGroupProvider extends ChangeNotifier {
  static const String _collapsedKey = 'world_book_group_collapsed_v1';
  static const String ungroupedKey = '__ungrouped__';

  final BusinessPreferences preferences;
  final Map<String, bool> _collapsed = <String, bool>{};

  WorldBookGroupProvider({required this.preferences}) {
    _load();
  }

  static String keyForGroupName(String groupName) {
    final g = groupName.trim();
    return g.isEmpty ? ungroupedKey : g;
  }

  bool isCollapsed(String groupName) =>
      _collapsed[keyForGroupName(groupName)] ?? false;

  Future<void> _load() async {
    await preferences.load();
    final raw = preferences.getString(_collapsedKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        _collapsed
          ..clear()
          ..addAll(
            m.map(
              (k, v) => MapEntry(k, (v is bool) ? v : (v.toString() == 'true')),
            ),
          );
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    await preferences.setString(_collapsedKey, jsonEncode(_collapsed));
  }

  Future<void> setCollapsed(String groupName, bool value) async {
    _collapsed[keyForGroupName(groupName)] = value;
    notifyListeners();
    await _persist();
  }

  Future<void> toggleCollapsed(String groupName) =>
      setCollapsed(groupName, !isCollapsed(groupName));
}
