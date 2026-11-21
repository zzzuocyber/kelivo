import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/conversation_prompt_settings.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/responsive/screen_type_helper.dart';
import '../../../shared/widgets/form_sheet.dart';
import '../../../shared/widgets/ios_form_text_field.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/sheet_drag_region.dart';
import '../../../theme/app_font_weights.dart';
import '../../../theme/app_semantic_colors.dart';

Future<void> editConversationSystemPrompt(
  BuildContext context, {
  required String conversationId,
}) async {
  final chat = context.read<ChatService>();
  final conversation = chat.getConversation(conversationId);
  final initial = ConversationPromptSettings.fromExtras(
    conversation?.extras ?? const {},
  ).systemPrompt;
  // 「引用」复制的是这个对话所属助手的提示词；没绑定的会话跟随当前助手。
  final assistantPrompt =
      context
          .read<AssistantProvider>()
          .resolveConversationAssistant(conversation?.assistantId)
          ?.systemPrompt ??
      '';
  final result = await showConversationSystemPromptEditor(
    context,
    initial: initial,
    assistantPrompt: assistantPrompt,
  );
  if (result == null) return;
  await chat.updateConversationExtras(conversationId, (extras) {
    final next = Map<String, dynamic>.from(extras);
    if (result.trim().isEmpty) {
      next.remove(ConversationPromptSettings.systemPromptKey);
    } else {
      next[ConversationPromptSettings.systemPromptKey] = result;
    }
    return next;
  });
}

Future<String?> showConversationSystemPromptEditor(
  BuildContext context, {
  required String initial,
  String assistantPrompt = '',
}) {
  final platform = Theme.of(context).platform;
  if (ResponsiveHelper.isDesktop(context) ||
      platform == TargetPlatform.macOS ||
      platform == TargetPlatform.windows ||
      platform == TargetPlatform.linux) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: ctx.overlaySurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 600,
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.8,
          ),
          child: _ConversationSystemPromptEditor(
            initial: initial,
            assistantPrompt: assistantPrompt,
            desktop: true,
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : null,
    backgroundColor: context.overlaySurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _ConversationSystemPromptEditor(
      initial: initial,
      assistantPrompt: assistantPrompt,
    ),
  );
}

class _ConversationSystemPromptEditor extends StatefulWidget {
  const _ConversationSystemPromptEditor({
    required this.initial,
    this.assistantPrompt = '',
    this.desktop = false,
  });
  final String initial;
  final String assistantPrompt;
  final bool desktop;

  @override
  State<_ConversationSystemPromptEditor> createState() =>
      _ConversationSystemPromptEditorState();
}

class _ConversationSystemPromptEditorState
    extends State<_ConversationSystemPromptEditor> {
  static const _minSize = 0.32;
  static const _maxSize = 0.94;

  late final _controller = TextEditingController(text: widget.initial);
  final _focus = FocusNode(debugLabel: 'conversationSystemPrompt');
  DraggableScrollableController? _sheetController;

  bool get _hasAssistantPrompt => widget.assistantPrompt.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  /// 键盘一弹，可用高度少一截，输入框会被压成一条。拿到焦点就顺手把面板
  /// 拉高一点，省得每次都要手动往上拖。
  void _onFocusChanged() {
    if (!_focus.hasFocus) return;
    final controller = _sheetController;
    if (controller == null || !controller.isAttached) return;
    if (controller.size < 0.7) {
      controller
          .animateTo(
            0.88,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
          )
          .catchError((Object _) {});
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// 把助手提示词插到光标处：不覆盖、不清空已经写好的内容。
  /// 若两侧紧贴文字，自动补一个换行，免得两段粘在一起。
  void _insertAssistantPrompt() {
    if (!_hasAssistantPrompt) return;
    Haptics.light();
    final base = _controller.text;
    final selection = _controller.selection;
    final start = selection.isValid ? selection.start : base.length;
    final end = selection.isValid ? selection.end : base.length;
    final before = base.substring(0, start);
    final after = base.substring(end);
    final text = widget.assistantPrompt.trimRight();
    final lead = before.isNotEmpty && !before.endsWith('\n') ? '\n' : '';
    final tail = after.isNotEmpty && !after.startsWith('\n') ? '\n' : '';
    final insert = '$lead$text$tail';
    _controller.value = TextEditingValue(
      text: before + insert + after,
      selection: TextSelection.collapsed(offset: before.length + insert.length),
    );
    _focus.requestFocus();
  }

  Widget _grabber(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: cs.onSurface.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }

  Widget _actions(BuildContext context, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    return FormSheetActions(
      cancelLabel: l10n.worldBookCancel,
      confirmLabel: l10n.worldBookSave,
      onCancel: () => Navigator.of(context).pop(),
      onConfirm: () => Navigator.of(context).pop(_controller.text),
      leading: _SquareAction(
        key: const ValueKey('conversation-system-prompt-quote'),
        icon: Lucide.Copy,
        label: l10n.conversationSystemPromptQuote,
        // 没有助手提示词可引用时置灰，点了也没内容。
        enabled: _hasAssistantPrompt,
        color: cs.primary,
        onTap: _insertAssistantPrompt,
      ),
    );
  }

  Widget _clearRow(BuildContext context, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: IosCardPress(
        baseColor: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        onTap: () => Navigator.of(context).pop(''),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Lucide.RotateCcw, size: 15, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                l10n.conversationSystemPromptClear,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    BuildContext context,
    AppLocalizations l10n, {
    required bool expanding,
  }) {
    final cs = Theme.of(context).colorScheme;
    final style = TextStyle(
      fontSize: 15,
      height: 1.3,
      fontWeight: AppFontWeights.medium,
      color: cs.onSurface.withValues(alpha: 0.92),
    );
    if (!expanding) {
      return IosFormTextField(
        key: const ValueKey('conversation-system-prompt-input'),
        label: '',
        hintText: l10n.conversationSystemPromptPlaceholder,
        controller: _controller,
        minLines: 8,
        maxLines: 20,
        keyboardType: TextInputType.multiline,
        outerPadding: EdgeInsets.zero,
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: context.appColors.surfaceCardFill,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: TextField(
        key: const ValueKey('conversation-system-prompt-input'),
        controller: _controller,
        focusNode: _focus,
        expands: true,
        maxLines: null,
        minLines: null,
        textAlignVertical: TextAlignVertical.top,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        enableInteractiveSelection: true,
        style: style,
        cursorColor: cs.primary,
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          hintText: l10n.conversationSystemPromptPlaceholder,
          hintStyle: style.copyWith(
            color: cs.onSurface.withValues(alpha: 0.38),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    if (widget.desktop) return _buildDesktop(context, l10n);
    final insets = MediaQuery.viewInsetsOf(context);
    // 面板可用高度：键盘弹起后按剩余高度算比例，拉动手感才不会跑偏。
    final available = MediaQuery.sizeOf(context).height - insets.bottom;
    // 键盘占掉一截后可用高度会矮很多，此时再按 0.32 收起，标题加按钮就
    // 塞不下了（Expanded 会被挤成负数直接报溢出），所以抬高下限。
    final minSize = insets.bottom > 0 ? 0.58 : _minSize;

    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: SafeArea(
        top: false,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.52,
          minChildSize: minSize,
          maxChildSize: _maxSize,
          builder: (ctx, controller) {
            _sheetController = controller;
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SheetDragRegion(
                    controller: controller,
                    height: available,
                    minSize: minSize,
                    maxSize: _maxSize,
                    child: Column(
                      children: [
                        const SizedBox(height: 6),
                        _grabber(context),
                        const SizedBox(height: 12),
                        Text(
                          l10n.conversationSystemPromptTitle,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: AppFontWeights.semibold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.conversationSystemPromptHint,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(child: _field(context, l10n, expanding: true)),
                  if (widget.initial.trim().isNotEmpty)
                    _clearRow(context, l10n),
                  const SizedBox(height: 10),
                  _actions(context, l10n),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDesktop(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.conversationSystemPromptTitle,
            style: TextStyle(fontSize: 17, fontWeight: AppFontWeights.emphasis),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l10n.conversationSystemPromptHint,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _field(context, l10n, expanding: false),
                  if (widget.initial.trim().isNotEmpty)
                    _clearRow(context, l10n),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _actions(context, l10n),
        ],
      ),
    );
  }
}

/// 方形图标动作，跟左右两个按钮同一行（比例 1:3:3）。
class _SquareAction extends StatelessWidget {
  const _SquareAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final resolved = enabled ? color : color.withValues(alpha: 0.3);
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Tooltip(
        message: label,
        child: IosCardPress(
          baseColor: context.appColors.surfaceFill,
          borderRadius: BorderRadius.circular(12),
          padding: EdgeInsets.zero,
          onTap: enabled ? onTap : null,
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: resolved),
          ),
        ),
      ),
    );
  }
}
