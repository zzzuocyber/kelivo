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
  ///
  /// 兜底：标记有可能没写进去（`updateConversationExtras` 抛异常被吞了）。
  /// 那种情况下按「extras 里有没有微信自己的数据键」认人——用户的普通对话
  /// 不会带 `wechat.groups` 这种键，所以不会认错。
  Conversation? findConversation() {
    final all = chat.getAllConversations();
    for (final conversation in all) {
      if (!isWechatConversation(conversation)) continue;
      return chat.getConversation(conversation.id) ?? conversation;
    }
    for (final conversation in all) {
      final extras = conversation.extras;
      final looksLikeOurs =
          extras.containsKey(wechatGroupsKey) ||
          extras.containsKey(wechatMessagesKey) ||
          extras.containsKey(wechatSettingsKey) ||
          extras.containsKey(wechatContactsKey) ||
          extras.containsKey(wechatReadsKey);
      if (!looksLikeOurs) continue;
      return chat.getConversation(conversation.id) ?? conversation;
    }
    return null;
  }

  Future<String> ensureConversation() async {
    final existing = findConversation();
    if (existing != null) {
      // 认下来了但标记还缺（老数据），补一次，免得它一直露在会话列表里。
      if (!isWechatConversation(existing)) {
        try {
          await chat.updateConversationExtras(existing.id, (extras) {
            final next = Map<String, dynamic>.from(extras);
            next[wechatHiddenKey] = true;
            return next;
          });
        } catch (_) {
          // 补不上也还能用，只是列表里会露出来。
        }
      }
      return existing.id;
    }
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
    String owner = '',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    // 新群默认「跟随全局」：以后在设置里改全局间隔，没单独设过的群会跟着变。
    final group = WechatGroup(
      id: '${now}_${_random.nextInt(99999)}',
      name: name.trim().isEmpty ? '新群聊' : name.trim(),
      members: members,
      bookIds: bookIds,
      persona: persona,
      owner: owner,
      intervalPreset: WechatIntervalPreset.follow,
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
  ///
  /// 我自己的那张存在 `@me` 底下，这里顺手按马甲名再挂一份，
  /// 免得每个调用点都要记住「我的头像不是按名字存的」。
  Map<String, String> avatarPaths() {
    final out = <String, String>{};
    String? mine;
    try {
      final assets = MomentStore(chat).readAssets();
      for (final entry in assets.entries) {
        final avatar = (entry.value.avatar ?? '').trim();
        if (avatar.isEmpty) continue;
        out[entry.key] = avatar;
        if (entry.key == '@me') mine = avatar;
      }
    } catch (_) {
      // 朋友圈那边还没建容器之类的，当作没有头像。
    }
    if (mine != null) {
      final persona = wechatSettings().effectivePersona;
      out.putIfAbsent(persona, () => mine!);
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
    bool divine = false,
    bool withImage = false,
    bool plot = false,
    int? at,
  }) => appendMessage(
    wechatDmKey(name),
    sender: plot ? '' : (sender ?? name),
    text: text,
    mine: mine,
    divine: divine,
    withImage: withImage,
    plot: plot,
    at: at,
  );

  /// 删掉跟某个人的私聊记录（通讯录里那人还在）。
  Future<void> deleteDm(String name) async {
    final key = wechatDmKey(name);
    final id = await ensureConversation();
    await chat.updateConversationExtras(id, (extras) {
      final map = Map<String, dynamic>.from(extras);
      final all = map[wechatMessagesKey];
      if (all is Map) {
        map[wechatMessagesKey] = Map<String, dynamic>.from(all)..remove(key);
      }
      final reads = map[wechatReadsKey];
      if (reads is Map) {
        map[wechatReadsKey] = Map<String, dynamic>.from(reads)..remove(key);
      }
      return map;
    });
  }

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

  /// 把一个会话标成「有未读」：把已读游标拨到最后一条消息之前。
  /// 离线补算的消息时间戳在过去，正常 markRead 会把它们当成老的、不冒红点，
  /// 所以补完要主动把游标拨回去，让用户一进来看见红点。
  Future<void> markUnread(String key) async {
    final all = messages(key);
    if (all.isEmpty) return;
    final latest = all.last.at;
    final current = _reads();
    final before = latest - 1;
    if ((current[key] ?? 0) >= before) {
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
        reads[key] = before;
        map[wechatReadsKey] = reads;
        return map;
      });
    }
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

  /// 只清一个会话的聊天记录，群/人/设置都留着。
  /// 私聊也能用（键是 `dm:名字`），未读一起清掉。
  Future<void> clearMessages(String key) async {
    final id = await ensureConversation();
    await chat.updateConversationExtras(id, (extras) {
      final map = Map<String, dynamic>.from(extras);
      final all = map[wechatMessagesKey];
      if (all is Map) {
        final copy = Map<String, dynamic>.from(all)..remove(key);
        map[wechatMessagesKey] = copy;
      }
      final reads = map[wechatReadsKey];
      if (reads is Map) {
        final copy = Map<String, dynamic>.from(reads)..remove(key);
        map[wechatReadsKey] = copy;
      }
      return map;
    });
  }

  List<WechatMessage> messages(String groupId) =>
      wechatMessagesFromExtras(_extras(), groupId);

  /// 跨场景记忆：扫所有会话（群 + 所有私聊），挑出 [name] 说过的话，
  /// 跳过 [excludeKey] 这个当前会话，避免把自己刚说的重复喂进去。
  ///
  /// 返回 `场景 · 内容` 的行，给社交上下文构建器用。
  List<String> memoryLinesFor(String name, {String excludeKey = '', int limit = 40}) {
    final extras = _extras();
    final raw = extras[wechatMessagesKey];
    final out = <String>[];
    if (raw is! Map) return out;
    final myName = wechatSettings().effectivePersona;
    for (final entry in raw.entries) {
      final key = entry.key.toString();
      if (key == excludeKey) continue;
      final scene = key.startsWith('dm:') ? '私聊' : '群里';
      final list = wechatMessagesFromExtras(<String, dynamic>{
        wechatMessagesKey: <String, dynamic>{key: entry.value},
      }, key);
      for (final message in list) {
        if (message.system || message.text.trim().isEmpty) continue;
        final isMine = message.mine && !message.divine;
        final speaker = isMine ? myName : message.sender.trim();
        // 群里认发送者；私聊里认对方（键名）。
        final dmPartner = key.startsWith('dm:') ? key.substring(3) : '';
        final matches = speaker == name || dmPartner == name && !isMine;
        if (!matches) continue;
        out.add('$scene：${message.text}');
        if (out.length >= limit) return out;
      }
    }
    return out;
  }

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

  /// 追加一条消息。
  /// [at] 默认当下；离线补算会传一段过去的时间，让消息看着像离开时真发过。
  Future<WechatMessage> appendMessage(
    String groupId, {
    required String sender,
    required String text,
    bool system = false,
    bool mine = false,
    bool divine = false,
    bool withImage = false,
    bool plot = false,
    int? at,
  }) async {
    final message = WechatMessage(
      id: _newMessageId(),
      sender: sender,
      text: text,
      at: at ?? DateTime.now().millisecondsSinceEpoch,
      system: system,
      mine: mine,
      divine: divine,
      withImage: withImage,
      plot: plot,
    );
    final next = <WechatMessage>[...messages(groupId), message];
    await _writeMessages(groupId, next);
    return message;
  }

  /// 改一条消息的正文。只有自己发的才允许改，判断放在界面层。
  Future<void> editMessage(
    String key,
    String id,
    String text, {
    bool? withImage,
  }) async {
    final list = messages(key);
    var changed = false;
    final next = <WechatMessage>[];
    for (final message in list) {
      if (message.id == id) {
        next.add(message.copyWith(text: text, withImage: withImage));
        changed = true;
      } else {
        next.add(message);
      }
    }
    if (!changed) return;
    await _writeMessages(key, next);
  }

  /// 撤回：正文**清空**（原文一个字都不留），只留个标记，界面渲染成一句灰字。
  ///
  /// 清空是有意的——撤回的话不该再被喂进上下文，也不该能被翻出来。
  Future<void> recallMessage(String key, String id) async {
    final list = messages(key);
    var changed = false;
    final next = <WechatMessage>[];
    for (final message in list) {
      if (message.id == id && !message.recalled) {
        next.add(message.copyWith(text: '', recalled: true));
        changed = true;
      } else {
        next.add(message);
      }
    }
    if (!changed) return;
    await _writeMessages(key, next);
  }

  /// 彻底删掉一条，不留灰字。
  Future<void> deleteMessage(String key, String id) async {
    final list = messages(key);
    final next = <WechatMessage>[
      for (final message in list)
        if (message.id != id) message,
    ];
    if (next.length == list.length) return;
    await _writeMessages(key, next);
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
    // 名义上以群主夺舍操作：建群时指定了群主就用他的名字，否则还是我。
    await appendMessage(
      group.id,
      sender: '',
      text: '${group.effectiveOwner} 邀请 $names 加入了群聊',
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
      text: '$name 被 ${group.effectiveOwner} 移出了群聊',
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
  // 撤回的那条正文已经清空了：原文绝不进上下文，
  // 只换成一句系统提示，让角色知道"刚才有句话被收回了"，别当他没说过。
  final usable = <WechatMessage>[
    for (final message in all)
      if (message.recalled)
        WechatMessage(
          id: message.id,
          sender: '',
          text:
              '${message.mine && !message.divine ? '我' : message.sender}撤回了一条消息',
          at: message.at,
          system: true,
        )
      else
        message,
  ];
  if (usable.length <= limit) return usable;
  return usable.sublist(usable.length - limit);
}
