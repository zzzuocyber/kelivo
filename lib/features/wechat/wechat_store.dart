import 'dart:math';

import '../../core/models/conversation.dart';
import '../../core/services/chat/chat_service.dart';
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
    final group = WechatGroup(
      id: '${now}_${_random.nextInt(99999)}',
      name: name.trim().isEmpty ? '新群聊' : name.trim(),
      members: members,
      bookIds: bookIds,
      persona: persona,
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
