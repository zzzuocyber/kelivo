import 'dart:async';

enum DesktopSettingsNavigationTarget {
  backup,
  mcp,
  topicPosition,
  providers,
  fal,
  creationPreferences,
}

class DesktopSettingsNavigationBus {
  DesktopSettingsNavigationBus._();

  static final DesktopSettingsNavigationBus instance =
      DesktopSettingsNavigationBus._();

  final StreamController<DesktopSettingsNavigationTarget> _controller =
      StreamController<DesktopSettingsNavigationTarget>.broadcast();

  Stream<DesktopSettingsNavigationTarget> get stream => _controller.stream;

  bool _topicPositionRequested = false;

  bool consumeTopicPositionRequest() {
    final requested = _topicPositionRequested;
    _topicPositionRequested = false;
    return requested;
  }

  void openTopicPosition() {
    _topicPositionRequested = true;
    _controller.add(DesktopSettingsNavigationTarget.topicPosition);
  }

  void openTopicPosition() =>
      _open(DesktopSettingsNavigationTarget.topicPosition);
  void openBackup() => _open(DesktopSettingsNavigationTarget.backup);
  void openMcp() => _open(DesktopSettingsNavigationTarget.mcp);
  void openProviders() => _open(DesktopSettingsNavigationTarget.providers);
  void openFal() => _open(DesktopSettingsNavigationTarget.fal);
  void openCreationPreferences() =>
      _open(DesktopSettingsNavigationTarget.creationPreferences);
}
