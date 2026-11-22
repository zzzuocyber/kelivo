import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/chat/chat_service.dart';
import '../../core/services/social_context_builder.dart';
import '../../core/services/social_store.dart';
import '../../core/utils/token_format.dart';
import '../../icons/lucide_adapter.dart';
import '../wechat/wechat_store.dart';
import 'moment_models.dart';
import 'moment_store.dart';
import 'moment_widgets.dart';

/// 小手机 → 设置 → 记忆管理。
///
/// 管三件事：
/// 1. 三个场景（朋友圈/群聊/私聊）喂给模型时用摘要还是完整；
/// 2. 显示三处累计发给模型的 token（各 + 合计）；
/// 3. 给每个角色设作息表——三处共用同一份，时间地点因此始终对得上。
class MomentSocialMemoryPage extends StatefulWidget {
  const MomentSocialMemoryPage({super.key});

  @override
  State<MomentSocialMemoryPage> createState() => _MomentSocialMemoryPageState();
}

class _MomentSocialMemoryPageState extends State<MomentSocialMemoryPage> {
  late SocialStore _social;
  late WechatStore _wechat;
  late MomentStore _moment;

  Map<String, SocialContextMode> _modes = const <String, SocialContextMode>{};
  SocialTokenStats _stats = const SocialTokenStats();
  Map<String, List<SocialTimeSlot>> _schedules = const <String, List<SocialTimeSlot>>{};
  List<String> _characters = const <String>[];
  String _plotSummary = '';
  String _compressPrompt = kDefaultCompressPrompt;
  List<PlotLogEntry> _plotLogs = const <PlotLogEntry>[];
  SocialWorldClock _clock = SocialWorldClock.real();

  @override
  void initState() {
    super.initState();
    final chat = context.read<ChatService>();
    _social = SocialStore(chat);
    _wechat = WechatStore(chat);
    _moment = MomentStore(chat);
    _reload();
  }

  void _reload() {
    final names = <String>{};
    for (final c in momentCharactersOf(_moment.findConversation())) {
      if (c.name.trim().isNotEmpty) names.add(c.name.trim());
    }
    for (final c in _wechat.contacts()) {
      if (c.name.trim().isNotEmpty) names.add(c.name.trim());
    }
    final sorted = names.toList()..sort();
    if (!mounted) return;
    setState(() {
      _modes = _social.contextModes();
      _stats = _social.tokenStats();
      _schedules = _social.schedules();
      _characters = sorted;
      _plotSummary = _social.plotSummary;
      _compressPrompt = _social.compressPrompt;
      _plotLogs = _social.plotLogs();
      _clock = _social.worldClock;
    });
  }

  /// 故事时间：三场景 + 离线补算共用的时间坐标。
  String get _storyNowText => socialTimeLine(_clock.now());

  Future<void> _pickWorldClockDate() async {
    final now = _clock.now();
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year, now.month, now.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: now.hour, minute: now.minute),
    );
    if (time == null || !mounted) return;
    await _social.setWorldClockTo(DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ));
    _reload();
  }

  Future<void> _advanceWorldClock(Duration by) async {
    await _social.advanceWorldClock(by);
    _reload();
  }

  Future<void> _followRealTime() async {
    await _social.setWorldClockFollowReal();
    _reload();
  }

  Future<void> _setMode(String scene, SocialContextMode mode) async {
    await _social.setContextMode(scene, mode);
    _reload();
  }

  Future<void> _editPlotSummary() async {
    final controller = TextEditingController(text: _plotSummary);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('手写剧情概括', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 12,
            minLines: 8,
            decoration: const InputDecoration(
              hintText: '把当前最重要的剧情、关系、冲突写下来，'
                  '三处生成都会读这一份。',
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontSize: 13.5),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    await _social.setPlotSummary(value);
    _reload();
  }

  Future<void> _editCompressPrompt() async {
    final controller = TextEditingController(text: _compressPrompt);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('压缩词（填写参考）', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 12,
            minLines: 8,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontSize: 13.5),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await _social.resetCompressPrompt();
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('恢复预设'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    // 恢复预设时 pop() 没带值 → value==null，此时已 reset，只需 reload。
    if (value != null) await _social.setCompressPrompt(value);
    _reload();
  }

  Future<void> _clearPlotLogs() async {
    await _social.clearPlotLogs();
    _reload();
  }

  void _showPlotLog(PlotLogEntry entry) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          entry.scene,
          style: const TextStyle(fontSize: 16),
        ),
        content: SingleChildScrollView(
          child: Text(
            '${DateTime.fromMillisecondsSinceEpoch(entry.at)}\n\n${entry.text}',
            style: const TextStyle(fontSize: 13.5, height: 1.5),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: momentLightTheme(),
      child: Scaffold(
        backgroundColor: MomentColors.background,
        appBar: AppBar(
          titleSpacing: 0,
          title: const Text(
            '记忆管理',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          actions: <Widget>[
            IconButton(
              icon: const Icon(Lucide.RefreshCw, size: 19),
              tooltip: '清零统计',
              onPressed: () async {
                await _social.resetTokens();
                _reload();
              },
            ),
          ],
        ),
        body: ListView(
          children: <Widget>[
            _sectionTitle('故事时间坐标（三场景 + 离线补算共用）'),
            _worldClockCard(),
            _sectionTitle('喂给模型的方式'),
            _modeRow('朋友圈', 'moment'),
            _modeRow('群聊', 'group'),
            _modeRow('私聊', 'dm'),
            const SizedBox(height: 8),
            _sectionTitle('剧情概括（手写，三处共用一份）'),
            Container(
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  InkWell(
                    onTap: _editPlotSummary,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              _plotSummary.trim().isEmpty
                                  ? '还没写。点这里写一份剧情概括，摘要模式下三处都会用它。'
                                  : _plotSummary.trim(),
                              maxLines: 6,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                height: 1.5,
                                color: _plotSummary.trim().isEmpty
                                    ? MomentColors.secondaryText
                                    : MomentColors.primaryText,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Lucide.ChevronRight, size: 16, color: Color(0xFFC8C8C8)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _sectionTitle('压缩词（写剧情概括时的填写参考，可清空/恢复预设）'),
            Container(
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  InkWell(
                    onTap: _editCompressPrompt,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              _compressPrompt.trim().isEmpty
                                  ? '（已清空）'
                                  : _compressPrompt.trim(),
                              maxLines: 5,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.5,
                                color: _compressPrompt.trim().isEmpty
                                    ? MomentColors.secondaryText
                                    : MomentColors.primaryText,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Lucide.ChevronRight, size: 16, color: Color(0xFFC8C8C8)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _sectionTitle('剧情控制记录（你写过的剧情）'),
            Container(
              color: Colors.white,
              child: Column(
                children: <Widget>[
                  if (_plotLogs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(18),
                      child: Text(
                        '还没有记录。用天意「控制剧情走向」写过的剧情会出现在这里。',
                        style: TextStyle(fontSize: 13, color: MomentColors.secondaryText),
                      ),
                    )
                  else
                    for (final entry in _plotLogs)
                      InkWell(
                        onTap: () => _showPlotLog(entry),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      entry.scene,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: MomentColors.secondaryText,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      entry.text,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13.5),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Lucide.ChevronRight, size: 16, color: Color(0xFFC8C8C8)),
                            ],
                          ),
                        ),
                      ),
                  if (_plotLogs.isNotEmpty)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _clearPlotLogs,
                        child: const Text('清空记录', style: TextStyle(fontSize: 13)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _sectionTitle('已发给模型的上下文'),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _statLine('朋友圈', _stats.moment),
                  _statLine('群聊', _stats.group),
                  _statLine('私聊', _stats.dm),
                  const Divider(height: 16, thickness: 0.5),
                  _statLine('合计', _stats.total, bold: true),
                  const SizedBox(height: 6),
                  const Text(
                    '约数。记忆开关改成「摘要」后，之后的消耗会变小。',
                    style: TextStyle(fontSize: 12, color: MomentColors.secondaryText),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _sectionTitle('角色作息（三处共用）'),
            if (_characters.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  '还没有角色。先在朋友圈或微信里加人，再来设作息。',
                  style: TextStyle(fontSize: 13, color: MomentColors.secondaryText),
                ),
              )
            else
              for (final name in _characters)
                _characterRow(name, _schedules[name] ?? const <SocialTimeSlot>[]),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

  Widget _worldClockCard() {
    final following = _clock.followReal;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _storyNowText,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: MomentColors.primaryText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            following
                ? '当前跟随手机真实时间。设定一个故事时刻后，三个场景都会按它走。'
                : '已锁定故事时间，会照常往前流；下面可推进/回拨或改回真实时间。',
            style: const TextStyle(
              fontSize: 11.5,
              color: MomentColors.secondaryText,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: _pickWorldClockDate,
                icon: const Icon(Lucide.Calendar, size: 15),
                label: const Text('手动设定'),
              ),
              OutlinedButton.icon(
                onPressed: () => _advanceWorldClock(const Duration(hours: 1)),
                icon: const Icon(Lucide.Timer, size: 15),
                label: const Text('+1 小时'),
              ),
              OutlinedButton.icon(
                onPressed: () => _advanceWorldClock(const Duration(hours: 6)),
                icon: const Icon(Lucide.Timer, size: 15),
                label: const Text('+6 小时'),
              ),
              OutlinedButton.icon(
                onPressed: () => _advanceWorldClock(const Duration(days: 1)),
                icon: const Icon(Lucide.Calendar, size: 15),
                label: const Text('+1 天'),
              ),
              OutlinedButton.icon(
                onPressed: () => _advanceWorldClock(const Duration(hours: -1)),
                icon: const Icon(Lucide.Timer, size: 15),
                label: const Text('-1 小时'),
              ),
              if (!following)
                OutlinedButton.icon(
                  onPressed: _followRealTime,
                  icon: const Icon(Lucide.RotateCcw, size: 15),
                  label: const Text('跟随真实时间'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          color: MomentColors.secondaryText,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _modeRow(String label, String scene) {
    final mode = _modes[scene] ?? SocialContextMode.full;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 15, color: MomentColors.primaryText)),
          ),
          SegmentedButton<SocialContextMode>(
            segments: const <ButtonSegment<SocialContextMode>>[
              ButtonSegment(value: SocialContextMode.full, label: Text('完整')),
              ButtonSegment(value: SocialContextMode.summary, label: Text('摘要')),
            ],
            selected: <SocialContextMode>{mode},
            onSelectionChanged: (set) => _setMode(scene, set.first),
          ),
        ],
      ),
    );
  }

  Widget _statLine(String label, int value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: MomentColors.primaryText,
                fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          Text(
            '约 ${formatTokenCount(value)} tokens',
            style: TextStyle(
              fontSize: 14,
              color: MomentColors.primaryText,
              fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _characterRow(String name, List<SocialTimeSlot> slots) {
    return Container(
      color: Colors.white,
      child: Column(
        children: <Widget>[
          ListTile(
            leading: CircleAvatar(
              radius: 16,
              child: Text(name.characters.isEmpty ? '?' : name.characters.first),
            ),
            title: Text(name, style: const TextStyle(fontSize: 15, color: MomentColors.primaryText)),
            subtitle: Text(
              slots.isEmpty
                  ? '没设作息：随时都可能有空'
                  : '${slots.length} 条作息',
              style: const TextStyle(fontSize: 12, color: MomentColors.secondaryText),
            ),
            trailing: IconButton(
              icon: const Icon(Lucide.Plus, size: 20, color: MomentColors.primaryText),
              tooltip: '加一条作息',
              onPressed: () => _editSlot(name, null),
            ),
            onTap: () => _openSlots(name, slots),
          ),
          const Divider(height: 0.5, thickness: 0.5),
        ],
      ),
    );
  }

  /// 展开某角色的所有作息规则，可逐条改/删。
  Future<void> _openSlots(String name, List<SocialTimeSlot> slots) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (sheetCtx) => Theme(
        data: momentLightTheme(),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '$name 的作息',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Lucide.Plus, size: 18),
                      label: const Text('添加'),
                      onPressed: () {
                        Navigator.of(sheetCtx).pop();
                        _editSlot(name, null);
                      },
                    ),
                  ],
                ),
              ),
              if (slots.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    '没设作息。这种情况下这个角色被当成随时都方便聊天。',
                    style: TextStyle(fontSize: 13, color: MomentColors.secondaryText),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: slots.length,
                    itemBuilder: (ctx, index) {
                      final slot = slots[index];
                      return ListTile(
                        title: Text(
                          '${_daysLabel(slot.days)} ${slot.startHour}:00–${slot.endHour}:00',
                          style: const TextStyle(fontSize: 14, color: MomentColors.primaryText),
                        ),
                        subtitle: Text(
                          '${slot.location.isEmpty ? '地点未写' : slot.location} · '
                          '${slot.activity.isEmpty ? '在做的事未写' : slot.activity} · '
                          '${slot.available ? '方便聊天' : '不方便聊天'}',
                          style: const TextStyle(fontSize: 12, color: MomentColors.secondaryText),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Lucide.Trash2, size: 18, color: Colors.redAccent),
                          onPressed: () async {
                            final next = List<SocialTimeSlot>.of(slots)
                              ..removeAt(index);
                            await _social.setSchedule(name, next);
                            _reload();
                            if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                          },
                        ),
                        onTap: () {
                          Navigator.of(sheetCtx).pop();
                          _editSlot(name, slot);
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _daysLabel(List<int> days) {
    if (days.length == 7) return '每天';
    const names = <int, String>{1: '一', 2: '二', 3: '三', 4: '四', 5: '五', 6: '六', 7: '日'};
    final set = days.toSet();
    if (set.containsAll(<int>{1, 2, 3, 4, 5}) && set.length == 5) return '工作日';
    if (set.containsAll(<int>{6, 7}) && set.length == 2) return '周末';
    return '周${days.map((d) => names[d]).join('、')}';
  }

  /// 新增/编辑一条作息。传 [existing] 为 null 表示新增。
  Future<void> _editSlot(String name, SocialTimeSlot? existing) async {
    final daysIndex = existing == null
        ? 0
        : existing.days.length == 7
            ? 0
            : existing.days.every((d) => d <= 5)
                ? 1
                : existing.days.every((d) => d >= 6)
                    ? 2
                    : 3;
    var choiceIndex = daysIndex;
    var selectedDays = _daysForChoice(choiceIndex);
    var start = existing?.startHour ?? 9;
    var end = existing?.endHour ?? 18;
    final locationCtrl = TextEditingController(text: existing?.location ?? '');
    final activityCtrl = TextEditingController(text: existing?.activity ?? '');
    var available = existing?.available ?? true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          title: Text(
            existing == null ? '加一条作息' : '改作息',
            style: const TextStyle(fontSize: 16),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('哪几天', style: TextStyle(fontSize: 13)),
                Wrap(
                  children: <Widget>[
                    for (var i = 0; i < 4; i++)
                      ChoiceChip(
                        label: Text(_dayChoiceLabel(i)),
                        selected: choiceIndex == i,
                        onSelected: (_) {
                          setDialogState(() {
                            choiceIndex = i;
                            selectedDays = _daysForChoice(i);
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('从 $start:00 到 $end:00'),
                Slider(
                  value: start.toDouble(),
                  min: 0,
                  max: 24,
                  divisions: 24,
                  label: '$start:00',
                  onChanged: (v) => setDialogState(() => start = v.round()),
                ),
                Slider(
                  value: end.toDouble(),
                  min: 0,
                  max: 24,
                  divisions: 24,
                  label: '$end:00',
                  onChanged: (v) => setDialogState(() => end = v.round()),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: locationCtrl,
                  decoration: const InputDecoration(
                    labelText: '在哪（例：公司 / 家里）',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: activityCtrl,
                  decoration: const InputDecoration(
                    labelText: '在做什么（例：上班 / 睡觉）',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('这时候方便聊天', style: TextStyle(fontSize: 14)),
                  value: available,
                  onChanged: (v) => setDialogState(() => available = v),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final slot = SocialTimeSlot(
      days: selectedDays,
      startHour: start,
      endHour: end,
      location: locationCtrl.text.trim(),
      activity: activityCtrl.text.trim(),
      available: available,
    );
    // 编辑是替换原位置，新增是追加。用对象身份 locating 不便，这里按内容近似匹配。
    final current = List<SocialTimeSlot>.of(_social.scheduleFor(name));
    if (existing != null) {
      var replaced = false;
      for (var i = 0; i < current.length; i++) {
        if (current[i].startHour == existing.startHour &&
            current[i].endHour == existing.endHour &&
            current[i].location == existing.location &&
            current[i].activity == existing.activity) {
          current[i] = slot;
          replaced = true;
          break;
        }
      }
      if (!replaced) current.add(slot);
    } else {
      current.add(slot);
    }
    await _social.setSchedule(name, current);
    _reload();
  }

  List<int> _daysForChoice(int choice) {
    switch (choice) {
      case 0:
        return List<int>.of(kSocialAllDays);
      case 1:
        return <int>[1, 2, 3, 4, 5];
      case 2:
        return <int>[6, 7];
      default:
        return <int>[1];
    }
  }

  String _dayChoiceLabel(int choice) {
    switch (choice) {
      case 0:
        return '每天';
      case 1:
        return '工作日';
      case 2:
        return '周末';
      default:
        return '周一';
    }
  }
}
