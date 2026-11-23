import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/world_book.dart';
import '../../../core/providers/world_book_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../theme/app_semantic_colors.dart';
import '../../../utils/app_directories.dart';
import 'group_chat_models.dart';
import 'group_chat_runtime.dart';

/// 群聊头像图库目录（聊天记录存储 → 图片 → 群聊头像 分类）。
Directory groupChatAvatarDirectory(String contentRoot) =>
    Directory(p.join(contentRoot, 'avatars', 'group_chat'));

/// 保存一张上传的群聊头像，返回本地路径。
Future<String?> saveGroupChatAvatar(String sourcePath) async {
  try {
    final root = (await AppDirectories.getContentDirectory()).path;
    final dir = groupChatAvatarDirectory(root);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final ext = p.extension(sourcePath).toLowerCase();
    final name =
        'group_avatar_${const Uuid().v4()}'
        '${ext.isEmpty ? '.jpg' : ext}';
    final target = p.join(dir.path, name);
    await File(sourcePath).copy(target);
    return target;
  } catch (_) {
    return null;
  }
}

/// 重新上传（压缩参数跟助手背景一致）。
Future<String?> pickAndSaveGroupChatAvatar() async {
  try {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 85,
    );
    if (file == null) return null;
    return saveGroupChatAvatar(file.path);
  } catch (_) {
    return null;
  }
}

/// 拼图按钮点开的「群聊设置」二级弹层（090）。
/// 每个对话独立：配置存在对话 extras 的 `groupChat.config`。
Future<void> showGroupChatSettingsSheet(
  BuildContext context, {
  required String? conversationId,
}) {
  if (conversationId == null || conversationId.isEmpty) {
    return Future.value();
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.overlaySurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _GroupChatSettingsSheet(conversationId: conversationId),
  );
}

class _GroupChatSettingsSheet extends StatefulWidget {
  const _GroupChatSettingsSheet({required this.conversationId});

  final String conversationId;

  @override
  State<_GroupChatSettingsSheet> createState() =>
      _GroupChatSettingsSheetState();
}

class _GroupChatSettingsSheetState extends State<_GroupChatSettingsSheet> {
  GroupChatConfig _config = const GroupChatConfig();
  late final TextEditingController _turns;
  late final TextEditingController _format;
  late final TextEditingController _topic;
  late final TextEditingController _rules;
  late final TextEditingController _world;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _config = GroupChatConfig.fromConversation(
      context.read<ChatService>().getConversation(widget.conversationId),
    );
    _turns = TextEditingController(text: '${_config.maxTurns}');
    _format = TextEditingController(text: _config.messageFormat);
    _topic = TextEditingController(text: _config.topic);
    _rules = TextEditingController(text: _config.rules);
    _world = TextEditingController(text: _config.worldPrompt);
    _loaded = true;
  }

  @override
  void dispose() {
    _turns.dispose();
    _format.dispose();
    _topic.dispose();
    _rules.dispose();
    _world.dispose();
    super.dispose();
  }

  Future<void> _persist(GroupChatConfig next) async {
    setState(() => _config = next);
    await context.read<ChatService>().updateConversationExtras(
          widget.conversationId,
          (current) {
            final extras = Map<String, dynamic>.from(current);
            extras[GroupChatConfig.extrasKey] = next.toJson();
            return extras;
          },
        );
  }

  InputDecoration _decoration(String hint) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: cs.onSurface.withValues(alpha: 0.04),
      hintStyle: TextStyle(
        color: cs.onSurface.withValues(alpha: 0.4),
        fontSize: 13,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      hintText: hint,
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(Lucide.Puzzle, size: 20, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: const Text(
                      '群聊设置',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IosSwitch(
                    value: _config.enabled,
                    onChanged: (v) => _persist(_config.copyWith(enabled: v)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '仅对当前对话生效',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
              if (_config.enabled) ...[
                const SizedBox(height: 16),
                _buildPauseRow(cs),
                const SizedBox(height: 14),
                _label('接力上限（条，最多 ${GroupChatConfig.maxTurnsLimit}）'),
                TextField(
                  controller: _turns,
                  keyboardType: TextInputType.number,
                  decoration: _decoration('默认 ${GroupChatConfig.defaultMaxTurns}'),
                  onChanged: (v) {
                    final parsed = int.tryParse(v.trim());
                    if (parsed == null) return;
                    _persist(
                      _config.copyWith(
                        maxTurns: parsed.clamp(1, GroupChatConfig.maxTurnsLimit),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),
                _label('消息格式（{角色名} {内容} 占位）'),
                TextField(
                  controller: _format,
                  decoration:
                      _decoration(GroupChatConfig.defaultMessageFormat),
                  onChanged: (v) =>
                      _persist(_config.copyWith(messageFormat: v)),
                ),
                const SizedBox(height: 14),
                _label('当前话题'),
                TextField(
                  controller: _topic,
                  minLines: 1,
                  maxLines: 4,
                  decoration: _decoration('现在大家在聊什么'),
                  onChanged: (v) => _persist(_config.copyWith(topic: v)),
                ),
                const SizedBox(height: 14),
                _label('群聊规则'),
                TextField(
                  controller: _rules,
                  minLines: 1,
                  maxLines: 4,
                  decoration: _decoration('怎么聊的约束，如：每次发言不超过三句'),
                  onChanged: (v) => _persist(_config.copyWith(rules: v)),
                ),
                const SizedBox(height: 14),
                _label('世界观'),
                TextField(
                  controller: _world,
                  minLines: 2,
                  maxLines: 6,
                  decoration: _decoration('群聊的世界观，可写字也可绑世界书条目'),
                  onChanged: (v) => _persist(_config.copyWith(worldPrompt: v)),
                ),
                const SizedBox(height: 8),
                _EntryPickerRow(
                  icon: Lucide.BookOpen,
                  label: '绑定世界观条目',
                  summary: _worldSummary(),
                  onTap: () => _pickWorldEntries(),
                ),
                const SizedBox(height: 16),
                _buildRoleSection(cs),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  String _worldSummary() {
    if (_config.worldEntryIds.isEmpty) return '未绑定';
    return '已绑 ${_config.worldEntryIds.length} 条';
  }

  Widget _buildPauseRow(ColorScheme cs) {
    final active = GroupChatRuntime.isActive(widget.conversationId);
    final paused = GroupChatRuntime.isPaused(widget.conversationId);
    if (!active) {
      return Text(
        '当前没有进行中的接力',
        style: TextStyle(
          fontSize: 12,
          color: cs.onSurface.withValues(alpha: 0.5),
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: Text(
            paused ? '接力已暂停' : '接力进行中…',
            style: TextStyle(
              fontSize: 13,
              color: paused ? cs.primary : cs.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
        TextButton(
          onPressed: () {
            setState(() {
              if (paused) {
                GroupChatRuntime.resume(widget.conversationId);
              } else {
                GroupChatRuntime.pause(widget.conversationId);
              }
            });
          },
          child: Text(paused ? '继续' : '暂停群聊'),
        ),
      ],
    );
  }

  Widget _buildRoleSection(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '角色管理（${_config.roles.length}）',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _addRole,
              icon: const Icon(Lucide.Plus, size: 16),
              label: const Text('添加角色'),
            ),
          ],
        ),
        if (_config.roles.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '还没有角色，先添加一个并绑定世界书条目当人设',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
          )
        else
          for (final role in _config.roles)
            _RoleTile(
              role: role,
              onTap: () => _manageRole(role),
            ),
      ],
    );
  }

  Future<void> _addRole() async {
    final next = List.of(_config.roles)
      ..add(
        GroupChatRole(
          id: const Uuid().v4(),
          name: '角色${_config.roles.length + 1}',
        ),
      );
    await _persist(_config.copyWith(roles: next));
    final added = _config.roles.last;
    await _manageRole(added);
  }

  Future<void> _manageRole(GroupChatRole role) async {
    await showGroupChatRoleManageSheet(
      context,
      conversationId: widget.conversationId,
      role: role,
    );
    if (!mounted) return;
    // 管理页可能改了配置，刷新本地快照。
    setState(() {
      _config = GroupChatConfig.fromConversation(
        context.read<ChatService>().getConversation(widget.conversationId),
      );
      _turns.text = '${_config.maxTurns}';
      _format.text = _config.messageFormat;
      _topic.text = _config.topic;
      _rules.text = _config.rules;
      _world.text = _config.worldPrompt;
    });
  }

  Future<void> _pickWorldEntries() async {
    final selected = await showWorldEntryPickerSheet(
      context,
      selectedIds: _config.worldEntryIds.toSet(),
      multiSelect: true,
      title: '绑定世界观条目',
    );
    if (selected == null || !mounted) return;
    await _persist(_config.copyWith(worldEntryIds: selected.toList()));
  }
}

// ============================================================================
// 角色管理
// ============================================================================

/// 角色管理页（设置弹层里点角色进来的二级页）。
Future<void> showGroupChatRoleManageSheet(
  BuildContext context, {
  required String conversationId,
  required GroupChatRole role,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.overlaySurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) =>
        _RoleManageSheet(conversationId: conversationId, role: role),
  );
}

class _RoleManageSheet extends StatefulWidget {
  const _RoleManageSheet({required this.conversationId, required this.role});

  final String conversationId;
  final GroupChatRole role;

  @override
  State<_RoleManageSheet> createState() => _RoleManageSheetState();
}

class _RoleManageSheetState extends State<_RoleManageSheet> {
  late TextEditingController _name;
  late GroupChatRole _role;

  @override
  void initState() {
    super.initState();
    _role = widget.role;
    _name = TextEditingController(text: _role.name);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _updateConfig(GroupChatRole Function(GroupChatRole) change) {
    final chat = context.read<ChatService>();
    final conversation = chat.getConversation(widget.conversationId);
    if (conversation == null) return;
    final config = GroupChatConfig.fromConversation(conversation);
    final roles = [
      for (final role in config.roles)
        if (role.id == _role.id) change(role) else role,
    ];
    chat.updateConversationExtras(widget.conversationId, (current) {
      final extras = Map<String, dynamic>.from(current);
      extras[GroupChatConfig.extrasKey] =
          config.copyWith(roles: roles).toJson();
      return extras;
    });
    setState(() => _role = change(_role));
  }

  Future<void> _deleteRole() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除角色'),
        content: Text('从本对话的角色列表删除「${_role.name}」？世界书条目不会被删。'),
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
    if (confirmed != true || !mounted) return;
    final chat = context.read<ChatService>();
    final conversation = chat.getConversation(widget.conversationId);
    if (conversation != null) {
      final config = GroupChatConfig.fromConversation(conversation);
      final roles = config.roles
          .where((role) => role.id != _role.id)
          .toList(growable: false);
      await chat.updateConversationExtras(widget.conversationId, (current) {
        final extras = Map<String, dynamic>.from(current);
        extras[GroupChatConfig.extrasKey] =
            config.copyWith(roles: roles).toJson();
        return extras;
      });
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final worldBooks = context.watch<WorldBookProvider>();
    final entry = _findEntry(worldBooks.books);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _buildAvatar(cs, size: 40),
                  const SizedBox(width: 10),
                  Expanded(
                    child: const Text(
                      '管理角色',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _deleteRole,
                    child: Text(
                      '删除角色',
                      style: TextStyle(color: cs.error),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _label('角色名'),
              TextField(
                controller: _name,
                decoration: _decoration('角色名'),
                onChanged: (v) =>
                    _updateConfig((role) => role.copyWith(name: v)),
              ),
              const SizedBox(height: 14),
              _EntryPickerRow(
                icon: Lucide.BookOpen,
                label: '绑定世界书条目（人设）',
                summary: entry == null ? '未绑定' : entry.name,
                onTap: _pickEntry,
              ),
              const SizedBox(height: 8),
              _EntryPickerRow(
                icon: Lucide.Image,
                label: '上传头像（存入群聊头像图库）',
                summary: _role.avatar.isEmpty ? '未设置·用首字圆标' : '已设置',
                onTap: _pickAvatar,
              ),
              if (_role.avatar.isNotEmpty)
                _EntryPickerRow(
                  icon: Lucide.X,
                  label: '清除头像',
                  summary: '',
                  onTap: () =>
                      _updateConfig((role) => role.copyWith(clearAvatar: true)),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  WorldBookEntry? _findEntry(List<WorldBook> books) {
    for (final book in books) {
      if (_role.bookId.isNotEmpty && book.id != _role.bookId) continue;
      for (final entry in book.entries) {
        if (entry.id == _role.entryId) return entry;
      }
    }
    return null;
  }

  Widget _buildAvatar(ColorScheme cs, {double size = 40}) {
    final avatar = _role.avatar.trim();
    if (avatar.isNotEmpty && File(avatar).existsSync()) {
      return ClipOval(
        child: Image.file(
          File(avatar),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _initialAvatar(cs, size),
        ),
      );
    }
    return _initialAvatar(cs, size);
  }

  Widget _initialAvatar(ColorScheme cs, double size) {
    final name = _role.name.trim();
    final ch = name.isEmpty ? '?' : name.characters.first;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        ch,
        style: TextStyle(
          color: cs.primary,
          fontSize: size * 0.45,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Future<void> _pickEntry() async {
    final result = await showWorldEntryPickerSheet(
      context,
      selectedIds: _role.entryId.isEmpty
          ? const <String>{}
          : {_role.entryId},
      multiSelect: false,
      title: '绑定世界书条目',
    );
    if (result == null || !mounted) return;
    if (result.isEmpty) {
      _updateConfig((role) => role.copyWith(entryId: '', bookId: ''));
      return;
    }
    final entryId = result.first;
    String bookId = '';
    String name = _role.name;
    for (final book in context.read<WorldBookProvider>().books) {
      for (final entry in book.entries) {
        if (entry.id == entryId) {
          bookId = book.id;
          // 角色名默认跟条目名走（用户改成过的就不再覆盖）。
          if (_name.text.trim().isEmpty ||
              _name.text.trim() == entry.name.trim() ||
              _name.text.trim().startsWith('角色')) {
            name = entry.name.trim();
            _name.text = name;
          }
        }
      }
    }
    _updateConfig(
      (role) => role.copyWith(entryId: entryId, bookId: bookId, name: name),
    );
  }

  Future<void> _pickAvatar() async {
    final path = await pickAndSaveGroupChatAvatar();
    if (path == null || !mounted) return;
    _updateConfig((role) => role.copyWith(avatar: path));
  }

  InputDecoration _decoration(String hint) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: cs.onSurface.withValues(alpha: 0.04),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      hintText: hint,
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      );
}

// ============================================================================
// 通用小件
// ============================================================================

class _EntryPickerRow extends StatelessWidget {
  const _EntryPickerRow({
    required this.icon,
    required this.label,
    required this.summary,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String summary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: cs.onSurface.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: cs.onSurface.withValues(alpha: 0.7)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 14),
              ),
            ),
            if (summary.isNotEmpty)
              Text(
                summary,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
            const SizedBox(width: 4),
            Icon(
              Lucide.ChevronRight,
              size: 16,
              color: cs.onSurface.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleTile extends StatelessWidget {
  const _RoleTile({required this.role, this.onTap});

  final GroupChatRole role;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final avatar = role.avatar.trim();
    final Widget leading;
    if (avatar.isNotEmpty && File(avatar).existsSync()) {
      leading = ClipOval(
        child: Image.file(
          File(avatar),
          width: 36,
          height: 36,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _initial(cs),
        ),
      );
    } else {
      leading = _initial(cs);
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                role.name,
                style: const TextStyle(fontSize: 14),
              ),
            ),
            Icon(
              Lucide.ChevronRight,
              size: 16,
              color: cs.onSurface.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _initial(ColorScheme cs) {
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
}

/// 世界书条目选择器。multiSelect=true 用于世界观（多选），
/// false 用于角色人设（单选）。返回选中的条目 id；取消返回 null，
/// 清空选择返回空集合。
Future<Set<String>?> showWorldEntryPickerSheet(
  BuildContext context, {
  required Set<String> selectedIds,
  required bool multiSelect,
  String title = '选择世界书条目',
}) {
  return showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.overlaySurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _WorldEntryPickerSheet(
      initialSelected: selectedIds,
      multiSelect: multiSelect,
      title: title,
    ),
  );
}

class _WorldEntryPickerSheet extends StatefulWidget {
  const _WorldEntryPickerSheet({
    required this.initialSelected,
    required this.multiSelect,
    required this.title,
  });

  final Set<String> initialSelected;
  final bool multiSelect;
  final String title;

  @override
  State<_WorldEntryPickerSheet> createState() => _WorldEntryPickerSheetState();
}

class _WorldEntryPickerSheetState extends State<_WorldEntryPickerSheet> {
  late Set<String> _selected = Set.of(widget.initialSelected);
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final worldBooks = context.watch<WorldBookProvider>();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pop(Set.of(_selected)),
                  child: const Text('完成'),
                ),
              ],
            ),
            TextField(
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Lucide.Search, size: 16),
                hintText: '搜条目名',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: cs.onSurface.withValues(alpha: 0.04),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: Builder(
                builder: (context) {
                  final groups = <String, List<_EntryRef>>{};
                  for (final book in worldBooks.books) {
                    for (final entry in book.entries) {
                      if (_query.isNotEmpty &&
                          !entry.name.contains(_query) &&
                          !book.name.contains(_query)) {
                        continue;
                      }
                      groups
                          .putIfAbsent(book.name, () => [])
                          .add(_EntryRef(book, entry));
                    }
                  }
                  if (groups.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          '没有世界书或条目',
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    );
                  }
                  return SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final entry in groups.entries) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 4),
                            child: Text(
                              entry.key,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color:
                                    cs.onSurface.withValues(alpha: 0.55),
                              ),
                            ),
                          ),
                          for (final ref in entry.value)
                            InkWell(
                              onTap: () => _toggle(ref.entry.id),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _selected.contains(ref.entry.id)
                                          ? Lucide.CircleCheck
                                          : Lucide.Circle,
                                      size: 18,
                                      color: _selected.contains(ref.entry.id)
                                          ? cs.primary
                                          : cs.onSurface.withValues(
                                              alpha: 0.35,
                                            ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        ref.entry.name,
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ),
                                    if (!ref.entry.enabled)
                                      Text(
                                        '已停用',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: cs.onSurface
                                              .withValues(alpha: 0.4),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggle(String entryId) {
    setState(() {
      if (widget.multiSelect) {
        if (!_selected.remove(entryId)) _selected.add(entryId);
      } else {
        if (_selected.contains(entryId)) {
          _selected.clear();
        } else {
          _selected
            ..clear()
            ..add(entryId);
        }
      }
    });
  }
}

class _EntryRef {
  const _EntryRef(this.book, this.entry);

  final WorldBook book;
  final WorldBookEntry entry;
}
