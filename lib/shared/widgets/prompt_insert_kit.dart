import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/workspace.dart';
import '../../core/providers/assistant_provider.dart';
import '../../core/providers/workspace_provider.dart';
import '../../core/services/haptics.dart';
import '../../features/chat/widgets/local_path_picker.dart'
    show LocalPathKind, pickLocalPath;
import '../../features/chat/widgets/workspace_path_picker.dart'
    show localPromptInsertion, pickWorkspacePath, workspacePromptInsertion;
import '../../icons/lucide_adapter.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_font_weights.dart';
import '../../theme/app_semantic_colors.dart';

/// A block of text (usually `{cur_date}`) that can be tapped into a field.
class PromptVariable {
  const PromptVariable(this.label, this.value);
  final String label;
  final String value;
}

enum _InsertPanel { none, variables, markdown, paths }

enum _SnippetKind { plain, fontColor, backgroundColor, fontSize }

class _MdSnippet {
  const _MdSnippet(
    this.label,
    this.kind, {
    this.template,
    this.placeholder,
    this.block = false,
  });

  final String label;
  final _SnippetKind kind;
  final String? template;
  final String? placeholder;

  /// Block-level snippets must start on their own line to be parsed.
  final bool block;
}

const List<_MdSnippet> _markdownSnippets = <_MdSnippet>[
  _MdSnippet(
    '代码块',
    _SnippetKind.plain,
    template: '```\n代码\n```',
    placeholder: '代码',
    block: true,
  ),
  _MdSnippet(
    '折叠',
    _SnippetKind.plain,
    template: '<details>\n<summary>标题</summary>\n\n内容\n\n</details>',
    placeholder: '标题',
    block: true,
  ),
  _MdSnippet('字体颜色', _SnippetKind.fontColor),
  _MdSnippet('文字高亮', _SnippetKind.plain, template: '==文字==', placeholder: '文字'),
  _MdSnippet('文字背景', _SnippetKind.backgroundColor),
  _MdSnippet('字体大小', _SnippetKind.fontSize),
  _MdSnippet('行内代码', _SnippetKind.plain, template: '`代码`', placeholder: '代码'),
  _MdSnippet(
    '表格',
    _SnippetKind.plain,
    template: '| 列一 | 列二 |\n| --- | --- |\n| 内容 | 内容 |',
    placeholder: '列一',
    block: true,
  ),
  _MdSnippet('斜体', _SnippetKind.plain, template: '*文字*', placeholder: '文字'),
  _MdSnippet('分割线', _SnippetKind.plain, template: '---', block: true),
  _MdSnippet(
    '图层叠加',
    _SnippetKind.plain,
    template: '```layers\n![L](/storage/emulated/0/左侧立绘.png)\n![C](/workspace/素材库/中间立绘.png)\n![240](/workspace/素材库/场景.webp)\n```',
    placeholder: '240',
    block: true,
  ),
];

const List<(String, String)> _fontColorChoices = <(String, String)>[
  ('红', '#ff5c5c'),
  ('橙', '#ff9f45'),
  ('绿', '#4caf7d'),
  ('蓝', '#4a90e2'),
  ('紫', '#9b6dff'),
  ('粉', '#ff6b9d'),
  ('灰', '#9a9a9a'),
  ('黑', '#1c1c1e'),
];

const List<(String, String)> _backgroundColorChoices = <(String, String)>[
  ('黄', '#ffe58a'),
  ('绿', '#c9f0d5'),
  ('蓝', '#cfe4ff'),
  ('粉', '#ffd9e0'),
  ('紫', '#e6dbff'),
  ('灰', '#e6e6e6'),
];

const List<(String, String)> _fontSizeChoices = <(String, String)>[
  ('14', '14px'),
  ('16', '16px'),
  ('18', '18px'),
  ('22', '22px'),
  ('28', '28px'),
];

Color _hexColor(String hex) {
  final raw = hex.replaceFirst('#', '');
  return Color(0xFF000000 | int.parse(raw, radix: 16));
}

/// Two pills above a collapsed panel: available variables and markdown
/// snippets. Snippets are inserted at the caret and their placeholder is
/// selected so typing replaces it.
class PromptInsertBar extends StatefulWidget {
  const PromptInsertBar({
    super.key,
    required this.controller,
    this.focusNode,
    this.onChanged,
    this.variables = const <PromptVariable>[],
    this.cacheWarningValues = const <String>{},
    this.cacheWarningTooltip,
    this.warning,
    this.enablePathInsert = false,
    this.assistantId,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final List<PromptVariable> variables;
  final Set<String> cacheWarningValues;
  final String? cacheWarningTooltip;

  /// Extra note shown at the bottom of the expanded variables panel.
  final Widget? warning;

  /// Adds a third "路径提取" pill with local + bound-workspace path pickers.
  /// Only enabled on the system prompt / world book / injection fields.
  final bool enablePathInsert;

  /// Which assistant's default workspace to browse. Falls back to the current
  /// assistant when null (world book / injection pages have no assistant id).
  final String? assistantId;

  @override
  State<PromptInsertBar> createState() => _PromptInsertBarState();
}

class _PromptInsertBarState extends State<PromptInsertBar> {
  _InsertPanel _open = _InsertPanel.none;

  bool get _hasVariables => widget.variables.isNotEmpty;

  /// Path pickers are Android-only, matching the chat composer group.
  bool get _showPathPill =>
      widget.enablePathInsert &&
      Theme.of(context).platform == TargetPlatform.android;

  /// The assistant whose default workspace the path picker browses.
  /// Uses [read] so it is safe to call from tap callbacks as well as build;
  /// build() watches the providers explicitly to keep this reactive.
  String? get _resolvedAssistantId =>
      widget.assistantId ?? context.read<AssistantProvider>().currentAssistantId;

  /// The bound default workspace, or null when this assistant has none.
  Workspace? _boundWorkspace() {
    final assistantId = _resolvedAssistantId;
    if (assistantId == null) return null;
    final workspaceId = context
        .read<AssistantProvider>()
        .getById(assistantId)
        ?.defaultWorkspaceId;
    if (workspaceId == null || workspaceId.isEmpty) return null;
    return context.read<WorkspaceProvider>().byId(workspaceId);
  }

  void _toggle(_InsertPanel panel) {
    setState(() => _open = _open == panel ? _InsertPanel.none : panel);
  }

  void _insert(String snippet, {String? placeholder, bool block = false}) {
    final controller = widget.controller;
    final raw = controller.text;
    final selection = controller.selection;
    final start = (selection.start >= 0 && selection.start <= raw.length)
        ? selection.start
        : raw.length;
    final end =
        (selection.end >= 0 &&
            selection.end <= raw.length &&
            selection.end >= start)
        ? selection.end
        : start;
    final hadSelection = end > start;
    var text = snippet;
    if (block && start > 0 && raw[start - 1] != '\n') {
      text = '\n$text';
    }
    final next = raw.replaceRange(start, end, text);
    final insertEnd = start + text.length;
    var selStart = insertEnd;
    var selEnd = insertEnd;
    if (!hadSelection && placeholder != null) {
      final index = text.indexOf(placeholder);
      if (index >= 0) {
        selStart = start + index;
        selEnd = selStart + placeholder.length;
      }
    }
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection(baseOffset: selStart, extentOffset: selEnd),
    );
    widget.onChanged?.call(next);
    Future.microtask(() => widget.focusNode?.requestFocus());
  }

  /// Pick a local absolute path and insert prompt-form text at the caret.
  Future<void> _pickLocalPath(LocalPathKind kind) async {
    Haptics.light();
    final path = await pickLocalPath(context, kind: kind);
    if (path == null || !mounted) return;
    _insert(
      localPromptInsertion(kind, path),
      placeholder: kind == LocalPathKind.image ? '240' : null,
    );
  }

  /// Pick a workspace-relative path and insert prompt-form text at the caret.
  Future<void> _pickWorkspacePath(LocalPathKind kind) async {
    final workspace = _boundWorkspace();
    if (workspace == null) return;
    Haptics.light();
    final relative = await pickWorkspacePath(
      context,
      kind: kind,
      workspace: workspace,
    );
    if (relative == null || !mounted) return;
    _insert(
      workspacePromptInsertion(kind, relative),
      placeholder: kind == LocalPathKind.image ? '240' : null,
    );
  }

  Future<String?> _pickPanel({
    required String title,
    required List<(String, String)> options,
    bool swatch = false,
  }) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.2),
      builder: (sheetContext) {
        final cs = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            decoration: BoxDecoration(
              color: sheetContext.overlaySurface,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: AppFontWeights.semibold,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final option in options)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.of(sheetContext).pop(option.$2),
                        child: swatch
                            ? _swatchTile(sheetContext, option)
                            : Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: sheetContext.appColors.surfaceCardFill,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: cs.outlineVariant.withValues(
                                      alpha: 0.35,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  option.$2,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: AppFontWeights.medium,
                                  ),
                                ),
                              ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted) return null;
    return result;
  }

  Widget _swatchTile(BuildContext ctx, (String, String) option) {
    final cs = Theme.of(ctx).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _hexColor(option.$2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          option.$1,
          style: TextStyle(
            fontSize: 11,
            color: cs.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Future<void> _onSnippet(_MdSnippet snippet) async {
    Haptics.soft();
    switch (snippet.kind) {
      case _SnippetKind.plain:
        _insert(
          snippet.template ?? '',
          placeholder: snippet.placeholder,
          block: snippet.block,
        );
      case _SnippetKind.fontColor:
        final color = await _pickPanel(
          title: '字体颜色',
          options: _fontColorChoices,
          swatch: true,
        );
        if (color == null) return;
        _insert('<span style="color:$color">文字</span>', placeholder: '文字');
      case _SnippetKind.backgroundColor:
        final color = await _pickPanel(
          title: '文字背景',
          options: _backgroundColorChoices,
          swatch: true,
        );
        if (color == null) return;
        _insert(
          '<span style="background-color:$color">文字</span>',
          placeholder: '文字',
        );
      case _SnippetKind.fontSize:
        final size = await _pickPanel(title: '字体大小', options: _fontSizeChoices);
        if (size == null) return;
        _insert('<span style="font-size:$size">文字</span>', placeholder: '文字');
    }
  }

  Widget _pill({
    required String label,
    required bool expanded,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.soft();
        onTap();
      },
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: expanded
              ? cs.primary.withValues(alpha: 0.12)
              : context.appColors.surfaceCardFill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: expanded
                ? cs.primary.withValues(alpha: 0.40)
                : cs.outlineVariant.withValues(alpha: 0.30),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: AppFontWeights.semibold,
                  color: expanded
                      ? cs.primary
                      : cs.onSurface.withValues(alpha: 0.85),
                ),
              ),
            ),
            const SizedBox(width: 5),
            AnimatedRotation(
              turns: expanded ? 0.5 : 0.0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: Icon(
                Lucide.ChevronDown,
                size: 14,
                color: expanded
                    ? cs.primary
                    : cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _variablesPanel(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            for (final item in widget.variables)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${item.label}: ',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.75),
                    ),
                  ),
                  InkWell(
                    onTap: () => _insert(item.value),
                    child: Text(
                      item.value,
                      style: TextStyle(
                        color: cs.primary,
                        decoration: TextDecoration.underline,
                        fontSize: 12,
                        fontWeight: AppFontWeights.semibold,
                      ),
                    ),
                  ),
                  if (widget.cacheWarningValues.contains(item.value)) ...[
                    const SizedBox(width: 4),
                    Tooltip(
                      message: widget.cacheWarningTooltip ?? '',
                      child: Icon(
                        Lucide.TriangleAlert,
                        size: 14,
                        color: cs.error,
                      ),
                    ),
                  ],
                ],
              ),
          ],
        ),
        if (widget.warning != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: widget.warning,
          ),
      ],
    );
  }

  Widget _markdownPanel(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final snippet in _markdownSnippets)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _onSnippet(snippet),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: context.appColors.surfaceCardFill,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.30),
                ),
              ),
              child: Text(
                snippet.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: AppFontWeights.medium,
                  color: cs.onSurface.withValues(alpha: 0.9),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _pathTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: context.appColors.surfaceCardFill,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: cs.onSurface.withValues(alpha: 0.85)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: AppFontWeights.medium,
                color: cs.onSurface.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pathsPanel(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final workspace = _boundWorkspace();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '本地路径',
          style: TextStyle(
            fontSize: 12,
            fontWeight: AppFontWeights.semibold,
            color: cs.onSurface.withValues(alpha: 0.65),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _pathTile(
              icon: Lucide.Image,
              label: '图片链接',
              onTap: () => unawaited(_pickLocalPath(LocalPathKind.image)),
            ),
            _pathTile(
              icon: Lucide.FileText,
              label: '文件链接',
              onTap: () => unawaited(_pickLocalPath(LocalPathKind.file)),
            ),
            _pathTile(
              icon: Lucide.FolderOpen,
              label: '文件夹链接',
              onTap: () => unawaited(_pickLocalPath(LocalPathKind.folder)),
            ),
          ],
        ),
        if (workspace != null) ...[
          const SizedBox(height: 14),
          Text(
            '工作区路径 · ${workspace.name}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: AppFontWeights.semibold,
              color: cs.onSurface.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _pathTile(
                icon: Lucide.Image,
                label: '图片链接',
                onTap: () => unawaited(_pickWorkspacePath(LocalPathKind.image)),
              ),
              _pathTile(
                icon: Lucide.FileText,
                label: '文件链接',
                onTap: () => unawaited(_pickWorkspacePath(LocalPathKind.file)),
              ),
              _pathTile(
                icon: Lucide.FolderOpen,
                label: '文件夹链接',
                onTap: () => unawaited(_pickWorkspacePath(LocalPathKind.folder)),
              ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch the binding sources during build so the workspace group appears
    // or disappears as soon as the assistant's default workspace changes.
    if (widget.enablePathInsert) {
      context.watch<AssistantProvider>();
      context.watch<WorkspaceProvider>();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (_hasVariables) ...[
              Expanded(
                child: _pill(
                  label: '可用变量',
                  expanded: _open == _InsertPanel.variables,
                  onTap: () => _toggle(_InsertPanel.variables),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: _pill(
                label: 'Markdown 语法',
                expanded: _open == _InsertPanel.markdown,
                onTap: () => _toggle(_InsertPanel.markdown),
              ),
            ),
            if (_showPathPill) ...[
              const SizedBox(width: 8),
              Expanded(
                child: _pill(
                  label: '路径提取',
                  expanded: _open == _InsertPanel.paths,
                  onTap: () => _toggle(_InsertPanel.paths),
                ),
              ),
            ],
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _open == _InsertPanel.none
              ? const SizedBox(width: double.infinity, height: 0)
              : Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: switch (_open) {
                    _InsertPanel.variables => _variablesPanel(context),
                    _InsertPanel.paths => _pathsPanel(context),
                    _ => _markdownPanel(context),
                  },
                ),
        ),
      ],
    );
  }
}

/// Full-screen editor shared by the system prompt, world book entries and
/// instruction injections. Variables are only passed where they exist.
class PromptFullScreenEditor extends StatefulWidget {
  const PromptFullScreenEditor({
    super.key,
    required this.initial,
    this.hintText,
    this.variables = const <PromptVariable>[],
    this.cacheWarningValues = const <String>{},
    this.cacheWarningTooltip,
    this.warning,
    this.enablePathInsert = false,
    this.assistantId,
  });

  final String initial;
  final String? hintText;
  final List<PromptVariable> variables;
  final Set<String> cacheWarningValues;
  final String? cacheWarningTooltip;
  final Widget? warning;
  final bool enablePathInsert;
  final String? assistantId;

  @override
  State<PromptFullScreenEditor> createState() => _PromptFullScreenEditorState();
}

class _PromptFullScreenEditorState extends State<PromptFullScreenEditor> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.96,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 10, 16, bottom + 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _PlainTextButton(
                  label: MaterialLocalizations.of(context).closeButtonLabel,
                  color: cs.onSurface,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                const Spacer(),
                _PlainTextButton(
                  label: l10n.assistantEditEmojiDialogSave,
                  color: cs.primary,
                  onTap: () => Navigator.of(context).pop(_controller.text),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.appColors.surfaceFill,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.2),
                  ),
                ),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: true,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  keyboardType: TextInputType.multiline,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            PromptInsertBar(
              controller: _controller,
              focusNode: _focusNode,
              variables: widget.variables,
              cacheWarningValues: widget.cacheWarningValues,
              cacheWarningTooltip: widget.cacheWarningTooltip,
              warning: widget.warning,
              enablePathInsert: widget.enablePathInsert,
              assistantId: widget.assistantId,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlainTextButton extends StatelessWidget {
  const _PlainTextButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.soft();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: AppFontWeights.medium,
            color: color,
          ),
        ),
      ),
    );
  }
}
