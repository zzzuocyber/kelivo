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
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../theme/app_font_weights.dart';
import '../../../theme/app_semantic_colors.dart';
import '../../../utils/app_directories.dart';
import '../assistant/pages/avatar_crop_page.dart';
import '../chat/widgets/tools_sheet_row.dart';
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

/// 上传角色头像：先问裁不裁，再进图库选图。
/// 选「裁剪为正方形」时复用助手头像那套裁剪页（圆形只做预览，输出 1:1 方形），
/// 结果仍旧存进「群聊头像」图库（094）。压缩参数跟助手背景一致。
Future<String?> pickAndSaveGroupChatAvatar(BuildContext context) async {
  final crop = await _showAvatarCropChoice(context);
  if (crop == null || !context.mounted) return null;
  try {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 85,
    );
    if (file == null) return null;
    var path = file.path;
    if (crop) {
      final cropped = await Navigator.of(context).push<String>(
        MaterialPageRoute<String>(
          builder: (_) => AvatarCropPage(imagePath: file.path),
        ),
      );
      if (cropped == null) return null;
      path = cropped;
    }
    return saveGroupChatAvatar(path);
  } catch (_) {
    return null;
  }
}

/// 裁剪 / 不裁剪 二选一，文案和助手头像设置共用一套。
Future<bool?> _showAvatarCropChoice(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: context.overlaySurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      Widget choice({
        required IconData icon,
        required String title,
        required String subtitle,
        required bool value,
      }) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: ToolsSheetRow(
            icon: icon,
            label: title,
            subtitle: subtitle,
            trailing: ToolsSheetRow.chevron(ctx),
            onTap: () => Navigator.of(ctx).pop<bool>(value),
          ),
        );
      }

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Center(child: _SheetHandle()),
              const SizedBox(height: 10),
              choice(
                icon: Lucide.Crop,
                title: l10n.assistantEditAvatarCropChoiceTitle,
                subtitle: l10n.assistantEditAvatarCropChoiceSubtitle,
                value: true,
              ),
              choice(
                icon: Lucide.Image,
                title: l10n.assistantEditAvatarNoCropChoiceTitle,
                subtitle: l10n.assistantEditAvatarNoCropChoiceSubtitle,
                value: false,
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      );
    },
  );
}

/// 拼图抽屉（092 起叫「扩展」）：一级只有一张群聊设置卡片，开关挪进二级。
Future<void> showGroupChatSettingsSheet(
  BuildContext context, {
  required String? conversationId,
}) {
  if (conversationId == null || conversationId.isEmpty) {
    return Future.value();
  }
  return _showGroupChatSheet<void>(
    context,
    (_) => _GroupChatEntrySheet(conversationId: conversationId),
  );
}

/// 群聊相关弹层统一走这里：同样的圆角、同样的底色。
Future<T?> _showGroupChatSheet<T>(
  BuildContext context,
  WidgetBuilder builder,
) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.overlaySurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _keyboardSafeSheet(ctx, builder(ctx)),
  );
}

/// 把整份群聊配置写回对话 extras（二级、三级页面共用）。
Future<void> _saveGroupChatConfig(
  BuildContext context,
  String conversationId,
  GroupChatConfig next,
) {
  return context.read<ChatService>().updateConversationExtras(
    conversationId,
    (current) {
      final extras = Map<String, dynamic>.from(current);
      extras[GroupChatConfig.extrasKey] = next.toJson();
      return extras;
    },
  );
}

// 三个二级入口的图标，三级页标题复用同一套。
const _roleMessageIcon = Lucide.MessagesSquare;
const _promptIcon = Lucide.Settings2;
const _roleIcon = Lucide.NotebookTabs;

/// 键盘避让：输入框聚焦时把面板整体顶到键盘上方，并限高让内容可滚（096）。
Widget _keyboardSafeSheet(BuildContext ctx, Widget child) {
  final insets = MediaQuery.viewInsetsOf(ctx).bottom;
  return AnimatedPadding(
    duration: const Duration(milliseconds: 180),
    curve: Curves.easeOutCubic,
    padding: EdgeInsets.only(bottom: insets),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(ctx).height - insets - 24,
      ),
      child: child,
    ),
  );
}

/// 弹层把手。
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

/// 弹层标题行：图标 + 名称，右边可以挂开关或按钮。
class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.icon, required this.title, this.trailing});

  final IconData icon;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: cs.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

InputDecoration _sheetFieldDecoration(BuildContext context, String hint) {
  final cs = Theme.of(context).colorScheme;
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: cs.onSurface.withValues(alpha: 0.04),
    hintStyle: TextStyle(
      color: cs.onSurface.withValues(alpha: 0.4),
      fontSize: 13,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    hintText: hint,
  );
}

Widget _sheetFieldLabel(String text) => Padding(
  padding: const EdgeInsets.only(bottom: 6),
  child: Text(
    text,
    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
  ),
);

// ============================================================================
// 一级：拼图抽屉「扩展」
// ============================================================================

class _GroupChatEntrySheet extends StatelessWidget {
  const _GroupChatEntrySheet({required this.conversationId});

  final String conversationId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final chat = context.watch<ChatService>();
    final enabled = GroupChatConfig.fromConversation(
      chat.getConversation(conversationId),
    ).enabled;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: _SheetHandle()),
            const SizedBox(height: 10),
            SizedBox(
              height: 34,
              child: Center(
                child: Text(
                  '扩展',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: AppFontWeights.emphasis,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            ToolsSheetRow(
              key: const ValueKey('group-chat-entry'),
              icon: Lucide.User,
              label: '群聊设置',
              detail: enabled ? '已开启' : '已关闭',
              trailing: ToolsSheetRow.chevron(context),
              onTap: () => _showGroupChatConfigSheet(
                context,
                conversationId: conversationId,
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 二级：群聊设置（开关 + 三个入口卡片）
// ============================================================================

Future<void> _showGroupChatConfigSheet(
  BuildContext context, {
  required String conversationId,
}) {
  return _showGroupChatSheet<void>(
    context,
    (_) => _GroupChatConfigSheet(conversationId: conversationId),
  );
}

class _GroupChatConfigSheet extends StatefulWidget {
  const _GroupChatConfigSheet({required this.conversationId});

  final String conversationId;

  @override
  State<_GroupChatConfigSheet> createState() => _GroupChatConfigSheetState();
}

class _GroupChatConfigSheetState extends State<_GroupChatConfigSheet> {
  GroupChatConfig _config = const GroupChatConfig();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _config = GroupChatConfig.fromConversation(
      context.read<ChatService>().getConversation(widget.conversationId),
    );
  }

  Future<void> _persist(GroupChatConfig next) async {
    setState(() => _config = next);
    await _saveGroupChatConfig(context, widget.conversationId, next);
  }

  /// 三级页回来可能改了角色或绑定，重新读一份快照。
  Future<void> _openChild(Future<void> child) async {
    await child;
    if (!mounted) return;
    setState(_reload);
  }

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
              const Center(child: _SheetHandle()),
              const SizedBox(height: 14),
              _SheetHeader(
                icon: Lucide.User,
                title: '群聊设置',
                trailing: IosSwitch(
                  value: _config.enabled,
                  onChanged: (v) => _persist(_config.copyWith(enabled: v)),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '仅对当前对话生效',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 16),
              _buildPauseRow(cs),
              const SizedBox(height: 14),
              ToolsSheetRow(
                key: const ValueKey('group-chat-role-message'),
                icon: _roleMessageIcon,
                label: '角色消息设置',
                trailing: ToolsSheetRow.chevron(context),
                onTap: () => _openChild(
                  _showGroupChatRoleMessageSheet(
                    context,
                    conversationId: widget.conversationId,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ToolsSheetRow(
                key: const ValueKey('group-chat-prompts'),
                icon: _promptIcon,
                label: '群聊提示词设置',
                trailing: ToolsSheetRow.chevron(context),
                onTap: () => _openChild(
                  _showGroupChatPromptSheet(
                    context,
                    conversationId: widget.conversationId,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ToolsSheetRow(
                key: const ValueKey('group-chat-roles'),
                icon: _roleIcon,
                label: '角色管理（${_config.roles.length}）',
                trailing: ToolsSheetRow.chevron(context),
                onTap: () => _openChild(
                  _showGroupChatRoleListSheet(
                    context,
                    conversationId: widget.conversationId,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
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
}

// ============================================================================
// 三级一：角色消息设置（接力上限 + 消息格式）
// ============================================================================

Future<void> _showGroupChatRoleMessageSheet(
  BuildContext context, {
  required String conversationId,
}) {
  return _showGroupChatSheet<void>(
    context,
    (_) => _GroupChatRoleMessageSheet(conversationId: conversationId),
  );
}

class _GroupChatRoleMessageSheet extends StatefulWidget {
  const _GroupChatRoleMessageSheet({required this.conversationId});

  final String conversationId;

  @override
  State<_GroupChatRoleMessageSheet> createState() =>
      _GroupChatRoleMessageSheetState();
}

class _GroupChatRoleMessageSheetState
    extends State<_GroupChatRoleMessageSheet> {
  GroupChatConfig _config = const GroupChatConfig();
  late final TextEditingController _turns;
  late final TextEditingController _format;

  @override
  void initState() {
    super.initState();
    _config = GroupChatConfig.fromConversation(
      context.read<ChatService>().getConversation(widget.conversationId),
    );
    _turns = TextEditingController(text: '${_config.maxTurns}');
    _format = TextEditingController(text: _config.messageFormat);
  }

  @override
  void dispose() {
    _turns.dispose();
    _format.dispose();
    super.dispose();
  }

  Future<void> _persist(GroupChatConfig next) async {
    setState(() => _config = next);
    await _saveGroupChatConfig(context, widget.conversationId, next);
  }

  /// 轮流方式的单选项（勾中的那行打勾）。
  Widget _relayModeRow({
    required IconData icon,
    required String label,
    required String hint,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return ToolsSheetRow(
      icon: icon,
      label: label,
      subtitle: hint,
      selected: selected,
      trailing: selected
          ? Icon(Lucide.Check, size: 18, color: cs.primary)
          : const SizedBox(width: 18),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: _SheetHandle()),
              const SizedBox(height: 14),
              const _SheetHeader(icon: _roleMessageIcon, title: '角色消息设置'),
              const SizedBox(height: 16),
              _sheetFieldLabel(
                '接力上限（条，最多 ${GroupChatConfig.maxTurnsLimit}）',
              ),
              TextField(
                controller: _turns,
                keyboardType: TextInputType.number,
                decoration: _sheetFieldDecoration(
                  context,
                  '默认 ${GroupChatConfig.defaultMaxTurns}',
                ),
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
              _sheetFieldLabel('消息格式（{角色名} {内容} 占位）'),
              TextField(
                controller: _format,
                decoration: _sheetFieldDecoration(
                  context,
                  GroupChatConfig.defaultMessageFormat,
                ),
                onChanged: (v) => _persist(_config.copyWith(messageFormat: v)),
              ),
              const SizedBox(height: 16),
              _sheetFieldLabel('轮流方式'),
              _relayModeRow(
                icon: Lucide.ListOrdered,
                label: '排队轮流',
                hint: 'A → B → C 依次接话',
                selected: _config.relayMode == GroupChatRelayMode.rotation,
                onTap: () => _persist(
                  _config.copyWith(relayMode: GroupChatRelayMode.rotation),
                ),
              ),
              const SizedBox(height: 8),
              _relayModeRow(
                icon: Lucide.Shuffle,
                label: '随机挑人',
                hint: '每轮打乱顺序，不连着同一个人说',
                selected: _config.relayMode == GroupChatRelayMode.random,
                onTap: () => _persist(
                  _config.copyWith(relayMode: GroupChatRelayMode.random),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 三级二：群聊提示词设置（话题 / 规则 / 世界观 / 绑定条目）
// ============================================================================

Future<void> _showGroupChatPromptSheet(
  BuildContext context, {
  required String conversationId,
}) {
  return _showGroupChatSheet<void>(
    context,
    (_) => _GroupChatPromptSheet(conversationId: conversationId),
  );
}

class _GroupChatPromptSheet extends StatefulWidget {
  const _GroupChatPromptSheet({required this.conversationId});

  final String conversationId;

  @override
  State<_GroupChatPromptSheet> createState() => _GroupChatPromptSheetState();
}

class _GroupChatPromptSheetState extends State<_GroupChatPromptSheet> {
  GroupChatConfig _config = const GroupChatConfig();
  late final TextEditingController _topic;
  late final TextEditingController _rules;
  late final TextEditingController _world;

  @override
  void initState() {
    super.initState();
    _config = GroupChatConfig.fromConversation(
      context.read<ChatService>().getConversation(widget.conversationId),
    );
    _topic = TextEditingController(text: _config.topic);
    _rules = TextEditingController(text: _config.rules);
    _world = TextEditingController(text: _config.worldPrompt);
  }

  @override
  void dispose() {
    _topic.dispose();
    _rules.dispose();
    _world.dispose();
    super.dispose();
  }

  Future<void> _persist(GroupChatConfig next) async {
    setState(() => _config = next);
    await _saveGroupChatConfig(context, widget.conversationId, next);
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

  String _worldSummary() {
    if (_config.worldEntryIds.isEmpty) return '未绑定';
    return '已绑 ${_config.worldEntryIds.length} 条';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: _SheetHandle()),
              const SizedBox(height: 14),
              const _SheetHeader(icon: _promptIcon, title: '群聊提示词设置'),
              const SizedBox(height: 16),
              _sheetFieldLabel('当前话题'),
              TextField(
                controller: _topic,
                minLines: 1,
                maxLines: 4,
                decoration: _sheetFieldDecoration(context, '现在大家在聊什么'),
                onChanged: (v) => _persist(_config.copyWith(topic: v)),
              ),
              const SizedBox(height: 14),
              _sheetFieldLabel('群聊规则'),
              TextField(
                controller: _rules,
                minLines: 1,
                maxLines: 4,
                decoration: _sheetFieldDecoration(
                  context,
                  '怎么聊的约束，如：每次发言不超过三句',
                ),
                onChanged: (v) => _persist(_config.copyWith(rules: v)),
              ),
              const SizedBox(height: 14),
              _sheetFieldLabel('世界观'),
              TextField(
                controller: _world,
                minLines: 2,
                maxLines: 6,
                decoration: _sheetFieldDecoration(
                  context,
                  '群聊的世界观，可写字也可绑世界书条目',
                ),
                onChanged: (v) => _persist(_config.copyWith(worldPrompt: v)),
              ),
              const SizedBox(height: 8),
              _EntryPickerRow(
                icon: Lucide.BookOpen,
                label: '绑定世界观条目',
                summary: _worldSummary(),
                onTap: _pickWorldEntries,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 三级三：角色管理（角色列表 + 添加角色）
// ============================================================================

Future<void> _showGroupChatRoleListSheet(
  BuildContext context, {
  required String conversationId,
}) {
  return _showGroupChatSheet<void>(
    context,
    (_) => _GroupChatRoleListSheet(conversationId: conversationId),
  );
}

class _GroupChatRoleListSheet extends StatefulWidget {
  const _GroupChatRoleListSheet({required this.conversationId});

  final String conversationId;

  @override
  State<_GroupChatRoleListSheet> createState() =>
      _GroupChatRoleListSheetState();
}

class _GroupChatRoleListSheetState extends State<_GroupChatRoleListSheet> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 角色增删改都落在对话 extras，watch 一下就自动刷新。
    final chat = context.watch<ChatService>();
    final config = GroupChatConfig.fromConversation(
      chat.getConversation(widget.conversationId),
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: _SheetHandle()),
              const SizedBox(height: 14),
              _SheetHeader(
                icon: _roleIcon,
                title: '角色管理（${config.roles.length}）',
                trailing: TextButton.icon(
                  onPressed: () => _addRole(config),
                  icon: const Icon(Lucide.Plus, size: 16),
                  label: const Text('添加角色'),
                ),
              ),
              if (config.roles.isEmpty)
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
                for (final role in config.roles)
                  _RoleTile(
                    role: role,
                    onTap: () => _manageRole(role),
                  ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addRole(GroupChatConfig config) async {
    final next = List.of(config.roles)
      ..add(
        GroupChatRole(
          id: const Uuid().v4(),
          name: '角色${config.roles.length + 1}',
        ),
      );
    await _saveGroupChatConfig(
      context,
      widget.conversationId,
      config.copyWith(roles: next),
    );
    if (!mounted) return;
    await _manageRole(next.last);
  }

  Future<void> _manageRole(GroupChatRole role) async {
    await showGroupChatRoleManageSheet(
      context,
      conversationId: widget.conversationId,
      role: role,
    );
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
    builder: (ctx) => _keyboardSafeSheet(
      ctx,
      _RoleManageSheet(conversationId: conversationId, role: role),
    ),
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
                label: '绑定世界书条目',
                summary: entry == null ? '未绑定' : entry.name,
                onTap: _pickEntry,
              ),
              const SizedBox(height: 8),
              _EntryPickerRow(
                icon: Lucide.Image,
                label: '上传头像',
                summary: _role.avatar.isEmpty ? '未设置' : '已设置',
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
    final path = await pickAndSaveGroupChatAvatar(context);
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
    builder: (ctx) => _keyboardSafeSheet(
      ctx,
      _WorldEntryPickerSheet(
        initialSelected: selectedIds,
        multiSelect: multiSelect,
        title: title,
      ),
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
  late final Set<String> _selected = Set.of(widget.initialSelected);
  final TextEditingController _search = TextEditingController();
  String _query = '';

  /// 当前在看的书；null = 第一层（选世界书）。
  String? _bookId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  WorldBook? _book(List<WorldBook> books) {
    for (final book in books) {
      if (book.id == _bookId) return book;
    }
    return null;
  }

  void _openBook(WorldBook book) {
    setState(() {
      _bookId = book.id;
      _query = '';
      _search.clear();
    });
  }

  void _backToBooks() {
    setState(() {
      _bookId = null;
      _query = '';
      _search.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final worldBooks = context.watch<WorldBookProvider>();
    final book = _book(worldBooks.books);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(child: _SheetHandle()),
            const SizedBox(height: 14),
            Row(
              children: [
                if (book != null)
                  IconButton(
                    onPressed: _backToBooks,
                    icon: const Icon(Lucide.ChevronLeft, size: 20),
                    tooltip: '返回世界书列表',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  ),
                Expanded(
                  child: Text(
                    book?.name ?? widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pop(Set<String>.of(_selected)),
                  child: const Text('完成'),
                ),
              ],
            ),
            TextField(
              controller: _search,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Lucide.Search, size: 16),
                hintText: book == null ? '搜书名' : '搜条目名',
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
              child: book == null
                  ? _buildBookList(cs, worldBooks.books)
                  : _buildEntryList(cs, book),
            ),
          ],
        ),
      ),
    );
  }

  /// 第一层：世界书列表，右边显示这本书已经勾了几条。
  Widget _buildBookList(ColorScheme cs, List<WorldBook> books) {
    final items = [
      for (final book in books)
        if (_query.isEmpty || book.name.contains(_query)) book,
    ];
    if (items.isEmpty) return _emptyHint(cs, '没有世界书');
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final book in items)
            InkWell(
              onTap: () => _openBook(book),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      Lucide.BookOpen,
                      size: 18,
                      color: cs.onSurface.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        book.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    if (_selectedIn(book) > 0)
                      Text(
                        '已选 ${_selectedIn(book)} 条',
                        style: TextStyle(fontSize: 12, color: cs.primary),
                      ),
                    const SizedBox(width: 6),
                    Icon(
                      Lucide.ChevronRight,
                      size: 16,
                      color: cs.onSurface.withValues(alpha: 0.4),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// 第二层：这本书里的条目。
  Widget _buildEntryList(ColorScheme cs, WorldBook book) {
    final entries = [
      for (final entry in book.entries)
        if (_query.isEmpty || entry.name.contains(_query)) entry,
    ];
    if (entries.isEmpty) return _emptyHint(cs, '这本书没有条目');
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in entries)
            InkWell(
              onTap: () => _toggle(entry.id),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      _selected.contains(entry.id)
                          ? Lucide.CircleCheck
                          : Lucide.Circle,
                      size: 18,
                      color: _selected.contains(entry.id)
                          ? cs.primary
                          : cs.onSurface.withValues(alpha: 0.35),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        entry.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    if (!entry.enabled)
                      Text(
                        '已停用',
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  int _selectedIn(WorldBook book) =>
      book.entries.where((entry) => _selected.contains(entry.id)).length;

  Widget _emptyHint(ColorScheme cs, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Center(
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          color: cs.onSurface.withValues(alpha: 0.5),
        ),
      ),
    ),
  );

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
