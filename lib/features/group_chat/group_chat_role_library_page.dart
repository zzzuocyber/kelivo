import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/business_preferences.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';
import '../../../theme/app_semantic_colors.dart';
import '../chat/widgets/tools_sheet_row.dart';
import 'group_chat_models.dart';
import 'group_chat_role_library.dart';
import 'group_chat_settings_sheet.dart';

/// 打开「角色库」全屏页（098）：所有对话共用的角色 + 文件夹分类。
Future<void> openGroupChatRoleLibraryPage(BuildContext context) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (_) => const GroupChatRoleLibraryPage()),
  );
}

class GroupChatRoleLibraryPage extends StatefulWidget {
  const GroupChatRoleLibraryPage({super.key});

  @override
  State<GroupChatRoleLibraryPage> createState() =>
      _GroupChatRoleLibraryPageState();
}

class _GroupChatRoleLibraryPageState extends State<GroupChatRoleLibraryPage> {
  final GroupChatRoleLibrary _library = GroupChatRoleLibrary.instance;

  @override
  void initState() {
    super.initState();
    _library.addListener(_onLibraryChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _library.ensureLoaded(context.read<BusinessPreferences>());
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _library.removeListener(_onLibraryChanged);
    super.dispose();
  }

  void _onLibraryChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final folders = _library.folders;
    final unclassified = _library.rolesInFolder('');
    return Scaffold(
      appBar: AppBar(
        title: const Text('角色库'),
        actions: [
          IconButton(
            tooltip: '新建文件夹',
            icon: const Icon(Lucide.FolderPlus, size: 20),
            onPressed: _createFolder,
          ),
          IconButton(
            tooltip: '新建角色',
            icon: const Icon(Lucide.Plus, size: 20),
            onPressed: _createRole,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (!_library.isLoaded)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_library.roles.isEmpty && folders.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  '还没有角色，点右上角「＋」建一个',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ),
          if (unclassified.isNotEmpty) ...[
            _sectionHeader('未分类', unclassified.length, folder: null),
            for (final role in unclassified) _roleRow(role),
          ],
          for (final folder in folders) ...[
            _sectionHeader(
              folder.name,
              _library.rolesInFolder(folder.id).length,
              folder: folder,
            ),
            for (final role in _library.rolesInFolder(folder.id))
              _roleRow(role),
          ],
          const SizedBox(height: 8),
          Text(
            '这里的角色所有对话共用；在群聊设置里挑「参与角色」才算进这场。',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: cs.onSurface.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(
    String title,
    int count, {
    required GroupChatRoleFolder? folder,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Row(
        children: [
          Icon(
            folder == null ? Lucide.Layers : Lucide.Folder,
            size: 16,
            color: cs.onSurface.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$title（$count）',
              style: TextStyle(
                fontSize: 13,
                fontWeight: AppFontWeights.semibold,
                color: cs.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          if (folder != null)
            PopupMenuButton<String>(
              tooltip: '文件夹操作',
              icon: Icon(
                Lucide.Ellipsis,
                size: 18,
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
              onSelected: (value) {
                if (value == 'rename') _renameFolder(folder);
                if (value == 'delete') _deleteFolder(folder);
              },
              itemBuilder: (_) => const [
                PopupMenuItem<String>(value: 'rename', child: Text('重命名文件夹')),
                PopupMenuItem<String>(value: 'delete', child: Text('删除文件夹')),
              ],
            ),
        ],
      ),
    );
  }

  Widget _roleRow(GroupChatRole role) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ToolsSheetRow(
        leading: _avatar(role, cs),
        label: role.name,
        subtitle: _roleSummary(role),
        trailing: PopupMenuButton<String>(
          tooltip: '角色操作',
          icon: Icon(
            Lucide.Ellipsis,
            size: 18,
            color: cs.onSurface.withValues(alpha: 0.6),
          ),
          onSelected: (value) {
            if (value == 'move') _moveRole(role);
            if (value == 'delete') _deleteRole(role);
          },
          itemBuilder: (_) => const [
            PopupMenuItem<String>(value: 'move', child: Text('移动到文件夹')),
            PopupMenuItem<String>(value: 'delete', child: Text('从角色库删除')),
          ],
        ),
        onTap: () => _editRole(role),
      ),
    );
  }

  String _roleSummary(GroupChatRole role) {
    final model = role.modelId.trim();
    final reasoning = role.reasoningLevel.trim();
    if (model.isEmpty) return '跟随对话模型';
    final parts = <String>[model];
    if (reasoning.isNotEmpty) parts.add('思考 $reasoning');
    return parts.join(' · ');
  }

  Widget _avatar(GroupChatRole role, ColorScheme cs) {
    final avatar = role.avatar.trim();
    if (avatar.isNotEmpty && File(avatar).existsSync()) {
      return ClipOval(
        child: Image.file(
          File(avatar),
          width: 36,
          height: 36,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _initial(role, cs),
        ),
      );
    }
    return _initial(role, cs);
  }

  Widget _initial(GroupChatRole role, ColorScheme cs) {
    final name = role.name.trim();
    final ch = name.isEmpty ? '?' : name.characters.first;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        ch,
        style: TextStyle(
          color: cs.primary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Future<void> _createRole() async {
    final role = GroupChatRole(
      id: const Uuid().v4(),
      name: '角色${_library.roles.length + 1}',
    );
    await _library.upsertRole(role);
    if (!mounted) return;
    await _editRole(role);
  }

  Future<void> _editRole(GroupChatRole role) async {
    // 库模式：没有对话，改动只落库。
    await showGroupChatRoleManageSheet(context, role: role);
  }

  Future<void> _createFolder() async {
    final name = await _askText(title: '新建文件夹', hint: '文件夹名');
    if (name == null || name.trim().isEmpty) return;
    await _library.addFolder(name.trim());
  }

  Future<void> _renameFolder(GroupChatRoleFolder folder) async {
    final name = await _askText(
      title: '重命名文件夹',
      hint: '文件夹名',
      initial: folder.name,
    );
    if (name == null || name.trim().isEmpty) return;
    await _library.renameFolder(folder.id, name.trim());
  }

  Future<void> _deleteFolder(GroupChatRoleFolder folder) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除文件夹'),
        content: Text('删掉「${folder.name}」？里面的角色会回到「未分类」，不会被删。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _library.removeFolder(folder.id);
  }

  Future<void> _moveRole(GroupChatRole role) async {
    final folders = _library.folders;
    final target = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.overlaySurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(
                    ctx,
                  ).colorScheme.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 12),
              for (final folder in folders)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ToolsSheetRow(
                    icon: Lucide.Folder,
                    label: folder.name,
                    trailing: role.folderId == folder.id
                        ? Icon(
                            Lucide.Check,
                            size: 18,
                            color: Theme.of(ctx).colorScheme.primary,
                          )
                        : const SizedBox(width: 18),
                    onTap: () => Navigator.of(ctx).pop(folder.id),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ToolsSheetRow(
                  icon: Lucide.Layers,
                  label: '未分类',
                  trailing: role.folderId.isEmpty
                      ? Icon(
                          Lucide.Check,
                          size: 18,
                          color: Theme.of(ctx).colorScheme.primary,
                        )
                      : const SizedBox(width: 18),
                  onTap: () => Navigator.of(ctx).pop(''),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (target == null) return;
    await _library.moveRoleToFolder(role.id, target);
  }

  Future<void> _deleteRole(GroupChatRole role) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从角色库删除'),
        content: Text('「${role.name}」会从角色库消失。已经选过它的对话仍按上次的样子显示，'
            '但之后改它不会再同步过去。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _library.removeRole(role.id);
  }

  Future<String?> _askText({
    required String title,
    required String hint,
    String initial = '',
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (value) => Navigator.of(ctx).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
