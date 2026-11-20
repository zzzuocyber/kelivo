import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/models/message_part.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_checkbox.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/app_font_weights.dart';
import '../../../theme/app_semantic_colors.dart';
import '../../chat/widgets/message_export_sheet.dart';

/// Conversation extras key holding the ids of bookmarked messages.
const String kMiniMapFavoritesKey = 'chat.favorites';

/// Rough row height used to land near a bookmark before the precise
/// `ensureVisible` pass (bubbles are single-line, so pairs stay near-uniform).
const double _kPairHeightEstimate = 96;

Future<String?> showMiniMapSheet(
  BuildContext context,
  List<ChatMessage> messages, {
  bool selecting = false,
  Set<String>? selectedMessageIds,
  Listenable? selectionListenable,
  ValueChanged<String>? onToggleSelection,
  VoidCallback? onOpenConversationFind,
  String? conversationId,
  Future<bool> Function(Set<String> ids)? onDeleteMessages,
}) async {
  assert(
    !selecting || (selectedMessageIds != null && onToggleSelection != null),
    'Mini map selection mode requires selectedMessageIds and onToggleSelection.',
  );
  return await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.overlaySurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _MiniMapSheet(
      messages: messages,
      selecting: selecting,
      selectedMessageIds: selectedMessageIds,
      selectionListenable: selectionListenable,
      onToggleSelection: onToggleSelection,
      onOpenConversationFind: onOpenConversationFind,
      conversationId: conversationId,
      onDeleteMessages: onDeleteMessages,
    ),
  );
}

class _MiniMapSheet extends StatefulWidget {
  final List<ChatMessage> messages;
  final bool selecting;
  final Set<String>? selectedMessageIds;
  final Listenable? selectionListenable;
  final ValueChanged<String>? onToggleSelection;
  final VoidCallback? onOpenConversationFind;
  final String? conversationId;
  final Future<bool> Function(Set<String> ids)? onDeleteMessages;

  const _MiniMapSheet({
    required this.messages,
    this.selecting = false,
    this.selectedMessageIds,
    this.selectionListenable,
    this.onToggleSelection,
    this.onOpenConversationFind,
    this.conversationId,
    this.onDeleteMessages,
  });

  @override
  State<_MiniMapSheet> createState() => _MiniMapSheetState();
}

class _MiniMapSheetState extends State<_MiniMapSheet> {
  late List<ChatMessage> _messages = List<ChatMessage>.of(widget.messages);
  late List<_QaPair> _pairs = _buildPairs(_messages);

  /// Own selection mode, entered from the minimap's own 「选择」 button so the
  /// whole flow stays inside this sheet (no trip back to the chat page).
  bool _selecting = false;
  final Set<String> _selected = <String>{};

  Set<String> _favorites = <String>{};
  bool _favoritesLoaded = false;
  int _favoriteCursor = -1;

  String? _flashId;
  final Map<String, GlobalKey> _bubbleKeys = <String, GlobalKey>{};
  ScrollController? _listController;

  bool get _selectionMode => widget.selecting || _selecting;

  Set<String> get _selectedIds => widget.selecting
      ? (widget.selectedMessageIds ?? const <String>{})
      : _selected;

  List<String> get _selectableIds => [
    for (final m in _messages)
      if (m.role == 'user' || m.role == 'assistant') m.id,
  ];

  List<String> get _favoriteIds => [
    for (final m in _messages)
      if (_favorites.contains(m.id)) m.id,
  ];

  @override
  void didUpdateWidget(_MiniMapSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.messages, widget.messages)) {
      _messages = List<ChatMessage>.of(widget.messages);
      _pairs = _buildPairs(_messages);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_favoritesLoaded) return;
    _favoritesLoaded = true;
    _favorites = _readFavorites();
  }

  Set<String> _readFavorites() {
    final id = widget.conversationId;
    if (id == null) return <String>{};
    final conversation = context.read<ChatService>().getConversation(id);
    final raw = conversation?.extras[kMiniMapFavoritesKey];
    if (raw is List) {
      return raw.whereType<String>().toSet();
    }
    return <String>{};
  }

  Future<void> _toggleFavorite(ChatMessage message) async {
    final conversationId = widget.conversationId;
    if (conversationId == null) return;
    Haptics.light();
    final next = Set<String>.of(_favorites);
    if (!next.remove(message.id)) next.add(message.id);
    setState(() => _favorites = next);
    try {
      await context.read<ChatService>().updateConversationExtras(
        conversationId,
        (extras) {
          extras[kMiniMapFavoritesKey] = next.toList();
          return extras;
        },
      );
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: '收藏没存上，再试一次',
        type: NotificationType.error,
      );
    }
  }

  void _enterSelection() {
    Haptics.light();
    setState(() {
      _selecting = true;
      _selected.clear();
    });
  }

  void _exitSelection() {
    if (widget.selecting) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _toggleMessage(String id) {
    if (widget.selecting) {
      widget.onToggleSelection?.call(id);
      return;
    }
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  void _toggleSelectAll() {
    final all = _selectableIds;
    if (all.isEmpty) return;
    Haptics.light();
    final allSelected = all.every(_selectedIds.contains);
    if (widget.selecting) {
      for (final id in all) {
        final selected = _selectedIds.contains(id);
        if (allSelected ? selected : !selected) {
          widget.onToggleSelection?.call(id);
        }
      }
      return;
    }
    setState(() {
      if (allSelected) {
        _selected.clear();
      } else {
        _selected.addAll(all);
      }
    });
  }

  Future<void> _copySelected() async {
    final ids = _selectedIds;
    final messages = [
      for (final m in _messages)
        if (ids.contains(m.id)) m,
    ];
    if (messages.isEmpty) return;
    Haptics.light();
    try {
      // Same header/body rules as the .txt export, so pasted text matches it.
      final text = await buildMessagesClipboardText(
        context,
        messages: messages,
      );
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: '已复制 ${messages.length} 条',
        type: NotificationType.success,
      );
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, message: '复制失败', type: NotificationType.error);
    }
  }

  Future<void> _deleteSelected() async {
    final ids = Set<String>.of(_selectedIds);
    final onDelete = widget.onDeleteMessages;
    if (ids.isEmpty || onDelete == null) return;
    final deleted = await onDelete(ids);
    if (!mounted || !deleted) return;
    setState(() {
      _messages.removeWhere((m) => ids.contains(m.id));
      _pairs = _buildPairs(_messages);
      for (final id in ids) {
        _bubbleKeys.remove(id);
        _favorites.remove(id);
      }
      _selected.clear();
      _selecting = false;
      _favoriteCursor = -1;
    });
  }

  Future<void> _jumpFavorite(int direction) async {
    final ids = _favoriteIds;
    if (ids.isEmpty) return;
    Haptics.light();
    _favoriteCursor = (_favoriteCursor + direction) % ids.length;
    final id = ids[_favoriteCursor];
    final pairIndex = _pairs.indexWhere(
      (p) => p.user?.id == id || p.assistant?.id == id,
    );
    final controller = _listController;
    if (pairIndex >= 0 && controller != null && controller.hasClients) {
      final target = (pairIndex * _kPairHeightEstimate - 80)
          .clamp(0.0, controller.position.maxScrollExtent)
          .toDouble();
      await controller.animateTo(
        target,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    }
    if (!mounted) return;
    setState(() => _flashId = id);
    final targetContext = _bubbleKeys[id]?.currentContext;
    if (targetContext != null) {
      await Scrollable.ensureVisible(
        targetContext,
        alignment: 0.35,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted && _flashId == id) {
      setState(() => _flashId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        builder: (ctx, controller) {
          _listController = controller;

          Widget buildList() {
            final pairs = _pairs;
            return ListView.builder(
              controller: controller,
              itemCount: pairs.length,
              itemBuilder: (context, index) {
                return _MiniMapRow(
                  pair: pairs[index],
                  selecting: _selectionMode,
                  selectedIds: _selectedIds,
                  favoriteIds: _favorites,
                  flashId: _flashId,
                  bubbleKeys: _bubbleKeys,
                  onToggle: _toggleMessage,
                  onOpen: (id) {
                    if (_selectionMode) {
                      _toggleMessage(id);
                    } else {
                      Navigator.of(context).pop(id);
                    }
                  },
                  onLongPressMessage: _toggleFavorite,
                );
              },
            );
          }

          Widget header() {
            return _selectionMode
                ? _selectionBar(context, l10n)
                : _titleBar(context, l10n, controller);
          }

          final selectionListenable = widget.selectionListenable;
          final needsSelectionRebuild =
              widget.selecting && selectionListenable != null;

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Pinned drag handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (needsSelectionRebuild)
                  AnimatedBuilder(
                    animation: selectionListenable!,
                    builder: (context, child) => header(),
                  )
                else
                  header(),
                const SizedBox(height: 12),
                // Scrollable content
                Expanded(
                  child: needsSelectionRebuild
                      ? AnimatedBuilder(
                          animation: selectionListenable!,
                          builder: (context, child) => buildList(),
                        )
                      : buildList(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _titleBar(
    BuildContext context,
    AppLocalizations l10n,
    ScrollController controller,
  ) {
    final cs = Theme.of(context).colorScheme;
    final hasFavorites = _favoriteIds.isNotEmpty;
    return Row(
      children: [
        Icon(Lucide.Map, size: 18, color: cs.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            l10n.miniMapTitle,
            style: TextStyle(fontSize: 16, fontWeight: AppFontWeights.emphasis),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        _MiniMapTextButton(label: '选择', onTap: _enterSelection),
        const SizedBox(width: 2),
        _MiniMapIconButton(
          icon: Lucide.ArrowUp,
          tooltip: '上一条收藏',
          enabled: hasFavorites,
          onTap: () => _jumpFavorite(-1),
        ),
        _MiniMapIconButton(
          icon: Lucide.ArrowDown,
          tooltip: '下一条收藏',
          enabled: hasFavorites,
          onTap: () => _jumpFavorite(1),
        ),
        SizedBox(
          height: 36,
          width: 36,
          child: IconButton(
            padding: EdgeInsets.zero,
            icon: Icon(Lucide.ChevronsDown, size: 18, color: cs.onSurface),
            tooltip: l10n.miniMapScrollToBottomTooltip,
            onPressed: () {
              if (controller.hasClients &&
                  controller.position.maxScrollExtent > 0) {
                controller.jumpTo(controller.position.maxScrollExtent);
              }
            },
          ),
        ),
        if (widget.onOpenConversationFind != null)
          IosIconButton(
            key: const ValueKey('miniMapSearchButton'),
            icon: Lucide.Search,
            minSize: 36,
            tooltip: l10n.conversationFindOpenTooltip,
            onTap: () {
              Navigator.of(context).pop();
              widget.onOpenConversationFind!();
            },
          ),
      ],
    );
  }

  Widget _selectionBar(BuildContext context, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    final count = _selectedIds.length;
    final hasSelection = count > 0 && widget.onDeleteMessages != null;
    return Row(
      children: [
        IosIconButton(
          key: const ValueKey('miniMapExitSelection'),
          icon: Lucide.X,
          size: 20,
          minSize: 36,
          semanticLabel: l10n.homePageCancel,
          onTap: _exitSelection,
        ),
        const SizedBox(width: 2),
        Expanded(
          child: Text(
            l10n.chatSelectionSelectedCountTitle(count),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: AppFontWeights.semibold,
              color: cs.onSurface,
            ),
          ),
        ),
        _MiniMapTextButton(label: '全选', onTap: _toggleSelectAll),
        _MiniMapTextButton(
          label: '复制',
          onTap: count > 0 ? _copySelected : null,
        ),
        _MiniMapTextButton(
          key: const ValueKey('miniMapDeleteSelection'),
          label: '删除',
          color: cs.error,
          onTap: hasSelection ? _deleteSelected : null,
        ),
      ],
    );
  }

  List<_QaPair> _buildPairs(List<ChatMessage> items) {
    final pairs = <_QaPair>[];
    ChatMessage? pendingUser;
    for (final m in items) {
      if (m.role == 'user') {
        // Push previous if it had no assistant
        if (pendingUser != null) {
          pairs.add(_QaPair(user: pendingUser, assistant: null));
        }
        pendingUser = m;
      } else if (m.role == 'assistant') {
        if (pendingUser != null) {
          pairs.add(_QaPair(user: pendingUser, assistant: m));
          pendingUser = null;
        } else {
          // Assistant without user: show as orphan on the right
          pairs.add(_QaPair(user: null, assistant: m));
        }
      }
    }
    if (pendingUser != null) {
      pairs.add(_QaPair(user: pendingUser, assistant: null));
    }
    return pairs;
  }
}

class _MiniMapIconButton extends StatelessWidget {
  const _MiniMapIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 36,
      width: 32,
      child: Tooltip(
        message: tooltip,
        child: IconButton(
          padding: EdgeInsets.zero,
          icon: Icon(
            icon,
            size: 18,
            color: cs.onSurface.withValues(alpha: enabled ? 0.9 : 0.25),
          ),
          onPressed: enabled ? onTap : null,
        ),
      ),
    );
  }
}

class _MiniMapTextButton extends StatelessWidget {
  const _MiniMapTextButton({
    super.key,
    required this.label,
    this.onTap,
    this.color,
  });

  final String label;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = color ?? cs.onSurface;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 10),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: AppFontWeights.medium,
            color: base.withValues(alpha: onTap == null ? 0.35 : 0.92),
          ),
        ),
      ),
    );
  }
}

class _QaPair {
  final ChatMessage? user;
  final ChatMessage? assistant;
  _QaPair({required this.user, required this.assistant});
}

class _MiniMapRow extends StatelessWidget {
  final _QaPair pair;
  final bool selecting;
  final Set<String> selectedIds;
  final Set<String> favoriteIds;
  final String? flashId;
  final Map<String, GlobalKey> bubbleKeys;
  final ValueChanged<String>? onToggle;
  final ValueChanged<String>? onOpen;
  final ValueChanged<ChatMessage>? onLongPressMessage;

  const _MiniMapRow({
    required this.pair,
    required this.selectedIds,
    required this.favoriteIds,
    required this.bubbleKeys,
    this.selecting = false,
    this.flashId,
    this.onToggle,
    this.onOpen,
    this.onLongPressMessage,
  });

  String _summaryText(ChatMessage? message) {
    if (message == null) return '';
    // ImagePart/FilePart are excluded; only TextPart contributes to the summary.
    final text = message.parts
        .whereType<TextPart>()
        .map((part) => part.text)
        .join();
    return _oneLine(text);
  }

  String _oneLine(String s) {
    // Strip vendor inline reasoning blocks if present; attachment markers are
    // no longer parsed because summaries are built from TextPart only.
    return _flattenWhitespace(
      s.replaceAll(
        RegExp(
          r'<(?:think|thought)>[\s\S]*?<\/(?:think|thought)>',
          caseSensitive: false,
        ),
        '',
      ),
    );
  }

  String _flattenWhitespace(String s) {
    return s.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Widget _bubbleLabel({
    required ChatMessage? message,
    required TextStyle style,
    required TextAlign textAlign,
  }) {
    final text = _summaryText(message);
    return Text(
      text.isNotEmpty ? text : ' ',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
      textAlign: textAlign,
    );
  }

  Widget _messageLine({
    required BuildContext context,
    required ChatMessage? message,
    required bool alignRight,
    required Color bg,
    required Color selectedBg,
    required Color borderColor,
    required TextStyle style,
    required double maxBubbleWidth,
  }) {
    final cs = Theme.of(context).colorScheme;
    if (message == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: _bubbleLabel(
          message: null,
          style: style,
          textAlign: TextAlign.left,
        ),
      );
    }
    final selected = selectedIds.contains(message.id);
    final favorite = favoriteIds.contains(message.id);
    final flash = flashId == message.id;
    final label = _bubbleLabel(
      message: message,
      style: style,
      textAlign: TextAlign.left,
    );
    final box = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? selectedBg : bg,
        borderRadius: BorderRadius.circular(16),
        border: (selected || flash)
            ? Border.all(
                color: flash ? cs.primary : borderColor,
                width: flash ? 1.4 : 1,
              )
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: label),
          if (favorite) ...[
            const SizedBox(width: 6),
            Icon(
              Lucide.Bookmark,
              size: 13,
              color: cs.primary.withValues(alpha: 0.75),
            ),
          ],
        ],
      ),
    );
    final interactive = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onOpen?.call(message.id),
      onLongPress: selecting ? null : () => onLongPressMessage?.call(message),
      child: box,
    );
    final checkbox = selecting
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: IosCheckbox(
              value: selected,
              size: 20,
              hitTestSize: 34,
              activeColor: cs.primary,
              onChanged: (_) => onToggle?.call(message.id),
            ),
          )
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: alignRight
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (checkbox != null) checkbox,
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxBubbleWidth - (selecting ? 34 : 0),
            ),
            child: KeyedSubtree(
              key: bubbleKeys.putIfAbsent(message.id, () => GlobalKey()),
              child: interactive,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final userStyle = TextStyle(
      fontSize: 15.5,
      height: 1.4,
      color: cs.onSurface,
    );
    final assistantStyle = TextStyle(fontSize: 15.7, height: 1.5);

    final userBg = (isDark
        ? cs.primary.withValues(alpha: 0.15)
        : cs.primary.withValues(alpha: 0.08));
    final userSelectedBg = (isDark
        ? cs.primary.withValues(alpha: 0.26)
        : cs.primary.withValues(alpha: 0.14));
    final userBorder = cs.primary.withValues(alpha: isDark ? 0.45 : 0.35);

    final assistantBg = cs.onSurface.withValues(alpha: isDark ? 0.06 : 0.04);
    final assistantSelectedBg = (isDark
        ? cs.primary.withValues(alpha: 0.18)
        : cs.primary.withValues(alpha: 0.10));
    final assistantBorder = cs.primary.withValues(alpha: isDark ? 0.38 : 0.28);

    final width = MediaQuery.sizeOf(context).width;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // User bubble — match main chat style (right aligned rounded rectangle)
        _messageLine(
          context: context,
          message: pair.user,
          alignRight: true,
          bg: userBg,
          selectedBg: userSelectedBg,
          borderColor: userBorder,
          style: userStyle,
          maxBubbleWidth: width * 0.75 - 32,
        ),
        // Assistant message
        _messageLine(
          context: context,
          message: pair.assistant,
          alignRight: false,
          bg: assistantBg,
          selectedBg: assistantSelectedBg,
          borderColor: assistantBorder,
          style: assistantStyle,
          maxBubbleWidth: width - 32,
        ),
      ],
    );
  }
}
