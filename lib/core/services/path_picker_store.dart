import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 本地/工作区路径选择器的设备本地状态：记住上次的目录 + 每个 scope 的收藏夹。
///
/// 只存相对根目录的 posix 路径，不存绝对路径：
/// - 绝对路径换设备/换工作区位置就失效，跟着备份跑没有意义；
/// - 所以直接走 SharedPreferences，不进 BusinessPreferences（不随备份同步）。
///
/// 读取方用 FileBrowserOps.joinInsideRoot 校验越界与存在性，脏数据会被忽略。
class PathPickerStore {
  const PathPickerStore();

  static const PathPickerStore instance = PathPickerStore();

  static const String _lastDirKey = 'path_picker_last_dir_v1';
  static const String _favoritesKey = 'path_picker_favorites_v1';

  /// 本地文件浏览器的 scope：根目录固定，直接拿根路径当标识。
  static String localScope(String rootPath) => 'local:$rootPath';

  /// 工作区文件浏览器的 scope：用 id，工作区搬过位置收藏也不失效。
  static String workspaceScope(String workspaceId) => 'workspace:$workspaceId';

  Future<Map<String, dynamic>> _readMap(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // 坏数据当没有，下次写入自然覆盖。
    }
    return <String, dynamic>{};
  }

  Future<void> _writeMap(String key, Map<String, dynamic> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(map));
  }

  /// 上次停留的目录（相对根目录）；没有或失效时返回 null。
  Future<String?> lastDir(String scope) async {
    final value = (await _readMap(_lastDirKey))[scope];
    if (value is! String || value.isEmpty) return null;
    return value;
  }

  /// 浏览到新目录时记录。空串表示根目录，也照记。
  Future<void> setLastDir(String scope, String relativePath) async {
    final map = await _readMap(_lastDirKey);
    map[scope] = relativePath;
    await _writeMap(_lastDirKey, map);
  }

  /// 收藏夹（相对根目录），按收藏顺序。
  Future<List<String>> favorites(String scope) async {
    final value = (await _readMap(_favoritesKey))[scope];
    if (value is! List) return const <String>[];
    final out = <String>[];
    for (final item in value) {
      // 空串是合法的：代表根目录。
      if (item is! String || out.contains(item)) continue;
      out.add(item);
    }
    return out;
  }

  /// 收藏 / 取消收藏，返回操作后该目录是否已收藏。
  Future<bool> toggleFavorite(String scope, String relativePath) async {
    final map = await _readMap(_favoritesKey);
    final raw = map[scope];
    final list = <String>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is String && !list.contains(item)) list.add(item);
      }
    }
    final added = !list.remove(relativePath);
    if (added) list.add(relativePath);
    // 空串是收藏的根目录，算一项，不会被当成空列表丢掉。
    if (list.isEmpty) {
      map.remove(scope);
    } else {
      map[scope] = list;
    }
    await _writeMap(_favoritesKey, map);
    return added;
  }
}
