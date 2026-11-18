import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/providers/world_book_provider.dart';
import '../../icons/lucide_adapter.dart';
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
  }

  @override
  void dispose() {
    _promptController.dispose();
    _instructionController.dispose();
    super.dispose();
  }

  Future<void> _pickBook() async {
    final settings = context.read<SettingsProvider>();
    final books = context.read<WorldBookProvider>().books;
    if (books.isEmpty) {
      _toast('还没有世界书');
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '选择世界书',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: MomentColors.primaryText,
                  ),
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  for (final book in books)
                    InkWell(
                      onTap: () => Navigator.of(ctx).pop(book.id),
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
                                book.name.trim().isEmpty ? '未命名世界书' : book.name,
                                style: const TextStyle(
                                  fontSize: 15,
                                  color: MomentColors.primaryText,
                                ),
                              ),
                            ),
                            if (book.id == settings.momentBookId)
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
    );
    if (picked == null) return;
    await settings.setMomentBookId(picked);
    if (!mounted) return;
    setState(() {});
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
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final book = context.watch<WorldBookProvider>().getById(
      settings.momentBookId.trim(),
    );
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
            _Row(
              label: '世界书',
              value: book == null
                  ? '未选择'
                  : (book.name.trim().isEmpty ? '未命名世界书' : book.name),
              onTap: _pickBook,
            ),
            _Row(label: '模型', value: modelText, onTap: _pickModel),
            const SizedBox(height: 8),
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
  });

  final String title;
  final String hint;
  final TextEditingController controller;
  final int minLines;

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
            maxLines: null,
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
