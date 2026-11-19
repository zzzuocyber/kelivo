import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/model_spec.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/world_book_provider.dart';
import '../../core/services/model_spec/model_spec_resolver.dart';
import '../../icons/lucide_adapter.dart';
import '../../l10n/app_localizations.dart';
import '../chat/widgets/reasoning_level_sheet.dart';
import '../model/widgets/model_select_sheet.dart';
import 'moment_service.dart';
import 'moment_widgets.dart';

/// 朋友圈设置：选一本世界书、填系统提示词和附加指令、选定一个模型。
/// 这些值都存进设置里，跟着备份走。
class MomentSettingsPage extends StatefulWidget {
  const MomentSettingsPage({super.key});

  @override
  State<MomentSettingsPage> createState() => _MomentSettingsPageState();
}

class _MomentSettingsPageState extends State<MomentSettingsPage> {
  late final TextEditingController _promptController;
  late final TextEditingController _instructionController;
  late final TextEditingController _personaController;
  late final TextEditingController _contextCharsController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _promptController = TextEditingController(
      text: settings.momentSystemPrompt,
    );
    _instructionController = TextEditingController(
      text: settings.momentExtraInstruction,
    );
    _personaController = TextEditingController(
      text: settings.momentPersonaName,
    );
    _contextCharsController = TextEditingController(
      text: settings.momentContextChars.toString(),
    );
  }

  @override
  void dispose() {
    _promptController.dispose();
    _instructionController.dispose();
    _personaController.dispose();
    _contextCharsController.dispose();
    super.dispose();
  }

  Future<void> _pickBook() async {
    final settings = context.read<SettingsProvider>();
    final books = context.read<WorldBookProvider>().books;
    if (books.isEmpty) {
      _toast('还没有世界书');
      return;
    }
    final selected = <String>{...settings.momentBookIds};
    final picked = await showModalBottomSheet<List<String>>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
                child: Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        '选择世界书（可以多本）',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: MomentColors.primaryText,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(selected.toList()),
                      child: const Text('完成'),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: <Widget>[
                    for (final book in books)
                      InkWell(
                        onTap: () => setSheetState(() {
                          if (!selected.remove(book.id)) selected.add(book.id);
                        }),
                        child: Container(
                          color: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  book.name.trim().isEmpty
                                      ? '未命名世界书'
                                      : book.name,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    color: MomentColors.primaryText,
                                  ),
                                ),
                              ),
                              if (selected.contains(book.id))
                                const Icon(
                                  Lucide.Check,
                                  size: 18,
                                  color: MomentColors.name,
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    await settings.setMomentBookIds(picked);
    if (!mounted) return;
    setState(() {});
  }

  /// 把选中的几本世界书拼成一行字给设置页显示。
  String _booksText(List<String> ids, WorldBookProvider provider) {
    if (ids.isEmpty) return '未选择';
    final names = <String>[];
    for (final id in ids) {
      final book = provider.getById(id);
      if (book == null) continue;
      final name = book.name.trim();
      names.add(name.isEmpty ? '未命名世界书' : name);
    }
    if (names.isEmpty) return '未选择';
    if (names.length <= 2) return names.join('、');
    return '${names.take(2).join('、')} 等 ${names.length} 本';
  }

  Future<void> _pickModel() async {
    final settings = context.read<SettingsProvider>();
    final selection = await showModelSelector(
      context,
      initialProviderKey: settings.momentModelProvider,
      initialModelId: settings.momentModelId,
    );
    if (selection == null) return;
    if (selection.providerKey.isEmpty || selection.modelId.isEmpty) return;
    await settings.setMomentModel(selection.providerKey, selection.modelId);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _pickReasoning() async {
    final settings = context.read<SettingsProvider>();
    final providerKey =
        settings.momentModelProvider ?? settings.currentModelProvider;
    final modelId = settings.momentModelId ?? settings.currentModelId;
    if (providerKey == null || modelId == null) {
      _toast('先选一个模型');
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final config = settings.getProviderConfig(providerKey);
    final spec = ModelSpecResolver.instance.spec(config, modelId);
    final rows = <(String, ReasoningLevel)>[
      if (spec.reasoning.canDisable)
        (reasoningLevelLabel(l10n, ReasoningLevel.off), ReasoningLevel.off),
      (reasoningLevelLabel(l10n, ReasoningLevel.auto), ReasoningLevel.auto),
      for (final level in spec.reasoning.levels)
        (reasoningLevelLabel(l10n, level), level),
    ];
    final picked = await showModalBottomSheet<ReasoningLevel>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                '深度思考',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: MomentColors.primaryText,
                ),
              ),
            ),
            for (final row in rows)
              InkWell(
                onTap: () => Navigator.of(ctx).pop(row.$2),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          row.$1,
                          style: const TextStyle(
                            fontSize: 15,
                            color: MomentColors.primaryText,
                          ),
                        ),
                      ),
                      if (settings.momentReasoning == row.$2)
                        const Icon(
                          Lucide.Check,
                          size: 18,
                          color: MomentColors.name,
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await settings.setMomentReasoning(picked);
    if (!mounted) return;
    setState(() {});
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final settings = context.read<SettingsProvider>();
    await settings.setMomentSystemPrompt(_promptController.text);
    await settings.setMomentExtraInstruction(_instructionController.text);
    await settings.setMomentPersonaName(_personaController.text);
    final chars = int.tryParse(_contextCharsController.text.trim()) ?? 0;
    await settings.setMomentContextChars(chars < 0 ? 0 : chars);
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final booksProvider = context.watch<WorldBookProvider>();
    final bookText = _booksText(settings.momentBookIds, booksProvider);
    final providerKey =
        settings.momentModelProvider ?? settings.currentModelProvider;
    final modelId = settings.momentModelId ?? settings.currentModelId;
    final modelText = (providerKey == null || modelId == null)
        ? '未选择'
        : '${settings.getProviderConfig(providerKey).name} · $modelId';

    return Theme(
      data: momentLightTheme(),
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: const Text(
            '朋友圈设置',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: _saving ? null : _save,
              child: const Text('保存'),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: <Widget>[
            _Row(label: '世界书', value: bookText, onTap: _pickBook),
            _Row(label: '模型', value: modelText, onTap: _pickModel),
            _Row(
              label: '深度思考',
              value: reasoningLevelLabel(
                AppLocalizations.of(context)!,
                settings.momentReasoning,
              ),
              onTap: _pickReasoning,
            ),
            const SizedBox(height: 8),
            _Section(
              title: '我的马甲',
              hint: '填了就是你在朋友圈里的名字，能发帖、评论、点赞。空着就用「我」',
              controller: _personaController,
              minLines: 1,
              singleLine: true,
            ),
            _Section(
              title: '旧帖最多喂多少字',
              hint: '0 = 不限制，全部喂回去；填数字就按最新的往回装，装够就停',
              controller: _contextCharsController,
              minLines: 1,
              singleLine: true,
              numberOnly: true,
            ),
            _Section(
              title: '系统提示词',
              hint: defaultMomentSystemPrompt,
              controller: _promptController,
              minLines: 5,
            ),
            _Section(
              title: '附加指令',
              hint: '每次生成都会拼在系统提示词后面，可以不填',
              controller: _instructionController,
              minLines: 3,
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, required this.onTap});

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: <Widget>[
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                color: MomentColors.primaryText,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  color: MomentColors.secondaryText,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Lucide.ChevronRight,
              size: 16,
              color: MomentColors.secondaryText,
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.hint,
    required this.controller,
    required this.minLines,
    this.singleLine = false,
    this.numberOnly = false,
  });

  final String title;
  final String hint;
  final TextEditingController controller;
  final int minLines;
  final bool singleLine;
  final bool numberOnly;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              color: MomentColors.primaryText,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            minLines: minLines,
            maxLines: singleLine ? 1 : null,
            keyboardType: numberOnly ? TextInputType.number : null,
            style: const TextStyle(
              fontSize: 14,
              height: 1.45,
              color: MomentColors.primaryText,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintMaxLines: 6,
              hintStyle: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: MomentColors.secondaryText,
              ),
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}
