import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/services/chat/chat_service.dart';
import '../../core/services/social_store.dart';
import '../../core/utils/pinyin_sort.dart';
import '../../icons/lucide_adapter.dart';
import '../../utils/avatar_files.dart';
import '../model/widgets/model_select_sheet.dart';
import '../moment/moment_models.dart';
import '../moment/moment_store.dart';
import 'wechat_models.dart';
import 'wechat_store.dart';
import 'wechat_ui.dart';

/// 「我」这一页：头像、马甲名、设置入口。
///
/// 头像存的是朋友圈那份（键 `@me`），所以两边改同一张。
class WechatMePage extends StatefulWidget {
  const WechatMePage({super.key, this.onChanged});

  /// 改了设置后通知外层刷新（马甲名变了，气泡上的名字要跟着变）。
  final VoidCallback? onChanged;

  @override
  State<WechatMePage> createState() => _WechatMePageState();
}

class _WechatMePageState extends State<WechatMePage> {
  late WechatStore _store;
  WechatSettings _settings = const WechatSettings();
  Map<String, String> _avatars = const <String, String>{};

  @override
  void initState() {
    super.initState();
    _store = WechatStore(context.read<ChatService>());
    _reload();
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _settings = _store.wechatSettings();
      _avatars = _store.avatarPaths();
    });
  }

  Future<void> _pickAvatar() async {
    final path = await _pickImage();
    if (path == null || !mounted) return;
    try {
      final stored = await importAvatarFile(path);
      await MomentStore(context.read<ChatService>())
          .saveAssets(MomentAssets.personaKey, avatar: stored);
      if (!mounted) return;
      _reload();
      widget.onChanged?.call();
    } catch (_) {
      _toast('头像没存上，再试一次');
    }
  }

  Future<String?> _pickImage() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 88,
      );
      return file?.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _editPersona() async {
    final controller = TextEditingController(text: _settings.persona);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('我的名字'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '在微信里显示的名字'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('算了'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogCtx).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || value == null) return;
    await _store.saveWechatSettings(_settings.copyWith(persona: value));
    // 暂时只用一个马甲：改完顺手同步进每个群，免得群里私聊两个名字。
    await _store.syncPersonaToGroups(value);
    if (!mounted) return;
    _reload();
    widget.onChanged?.call();
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final persona = _settings.effectivePersona;
    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
          child: Row(
            children: <Widget>[
              GestureDetector(
                onTap: _pickAvatar,
                child: WechatAvatarText(
                  name: persona,
                  size: 60,
                  imagePath: _avatars[MomentAssets.personaKey],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      persona,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                        color: WechatColors.primaryText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '点头像换一张（跟朋友圈是同一张）',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: WechatColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _editPersona,
                icon: const Icon(
                  Lucide.Pencil,
                  size: 19,
                  color: WechatColors.secondaryText,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _row(
          icon: Lucide.Settings,
          title: '设置',
          onTap: () async {
            await Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const WechatSettingsSubPage(),
              ),
            );
            if (!mounted) return;
            _reload();
            widget.onChanged?.call();
          },
        ),
      ],
    );
  }

  Widget _row({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 20, color: const Color(0xFF4A4A4A)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  color: WechatColors.primaryText,
                ),
              ),
            ),
            const Icon(Lucide.ChevronRight, size: 17, color: Color(0xFFC8C8C8)),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 微信设置（从「我」进来）
// ============================================================

class WechatSettingsSubPage extends StatefulWidget {
  const WechatSettingsSubPage({super.key});

  @override
  State<WechatSettingsSubPage> createState() => _WechatSettingsSubPageState();
}

class _WechatSettingsSubPageState extends State<WechatSettingsSubPage> {
  late WechatStore _store;
  WechatSettings _settings = const WechatSettings();

  @override
  void initState() {
    super.initState();
    _store = WechatStore(context.read<ChatService>());
    _reload();
  }

  void _reload() {
    if (!mounted) return;
    setState(() => _settings = _store.wechatSettings());
  }

  /// 全局那份间隔：只当**新建群**的默认值，已经建好的群各改各的。
  Future<void> _pickGlobalInterval() async {
    var preset = _settings.intervalPreset;
    var min = _settings.customMinSeconds;
    var max = _settings.customMaxSeconds;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (sheetCtx) => Theme(
        data: wechatLightTheme(),
        child: StatefulBuilder(
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
                          '群聊默认间隔',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: WechatColors.primaryText,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('好'),
                      ),
                    ],
                  ),
                ),
                WechatIntervalPicker(
                  preset: preset,
                  customMin: min,
                  customMax: max,
                  note: '这是默认档；建群时选「跟随全局」的群会跟着这里变。',
                  onChanged: (nextPreset, nextMin, nextMax) {
                    setSheetState(() {
                      preset = nextPreset;
                      min = nextMin;
                      max = nextMax;
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (saved != true || !mounted) return;
    await _store.saveWechatSettings(
      _settings.copyWith(
        intervalPreset: preset,
        customMinSeconds: min,
        customMaxSeconds: max,
      ),
    );
    if (!mounted) return;
    _reload();
  }

  /// 一次回几条的概率档：单条始终最多，档位只调连发的稀罕程度。
  Future<void> _pickBurstPreset() async {
    var preset = _settings.burstPreset;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (sheetCtx) => Theme(
        data: wechatLightTheme(),
        child: StatefulBuilder(
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
                          '一次回几条',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: WechatColors.primaryText,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('好'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    '不管哪档，一条都是最多的；群聊和私聊都跟着这里。',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: WechatColors.secondaryText,
                      height: 1.5,
                    ),
                  ),
                ),
                const Divider(height: 0.5, thickness: 0.5),
                for (final item in WechatBurstPreset.values)
                  ListTile(
                    title: Text(
                      item.label,
                      style: const TextStyle(
                        fontSize: 15,
                        color: wechatMenuInk,
                      ),
                    ),
                    subtitle: Text(
                      item.hint,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: WechatColors.secondaryText,
                      ),
                    ),
                    trailing: preset == item
                        ? const Icon(
                            Lucide.Check,
                            size: 18,
                            color: WechatColors.green,
                          )
                        : null,
                    onTap: () => setSheetState(() => preset = item),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (saved != true || !mounted) return;
    await _store.saveWechatSettings(_settings.copyWith(burstPreset: preset));
    if (!mounted) return;
    _reload();
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final intervalText = wechatIntervalLabel(
      _settings.intervalPreset,
      customMinSeconds: _settings.customMinSeconds,
      customMaxSeconds: _settings.customMaxSeconds,
    );

    return Theme(
      data: wechatLightTheme(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF2F2F2),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF7F7F7),
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          shape: const Border(
            bottom: BorderSide(color: Color(0xFFE0E0E0), width: 0.5),
          ),
          leading: IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Lucide.ChevronLeft, size: 22, color: Colors.black),
          ),
          title: const Text(
            '微信设置',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
        ),
        body: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            const SizedBox(height: 10),
            _settingRow(
              title: '群聊默认间隔',
              value: intervalText,
              onTap: _pickGlobalInterval,
            ),
            const SizedBox(height: 10),
            _settingRow(
              title: '连发条数概率',
              value: _settings.burstPreset.label,
              onTap: _pickBurstPreset,
            ),
          ],
        ),
      ),
    );
  }

  Widget _settingRow({
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15.5,
                  color: WechatColors.primaryText,
                ),
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 12.5,
                color: WechatColors.secondaryText,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Lucide.ChevronRight, size: 16, color: Color(0xFFC8C8C8)),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 角色管理：头像 + 模型
// ============================================================

class WechatCharactersPage extends StatefulWidget {
  const WechatCharactersPage({super.key});

  @override
  State<WechatCharactersPage> createState() => _WechatCharactersPageState();
}

class _WechatCharactersPageState extends State<WechatCharactersPage> {
  late WechatStore _store;
  late SocialStore _social;
  List<WechatContact> _contacts = const <WechatContact>[];
  Map<String, String> _avatars = const <String, String>{};

  @override
  void initState() {
    super.initState();
    final chat = context.read<ChatService>();
    _store = WechatStore(chat);
    // 心声开关也搬到这里：统一后的「角色管理」就在这页，开关不能再只藏在朋友圈里。
    _social = SocialStore(chat);
    _reload();
  }

  /// 点行尾的心形：开/关这个角色的心声（一份全局名单，群聊/私聊/朋友圈通用）。
  Future<void> _toggleHeartVoice(String name) async {
    final key = name.trim();
    if (key.isEmpty) return;
    await _social.setHeartVoice(key, !_social.heartVoiceOn(key));
    if (!mounted) return;
    setState(() {});
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _contacts = sortedByPinyin(_store.contacts(), (c) => c.name);
      _avatars = _store.avatarPaths();
    });
  }

  /// 换头像：存进朋友圈那份资产里，所以朋友圈那边同步变。
  Future<void> _pickAvatar(WechatContact contact) async {
    String? path;
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 88,
      );
      path = file?.path;
    } catch (_) {
      path = null;
    }
    if (path == null || !mounted) return;
    try {
      final stored = await importAvatarFile(path);
      await MomentStore(context.read<ChatService>())
          .saveAssets(contact.name, avatar: stored);
      if (!mounted) return;
      _reload();
    } catch (_) {
      _toast('头像没存上，再试一次');
    }
  }

  Future<void> _clearAvatar(WechatContact contact) async {
    await MomentStore(context.read<ChatService>())
        .saveAssets(contact.name, clearAvatar: true);
    if (!mounted) return;
    _reload();
  }

  /// 绑模型。选择器自带「跟随默认」那一项，选它就是把绑定清掉。
  Future<void> _pickModel(WechatContact contact) async {
    final picked = await showModelSelector(
      context,
      initialProviderKey: contact.providerKey,
      initialModelId: contact.modelId,
      allowInherit: true,
      inheritLabel: '跟随默认模型',
    );
    if (picked == null || !mounted) return;
    if (picked.isInherit) {
      await _store.saveContact(contact.copyWith(clearModel: true));
    } else {
      await _store.saveContact(
        contact.copyWith(
          providerKey: picked.providerKey,
          modelId: picked.modelId,
        ),
      );
    }
    if (!mounted) return;
    _reload();
  }

  /// 私聊偶尔不回：全局默认开，可按角色单独关。
  Future<void> _pickNoReply(WechatContact contact) async {
    var enabled = contact.noReplyEnabled;
    var strength = contact.noReplyStrength;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (sheetCtx) => Theme(
        data: wechatLightTheme(),
        child: StatefulBuilder(
          builder: (ctx, setSheetState) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '${contact.name} 会不会不搭理人',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: WechatColors.primaryText,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('好'),
                      ),
                    ],
                  ),
                ),
                SwitchListTile(
                  value: enabled,
                  onChanged: (value) => setSheetState(() => enabled = value),
                  title: const Text(
                    '会不搭理人',
                    style: TextStyle(
                      fontSize: 14,
                      color: WechatColors.primaryText,
                    ),
                  ),
                  subtitle: const Text(
                    '默认会偶尔不搭理你；关掉就是每次都回。',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: WechatColors.secondaryText,
                    ),
                  ),
                ),
                if (enabled) ...<Widget>[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 6, 16, 4),
                    child: Text(
                      '不搭理的频繁程度',
                      style: TextStyle(
                        fontSize: 12,
                        color: WechatColors.secondaryText,
                      ),
                    ),
                  ),
                  for (final item in WechatNoReplyStrength.values)
                    RadioListTile<WechatNoReplyStrength>(
                      value: item,
                      groupValue: strength,
                      onChanged: (value) {
                        if (value != null) {
                          setSheetState(() => strength = value);
                        }
                      },
                      title: Text(
                        item.label,
                        style: const TextStyle(
                          fontSize: 14,
                          color: WechatColors.primaryText,
                        ),
                      ),
                      subtitle: Text(
                        item.hint,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: WechatColors.secondaryText,
                        ),
                      ),
                      dense: true,
                    ),
                ],
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
    if (saved != true || !mounted) return;
    await _store.saveContact(
      contact.copyWith(noReplyEnabled: enabled, noReplyStrength: strength),
    );
    if (!mounted) return;
    _reload();
  }

  String _modelLabel(WechatContact contact, SettingsProvider settings) {
    final provider = contact.providerKey;
    final model = contact.modelId;
    if (provider == null || model == null) return '跟随默认';
    final config = settings.getProviderConfig(provider);
    final name = config.name.trim().isEmpty ? provider : config.name;
    return '$name · $model';
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return Theme(
      data: wechatLightTheme(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF2F2F2),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF7F7F7),
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          shape: const Border(
            bottom: BorderSide(color: Color(0xFFE0E0E0), width: 0.5),
          ),
          leading: IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Lucide.ChevronLeft, size: 22, color: Colors.black),
          ),
          title: const Text(
            '角色管理',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
        ),
        body: _contacts.isEmpty
            ? const Center(
                child: Text(
                  '通讯录里还没人。先去通讯录加几个。',
                  style: TextStyle(
                    fontSize: 13,
                    color: WechatColors.secondaryText,
                  ),
                ),
              )
            : ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: _contacts.length + 1,
                itemBuilder: (_, index) {
                  if (index == 0) {
                    return Container(
                      color: const Color(0xFFF2F2F2),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: const Text(
                        '点心形图标开启心声：角色说话时会附一段心里话，长按消息可偷看。',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: WechatColors.secondaryText,
                          height: 1.5,
                        ),
                      ),
                    );
                  }
                  final contact = _contacts[index - 1];
                  return Container(
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                    child: Row(
                      children: <Widget>[
                        GestureDetector(
                          onTap: () => _pickAvatar(contact),
                          onLongPress: () => _clearAvatar(contact),
                          child: WechatAvatarText(
                            name: contact.name,
                            size: 44,
                            imagePath: _avatars[contact.name],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                contact.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15.5,
                                  color: WechatColors.primaryText,
                                ),
                              ),
                              const SizedBox(height: 2),
                              GestureDetector(
                                onTap: () => _pickModel(contact),
                                behavior: HitTestBehavior.opaque,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Text(
                                      _modelLabel(contact, settings),
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: WechatColors.secondaryText,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    const Icon(
                                      Lucide.ChevronRight,
                                      size: 12,
                                      color: Color(0xFFC8C8C8),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 2),
                              GestureDetector(
                                onTap: () => _pickNoReply(contact),
                                behavior: HitTestBehavior.opaque,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Text(
                                      contact.noReplyEnabled
                                          ? '会不搭理人 · ${contact.noReplyStrength.label}'
                                          : '不会不搭理人',
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: WechatColors.secondaryText,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    const Icon(
                                      Lucide.ChevronRight,
                                      size: 12,
                                      color: Color(0xFFC8C8C8),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => _toggleHeartVoice(contact.name),
                          tooltip: _social.heartVoiceOn(contact.name)
                              ? '关掉心声'
                              : '开启心声',
                          icon: Icon(
                            _social.heartVoiceOn(contact.name)
                                ? Lucide.Heart
                                : Lucide.HeartOff,
                            size: 18,
                            color: _social.heartVoiceOn(contact.name)
                                ? WechatColors.red
                                : const Color(0xFF9A9A9A),
                          ),
                        ),
                        IconButton(
                          onPressed: () => _pickModel(contact),
                          icon: const Icon(
                            Lucide.Bot,
                            size: 18,
                            color: Color(0xFF9A9A9A),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
