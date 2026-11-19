import 'dart:math';

import '../../core/models/conversation.dart';
import '../../core/services/chat/chat_service.dart';
import '../moment/moment_store.dart';
import 'wechat_models.dart';

bool isWechatConversation(Conversation conversation) =>
    conversation.extras[wechatHiddenKey] == true;

/// 微信数据的唯一出入口。
///
/// 全部塞在一条隐藏对话的 extras 里：
/// - wechat.groups   群的清单（含成员、世界书、间隔、模型绑定）
/// - wechat.messages 每个群一堆聊天记录，键是群 id
///
/// 之所以不塞进主对话的消息表：这一版先要能稳跑，不动核心模型。
/// 以后记录多了要提速，只改这个类，外面一律不用动。
class WechatStore {
  WechatStore(this.chat);

  final ChatService chat;

  final Random _random = Random();

  /// 找那条隐藏对话。跟朋友圈一样，会话列表里的是缓存对象，
  /// 写完要按 id 再取一次最新值，不然读到的是旧的。
  Conversation? findConversation() {
    for (final conversation in chat.getAllConversations()) {
      if (!isWechatConversation(conversation)) continue;
      return chat.getConversation(conversation.id) ?? conversation;
    }
    return null;
  }

  Future<String> ensureConversation() async {
    final existing = findConversation();
    if (existing != null) return existing.id;
    final created = await chat.createConversation(
      title: wechatContainerTitle,
      activate: false,
    );
    try {
      await chat.updateConversationExtras(created.id, (extras) {
        final next = Map<String, dynamic>.from(extras);
        next[wechatHiddenKey] = true;
        return next;
      });
    } catch (_) {
      // 标记没写进去也还能用，只是会话列表里会露出来一条。
    }
    return created.id;
  }

  Map<String, dynamic> _extras() {
    final conversation = findConversation();
    return conversation?.extras ?? const <String, dynamic>{};
  }

  // ---------------- 群 ----------------

  List<WechatGroup> groups() {
    final list = wechatGroupsFromExtras(_extras());
    final sorted = List<WechatGroup>.from(list)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted;
  }

  WechatGroup? group(String id) {
    for (final item in groups()) {
      if (item.id == id) return item;
    }
    return null;
  }

  Future<void> _writeGroups(List<WechatGroup> next) async {
    final id = await ensureConversation();
    await chat.updateConversationExtras(id, (extras) {
      final map = Map<String, dynamic>.from(extras);
      map[wechatGroupsKey] = next
          .map((g) => g.toJson())
          .toList(growable: false);
      return map;
    });
  }

  Future<WechatGroup> createGroup({
    required String name,
    List<WechatMember> members = const <WechatMember>[],
    List<String> bookIds = const <String>[],
    String persona = '',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    // 新群继承「微信设置 → 群聊默认间隔」，建好之后还能在群设置里单独改。
    final defaults = wechatSettings();
    final group = WechatGroup(
      id: '${now}_${_random.nextInt(99999)}',
      name: name.trim().isEmpty ? '新群聊' : name.trim(),
      members: members,
      bookIds: bookIds,
      persona: persona,
      intervalPreset: defaults.intervalPreset,
      customMinSeconds: defaults.customMinSeconds,
      customMaxSeconds: defaults.customMaxSeconds,
      createdAt: now,
    );
    final next = <WechatGroup>[...groups(), group];
    await _writeGroups(next);
    return group;
  }

  Future<void> saveGroup(WechatGroup group) async {
    final next = <WechatGroup>[
      for (final item in groups())
        if (item.id == group.id) group else item,
    ];
    await _writeGroups(next);
  }

  Future<void> deleteGroup(String groupId) async {
    final next = <WechatGroup>[
      for (final item in groups())
        if (item.id != groupId) item,
    ];
    final containerId = await ensureConversation();
    await chat.updateConversationExtras(containerId, (extras) {
      final map = Map<String, dynamic>.from(extras);
      map[wechatGroupsKey] = next
          .map((g) => g.toJson())
          .toList(growable: false);
      final messages = map[wechatMessagesKey];
      if (messages is Map) {
        final copy = Map<String, dynamic>.from(messages);
        copy.remove(groupId);
        map[wechatMessagesKey] = copy;
      }
      return map;
    });
  }

  // ---------------- 头像 ----------------

  /// 名字 → 头像路径。直接读朋友圈那份（`moment.assets`），
  /// 所以两边上传同一份文件，天然联动；朋友圈没传过的这里也没有。
  Map<String, String> avatarPaths() {
    final out = <String, String>{};
    try {
      final assets = MomentStore(chat).readAssets();
      for (final entry in assets.entries) {
        final avatar = (entry.value.avatar ?? '').trim();
        if (avatar.isNotEmpty) out[entry.key] = avatar;
      }
    } catch (_) {
      // 朋友圈那边还没建容器之类的，当作没有头像。
    }
    return out;
  }

  // ---------------- 微信全局设置 ----------------

  WechatSettings wechatSettings() => wechatSettingsFromExtras(_extras());

  Future<void> saveWechatSettings(WechatSettings next) async {
    final id = await ensureConversation();
    await chat.updateConversationExtras(id, (extras) {
      final map = Map<String, dynamic>.from(extras);
      map[wechatSettingsKey] = next.toJson();
      return map;
    });
  }

  /// 全局马甲改了，顺手同步进每个群（暂时只用一个名字，别的地方没法改群马甲）。
  Future<void> syncPersonaToGroups(String persona) async {
    final all = groups();
    if (all.isEmpty) return;
    var touched = false;
    final next = <WechatGroup>[];
    for (final group in all) {
      if (group.persona == persona) {
        next.add(group);
        continue;
      }
      touched = true;
      next.add(group.copyWith(persona: persona));
    }
    if (!touched) return;
    await _writeGroups(next);
  }

  // ---------------- 通讯录 ----------------

  /// 通讯录里的人，按添加时间倒序（新加的在上）。
  List<WechatContact> contacts() {
    final list = wechatContactsFromExtras(_extras());
    final sorted = List<WechatContact>.from(list)
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return sorted;
  }

  WechatContact? contact(String name) {
    final key = name.trim();
    for (final item in contacts()) {
      if (item.name == key) return item;
    }
    return null;
  }

  Future<void> _writeContacts(List<WechatContact> next) async {
    final id = await ensureConversation();
    await chat.updateConversationExtras(id, (extras) {
      final map = Map<String, dynamic>.from(extras);
      map[wechatContactsKey] = next
          .map((c) => c.toJson())
          .toList(growable: false);
      return map;
    });
  }

  /// 手动把人加进通讯录。已经在里面的跳过。
  Future<List<WechatContact>> addContacts(List<WechatContact> added) async {
    if (added.isEmpty) return contacts();
    final current = contacts();
    final existing = <String>{for (final c in current) c.name};
    final now = DateTime.now().millisecondsSinceEpoch;
    final fresh = <WechatContact>[
      for (final contact in added)
        if (existing.add(contact.name))
          contact.addedAt > 0
              ? contact
              : WechatContact(
                  name: contact.name,
                  entryId: contact.entryId,
                  bookId: contact.bookId,
                  providerKey: contact.providerKey,
                  modelId: contact.modelId,
                  addedAt: now,
                ),
    ];
    if (fresh.isEmpty) return current;
    final next = <WechatContact>[...current, ...fresh];
    await _writeContacts(next);
    return next;
  }

  Future<void> saveContact(WechatContact contact) async {
    final next = <WechatContact>[
      for (final item in contacts())
        if (item.name == contact.name) contact else item,
    ];
    await _writeContacts(next);
  }

  /// 从通讯录删人。同时把他从所有群里移出去（不然群里会有个幽灵成员），
  /// 每个群各留一条系统消息。私聊记录一起清掉。
  Future<void> removeContact(String name) async {
    final key = name.trim();
    if (key.isEmpty) return;
    final next = <WechatContact>[
      for (final item in contacts())
        if (item.name != key) item,
    ];
    await _writeContacts(next);

    for (final group in groups()) {
      final has = group.members.any((m) => m.name == key);
      if (has) {
        await removeMember(group, key);
      }
    }

    final containerId = await ensureConversation();
    await chat.updateConversationExtras(containerId, (extras) {
      final map = Map<String, dynamic>.from(extras);
      final messages = map[wechatMessagesKey];
      if (messages is Map) {
        final copy = Map<String, dynamic>.from(messages);
        copy.remove(wechatDmKey(key));
        map[wechatMessagesKey] = copy;
      }
      return map;
    });
  }

  /// 老数据迁移：以前只有群成员，没有通讯录。
  ///
  /// 把每个群里的成员补进通讯录，不然改造后群会变成空壳；
  /// 已有的同名条目不覆盖（保留用户可能已经绑过的模型）。
  Future<void> ensureMigrated() async {
    final allGroups = groups();
    if (allGroups.isEmpty) return;
    final current = contacts();
    final existing = <String>{for (final c in current) c.name};
    final missing = <WechatContact>[];
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final group in allGroups) {
      for (final member in group.members) {
        if (member.name.trim().isEmpty) continue;
        if (!existing.add(member.name)) continue;
        missing.add(
          WechatContact(
            name: member.name,
            entryId: member.entryId,
            bookId: member.bookId,
            providerKey: member.providerKey,
            modelId: member.modelId,
            addedAt: now,
          ),
        );
      }
    }
    if (missing.isEmpty) return;
    await _writeContacts(<WechatContact>[...current, ...missing]);
  }

  // ---------------- 私聊 ----------------

  /// 私聊的记录键。
  static String dmKey(String name) => wechatDmKey(name);

  List<WechatMessage> dmMessages(String name) => messages(wechatDmKey(name));

  Future<WechatMessage> appendDmMessage(
    String name, {
    required String text,
    required bool mine,
    String? sender,
  }) => appendMessage(
    wechatDmKey(name),
    sender: sender ?? name,
    text: text,
    mine: mine,
  );

  // ---------------- 未读 ----------------

  /// 每个会话读到哪了（毫秒）。键跟消息键一致：群 id 或 `dm:名字`。
  Map<String, int> _reads() {
    final raw = _extras()[wechatReadsKey];
    if (raw is! Map) return <String, int>{};
    final out = <String, int>{};
    for (final entry in raw.entries) {
      final value = entry.value;
      if (value is int) {
        out[entry.key.toString()] = value;
      } else if (value is num) {
        out[entry.key.toString()] = value.toInt();
      }
    }
    return out;
  }

  /// 某个会话有几条没读。算的是「别人发的、比我上次读的时间新」的条数。
  int unreadOf(String key) {
    final since = _reads()[key] ?? 0;
    var count = 0;
    for (final message in messages(key)) {
      if (message.mine) continue;
      if (message.system) continue;
      if (message.at > since) count++;
    }
    return count;
  }

  /// 进过某个会话就把它标成已读。
  Future<void> markRead(String key) async {
    final all = messages(key);
    if (all.isEmpty) return;
    final latest = all.last.at;
    final current = _reads();
    if ((current[key] ?? 0) >= latest) return;
    final id = await ensureConversation();
    await chat.updateConversationExtras(id, (extras) {
      final map = Map<String, dynamic>.from(extras);
      final reads = <String, dynamic>{};
      final raw = map[wechatReadsKey];
      if (raw is Map) {
        for (final entry in raw.entries) {
          reads[entry.key.toString()] = entry.value;
        }
      }
      reads[key] = latest;
      map[wechatReadsKey] = reads;
      return map;
    });
  }

  /// 所有私聊的键（有记录的那些人）。
  List<String> dmKeysWithMessages() {
    final all = _extras()[wechatMessagesKey];
    if (all is! Map) return const <String>[];
    const prefix = 'dm:';
    final out = <String>[];
    for (final key in all.keys) {
      final text = key.toString();
      if (!text.startsWith(prefix)) continue;
      final name = text.substring(prefix.length);
      if (name.trim().isEmpty) continue;
      final list = all[key];
      if (list is List && list.isNotEmpty) out.add(text);
    }
    return out;
  }

  // ---------------- 消息 ----------------

  List<WechatMessage> messages(String groupId) =>
      wechatMessagesFromExtras(_extras(), groupId);

  Future<void> _writeMessages(String groupId, List<WechatMessage> next) async {
    final containerId = await ensureConversation();
    await chat.updateConversationExtras(containerId, (extras) {
      final map = Map<String, dynamic>.from(extras);
      final all = map[wechatMessagesKey];
      final copy = all is Map
          ? Map<String, dynamic>.from(all)
          : <String, dynamic>{};
      copy[groupId] = next.map((m) => m.toJson()).toList(growable: false);
      map[wechatMessagesKey] = copy;
      return map;
    });
  }

  String _newMessageId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(9999)}';

  /// 追加一条消息。传 [extra] 里的是已经定好的字段。
  Future<WechatMessage> appendMessage(
    String groupId, {
    required String sender,
    required String text,
    bool system = false,
    bool mine = false,
    bool divine = false,
  }) async {
    final message = WechatMessage(
      id: _newMessageId(),
      sender: sender,
      text: text,
      at: DateTime.now().millisecondsSinceEpoch,
      system: system,
      mine: mine,
      divine: divine,
    );
    final next = <WechatMessage>[...messages(groupId), message];
    await _writeMessages(groupId, next);
    return message;
  }

  /// 拉人进群，同时留一条系统消息——角色看得见，能顺着这事聊。
  Future<WechatGroup> addMembers(
    WechatGroup group,
    List<WechatMember> added,
  ) async {
    if (added.isEmpty) return group;
    final existing = <String>{for (final m in group.members) m.name};
    final fresh = <WechatMember>[
      for (final member in added)
        if (!existing.contains(member.name)) member,
    ];
    if (fresh.isEmpty) return group;
    final next = group.copyWith(
      members: <WechatMember>[...group.members, ...fresh],
    );
    await saveGroup(next);
    final names = fresh.map((m) => m.name).join('、');
    await appendMessage(
      group.id,
      sender: '',
      text: '${group.effectivePersona} 邀请 $names 加入了群聊',
      system: true,
    );
    return next;
  }

  /// 踢人。系统消息同样会进上下文。
  Future<WechatGroup> removeMember(WechatGroup group, String name) async {
    final next = group.copyWith(
      members: <WechatMember>[
        for (final member in group.members)
          if (member.name != name) member,
      ],
      divine: group.divine == name ? '' : group.divine,
    );
    await saveGroup(next);
    await appendMessage(
      group.id,
      sender: '',
      text: '$name 被移出了群聊',
      system: true,
    );
    return next;
  }

  /// 建群时也留一条开场系统消息。
  Future<void> markGroupCreated(WechatGroup group) async {
    final names = group.members.map((m) => m.name).join('、');
    await appendMessage(
      group.id,
      sender: '',
      text: names.isEmpty
          ? '${group.effectivePersona} 创建了群聊「${group.name}」'
          : '${group.effectivePersona} 创建了群聊「${group.name}」，并邀请 $names 加入',
      system: true,
    );
  }
}

/// 群里最近 N 条记录，按时间正序，拿去当上下文。
List<WechatMessage> wechatRecentContext(
  List<WechatMessage> all, {
  int limit = 60,
}) {
  if (all.length <= limit) return all;
  return all.sublist(all.length - limit);
}
