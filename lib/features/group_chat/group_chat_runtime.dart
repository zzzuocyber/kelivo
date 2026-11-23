/// 群聊运行时状态（内存级，随 app 进程存活）。
///
/// 每个对话同时最多一场接力。暂停 = 软停止：当前正在生成的那条让它
/// 自然说完（一次性调用，不会出半截话），下一轮开始不再发起调用。
class GroupChatRuntime {
  GroupChatRuntime._();

  static final Set<String> _active = <String>{};
  static final Set<String> _paused = <String>{};

  static bool isActive(String conversationId) => _active.contains(conversationId);

  static bool isPaused(String conversationId) => _paused.contains(conversationId);

  static void markActive(String conversationId) {
    _active.add(conversationId);
    _paused.remove(conversationId);
  }

  static void pause(String conversationId) {
    _paused.add(conversationId);
  }

  static void resume(String conversationId) {
    _paused.remove(conversationId);
  }

  static void markFinished(String conversationId) {
    _active.remove(conversationId);
    _paused.remove(conversationId);
  }
}
