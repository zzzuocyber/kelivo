import '../../models/conversation.dart';
import 'chat_service.dart';

/// 小手机的三块数据（微信 / 朋友圈 / 社交状态）都各自挂在一个隐藏 conversation
/// 的 extras 里，它们不是真正的聊天，绝不能出现在主页会话列表、历史列表、
/// 启动恢复、跳转候选、全局搜索这些「给用户看的会话列表」里。
///
/// 这段判断之所以收在 core 层：以前每个列表页各写各的，侧边栏只过滤了
/// moment + wechat，漏掉 social，于是「社交状态」这条就露在了主页——这个坑
/// 出现过好几次。以后**新增任何会话列表，一律用 [visibleConversations]**，
/// 不要再手写 `!isXxxConversation`，避免再漏。
///
/// 注意：store 自己的 findConversation() 与备份导出仍要用 getAllConversations()，
/// 它们本来就找这些隐藏容器，不能走这里。
bool isPhoneHiddenConversation(Conversation conversation) {
  final extras = conversation.extras;
  return extras['wechat.hidden'] == true ||
      extras['moment.hidden'] == true ||
      extras['social.hidden'] == true;
}

/// 过滤掉小手机隐藏容器后的会话列表，按更新时间倒序（同 getAllConversations）。
List<Conversation> visibleConversations(ChatService chat) =>
    chat.getAllConversations()
        .where((conversation) => !isPhoneHiddenConversation(conversation))
        .toList(growable: false);
