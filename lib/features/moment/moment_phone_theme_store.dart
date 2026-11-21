import '../../core/services/chat/chat_service.dart';
import 'moment_store.dart';

/// 小手机桌面的主题设置。
///
/// 跟朋友圈、微信一样挂在隐藏对话的 extras 里：这样壁纸路径会被存储页
/// 归进「小手机」分类（键带 moment. 前缀），备份/导出/恢复也自动跟着走，
/// 不用动数据库结构。
const String phoneThemeWallpaperKey = 'moment.phone.wallpaper';
const String phoneThemeModeKey = 'moment.phone.theme';
const String phoneThemeDimKey = 'moment.phone.wallpaper.dim';

/// true = 深色（默认），false = 浅色。不跟随系统。
const bool _defaultDark = true;

/// 默认压暗 45%，上限 80%（再黑就没壁纸的意思了）。
const double defaultPhoneWallpaperDim = 0.45;
const double maxPhoneWallpaperDim = 0.8;

class PhoneTheme {
  const PhoneTheme({
    required this.wallpaperPath,
    required this.dark,
    required this.dim,
  });

  final String wallpaperPath;
  final bool dark;
  final double dim;

  static PhoneTheme fromExtras(Map<String, dynamic>? extras) {
    final rawPath = (extras?[phoneThemeWallpaperKey] ?? '').toString();
    final rawMode = extras?[phoneThemeModeKey];
    final rawDim = extras?[phoneThemeDimKey];
    return PhoneTheme(
      wallpaperPath: rawPath.trim(),
      dark: rawMode is bool ? rawMode : _defaultDark,
      dim: rawDim is num
          ? rawDim.toDouble().clamp(0.0, maxPhoneWallpaperDim)
          : defaultPhoneWallpaperDim,
    );
  }
}

/// 小手机主题读写入口，跟 MomentStore 共用同一条隐藏对话。
class PhoneThemeStore {
  PhoneThemeStore(this.chat);

  final ChatService chat;
  final MomentStore _moment = MomentStore(chat);

  PhoneTheme read() => PhoneTheme.fromExtras(_moment.findConversation()?.extras);

  Future<void> setWallpaper(String path) => _write((next) {
        next[phoneThemeWallpaperKey] = path;
      });

  Future<void> clearWallpaper() => _write((next) {
        next.remove(phoneThemeWallpaperKey);
      });

  Future<void> setDark(bool dark) => _write((next) {
        next[phoneThemeModeKey] = dark;
      });

  Future<void> setDim(double dim) => _write((next) {
        next[phoneThemeDimKey] = dim.clamp(0.0, maxPhoneWallpaperDim);
      });

  Future<void> _write(void Function(Map<String, dynamic> next) mutate) async {
    final id = await _moment.ensureConversation();
    await chat.updateConversationExtras(id, (extras) {
      final next = Map<String, dynamic>.from(extras);
      mutate(next);
      return next;
    });
  }
}
