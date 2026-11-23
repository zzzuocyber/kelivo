import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/database/business_preferences.dart';
import 'group_chat_models.dart';

/// 全局角色库（098）：所有对话共用一份角色表，角色还能收进文件夹。
///
/// 存 BusinessPreferences 里的一个 JSON 字符串（key 见 [prefsKey]），
/// 不动数据库结构。单例：界面直接用 `GroupChatRoleLibrary.instance`，
/// 改完 notifyListeners，页面 watch/监听一下就会刷新。
class GroupChatRoleLibrary extends ChangeNotifier {
  GroupChatRoleLibrary._();

  static final GroupChatRoleLibrary instance = GroupChatRoleLibrary._();

  static const String prefsKey = 'groupChat.roleLibrary.v1';

  BusinessPreferences? _prefs;
  bool _loaded = false;
  List<GroupChatRole> _roles = const <GroupChatRole>[];
  List<GroupChatRoleFolder> _folders = const <GroupChatRoleFolder>[];

  List<GroupChatRole> get roles => _roles;
  List<GroupChatRoleFolder> get folders => _folders;
  bool get isLoaded => _loaded;

  /// 第一次打开界面时调一次（谁先打开谁调，重复调用无副作用）。
  Future<void> ensureLoaded(BusinessPreferences prefs) async {
    _prefs = prefs;
    if (_loaded) return;
    await prefs.load();
    final raw = prefs.getString(prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final map = decoded.cast<String, dynamic>();
          final roles = map['roles'];
          final folders = map['folders'];
          if (roles is List) {
            _roles = <GroupChatRole>[
              for (final item in roles)
                if (item is Map)
                  GroupChatRole.fromJson(item.cast<String, dynamic>()),
            ];
          }
          if (folders is List) {
            _folders = <GroupChatRoleFolder>[
              for (final item in folders)
                if (item is Map)
                  GroupChatRoleFolder.fromJson(item.cast<String, dynamic>()),
            ];
          }
        }
      } catch (_) {
        // 坏数据当空库，别让界面开不了。
        _roles = const <GroupChatRole>[];
        _folders = const <GroupChatRoleFolder>[];
      }
    }
    _loaded = true;
    notifyListeners();
  }

  GroupChatRole? roleById(String id) {
    for (final role in _roles) {
      if (role.id == id) return role;
    }
    return null;
  }

  /// 某个文件夹里的角色（folderId 为空 = 未分类）。
  List<GroupChatRole> rolesInFolder(String folderId) => <GroupChatRole>[
    for (final role in _roles)
      if (role.folderId == folderId) role,
  ];

  Future<void> upsertRole(GroupChatRole role) async {
    final next = List<GroupChatRole>.of(_roles);
    final at = next.indexWhere((item) => item.id == role.id);
    if (at >= 0) {
      next[at] = role;
    } else {
      next.add(role);
    }
    _roles = next;
    notifyListeners();
    await _persist();
  }

  Future<void> removeRole(String id) async {
    _roles = <GroupChatRole>[
      for (final role in _roles)
        if (role.id != id) role,
    ];
    notifyListeners();
    await _persist();
  }

  Future<GroupChatRoleFolder> addFolder(String name) async {
    final folder = GroupChatRoleFolder(
      id: 'folder_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
    );
    _folders = <GroupChatRoleFolder>[..._folders, folder];
    notifyListeners();
    await _persist();
    return folder;
  }

  Future<void> renameFolder(String id, String name) async {
    _folders = <GroupChatRoleFolder>[
      for (final folder in _folders)
        folder.id == id ? folder.copyWith(name: name) : folder,
    ];
    notifyListeners();
    await _persist();
  }

  /// 删文件夹不删角色，里面的角色回到「未分类」。
  Future<void> removeFolder(String id) async {
    _folders = <GroupChatRoleFolder>[
      for (final folder in _folders)
        if (folder.id != id) folder,
    ];
    _roles = <GroupChatRole>[
      for (final role in _roles)
        role.folderId == id ? role.copyWith(folderId: '') : role,
    ];
    notifyListeners();
    await _persist();
  }

  Future<void> moveRoleToFolder(String roleId, String folderId) async {
    _roles = <GroupChatRole>[
      for (final role in _roles)
        role.id == roleId ? role.copyWith(folderId: folderId) : role,
    ];
    notifyListeners();
    await _persist();
  }

  /// 把老对话里存的角色搬进库（按 id 去重，库里已有的不覆盖），
  /// 返回这对话应该用的角色 id 列表（老对话第一次打开时用）。
  Future<List<String>> adoptConversation(GroupChatConfig config) async {
    if (config.roles.isEmpty) return config.roleIds;
    final existing = <String>{for (final role in _roles) role.id};
    final added = <GroupChatRole>[
      for (final role in config.roles)
        if (!existing.contains(role.id)) role,
    ];
    if (added.isNotEmpty) {
      _roles = <GroupChatRole>[..._roles, ...added];
      notifyListeners();
      await _persist();
    }
    return config.roleIds.isNotEmpty
        ? config.roleIds
        : <String>[for (final role in config.roles) role.id];
  }

  Future<void> _persist() async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.setString(
      prefsKey,
      jsonEncode(<String, dynamic>{
        'roles': <Map<String, dynamic>>[
          for (final role in _roles) role.toJson(),
        ],
        'folders': <Map<String, dynamic>>[
          for (final folder in _folders) folder.toJson(),
        ],
      }),
    );
  }
}

/// 按配置解析这场群聊实际用的角色：优先 `roleIds` 指向库里的最新角色，
/// 库里查不到就用配置里存的快照兜底（老对话、角色被删都不丢人）。
List<GroupChatRole> resolveGroupChatRoles(GroupChatConfig config) {
  if (config.roleIds.isEmpty) return config.roles;
  final library = GroupChatRoleLibrary.instance;
  final out = <GroupChatRole>[];
  for (final id in config.roleIds) {
    final role = library.roleById(id) ?? _snapshotRole(config, id);
    if (role != null) out.add(role);
  }
  return out;
}

GroupChatRole? _snapshotRole(GroupChatConfig config, String id) {
  for (final role in config.roles) {
    if (role.id == id) return role;
  }
  return null;
}
