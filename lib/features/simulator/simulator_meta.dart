import '../../core/models/conversation.dart';

/// A simulation borrows the whole conversation pipeline: it is a plain
/// conversation carrying one flag in its extras bag. Nothing in storage,
/// backup, export or the send path knows it is anything else.
abstract final class SimulatorMeta {
  /// Marker in [Conversation.extras]. Only the list page and the composer read
  /// it; clearing it turns the record back into an ordinary conversation.
  static const String extrasKey = 'simulator';

  static bool isSimulator(Conversation? conversation) =>
      conversation != null && conversation.extras[extrasKey] == true;

  static Map<String, dynamic> mark(Map<String, dynamic> extras) =>
      <String, dynamic>{...extras, extrasKey: true};

  static Map<String, dynamic> unmark(Map<String, dynamic> extras) {
    final next = <String, dynamic>{...extras};
    next.remove(extrasKey);
    return next;
  }
}
