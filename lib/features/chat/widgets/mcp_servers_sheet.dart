import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/assistant.dart';
import '../../../core/models/conversation.dart';
import '../../../core/models/conversation_mcp_settings.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/mcp_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/ios_text_button.dart';
import '../../../theme/app_semantic_colors.dart';
import '../../mcp/utils/mcp_tool_groups.dart';
import '../../mcp/widgets/mcp_server_avatar.dart';
import '../../mcp/widgets/mcp_tool_connection_status.dart';
import 'tools_sheet_row.dart';

/// Second-level sheet opened from the reasoning (lightbulb) composer sheet:
/// the same MCP server selection that lives in the chat tools sheet, but as a
/// plain list so the composer sheet stays a short stack of entry rows.
Future<void> showMcpServersSheet(
  BuildContext context, {
  required String assistantId,
  String? conversationId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.overlaySurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _McpServersSheet(
      assistantId: assistantId,
      conversationId: conversationId,
    ),
  );
}

class _McpServersSheet extends StatelessWidget {
  const _McpServersSheet({
    required this.assistantId,
    this.conversationId,
  });

  final String assistantId;
  final String? conversationId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final mcp = context.watch<McpProvider>();
    final assistant = context.select<AssistantProvider, Assistant?>(
      (provider) => provider.getById(assistantId),
    );
    if (assistant == null) return const SizedBox.shrink();
    final conversationScoped =
        assistant.allowConversationMcp && conversationId != null;
    final conversation = conversationScoped
        ? context.select<ChatService, Conversation?>(
            (chat) => chat.getConversation(conversationId!),
          )
        : null;
    final inherited = !ConversationMcpSettings.isOverridden(conversation);
    final groups = mcpToolGroups(mcp);
    final servers = groups.expand((group) => group.servers).toList(
          growable: false,
        );

    final selected = ConversationMcpSettings.effectiveServerIds(
      assistant,
      conversation,
    ).toSet();
    final selectedCount = servers
        .where((server) => selected.contains(server.id))
        .length;

    Future<void> setIds(Iterable<String>? ids) {
      if (conversationScoped) {
        return context.read<ChatService>().setConversationMcpServers(
              conversationId!,
              ids?.toList(growable: false),
            );
      }
      return context.read<AssistantProvider>().updateAssistant(
            assistant.copyWith(mcpServerIds: ids!.toList(growable: false)),
          );
    }

    Future<void> setSelected(String id, bool value) {
      final next = selected.toSet();
      if (value) {
        next.add(id);
      } else {
        next.remove(id);
      }
      return setIds(next);
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                '${l10n.mcpAssistantSheetTitle} · $selectedCount/${servers.length}',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                ),
              ),
            ),
            if (conversationScoped)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: OverflowBar(
                  alignment: MainAxisAlignment.spaceBetween,
                  spacing: 8,
                  overflowAlignment: OverflowBarAlignment.start,
                  children: [
                    Text(
                      inherited
                          ? l10n.mcpSelectionInherited
                          : l10n.mcpSelectionCustom,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5),
                      ),
                    ),
                    Wrap(
                      alignment: WrapAlignment.end,
                      children: [
                        if (!inherited)
                          IosTextButton(
                            label: l10n.mcpInheritAssistant,
                            fontSize: 12,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 6),
                            onPressed: () => unawaited(setIds(null)),
                          ),
                        IosTextButton(
                          label: l10n.mcpAssistantSheetClearAll,
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                          padding:
                              const EdgeInsets.symmetric(horizontal: 6),
                          onPressed: !inherited && selected.isEmpty
                              ? null
                              : () => unawaited(setIds(const [])),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            if (servers.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  l10n.mcpSelectionInherited,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                  ),
                ),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final group in groups) ...[
                        if (mcp.groups.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
                            child: Text(
                              group.group?.name ?? l10n.providerGroupsOther,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: .5),
                              ),
                            ),
                          ),
                        for (final server in group.servers)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ToolsSheetRow(
                                  leading: McpServerAvatar(
                                    server: server,
                                    size: 20,
                                    radius: 7,
                                    showBackground: false,
                                    status:
                                        mcp.statusFor(server.id) ==
                                                McpStatus.connected
                                            ? null
                                            : mcp.statusFor(server.id),
                                  ),
                                  label: server.name,
                                  selected: selected.contains(server.id),
                                  detail:
                                      '${server.tools.where((tool) => tool.enabled).length}/${server.tools.length}',
                                  onTap: () => unawaited(
                                    setSelected(
                                      server.id,
                                      !selected.contains(server.id),
                                    ),
                                  ),
                                  trailing: IosSwitch(
                                    value: selected.contains(server.id),
                                    semanticLabel: server.name,
                                    onChanged: (value) => unawaited(
                                      setSelected(server.id, value),
                                    ),
                                  ),
                                ),
                                McpToolConnectionStatus(serverId: server.id),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
