import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../icons/lucide_adapter.dart';
import 'moment_models.dart';

/// 朋友圈固定浅色，不跟夜间模式走，所以颜色都写死在这里。
class MomentColors {
  const MomentColors._();

  static const Color background = Color(0xFFF4F5F7);
  static const Color card = Colors.white;
  static const Color primaryText = Color(0xFF1B1C1E);
  static const Color secondaryText = Color(0xFF8B9099);
  static const Color name = Color(0xFF3B5A8C);
  static const Color commentBlock = Color(0xFFF6F7F9);
  static const Color hairline = Color(0xFFE8EAEE);
}

/// 朋友圈一律浅色，进来就把主题换掉，不看夜间模式。
ThemeData momentLightTheme() {
  return ThemeData(
    brightness: Brightness.light,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF3B5A8C),
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: MomentColors.background,
    canvasColor: MomentColors.card,
    appBarTheme: const AppBarTheme(
      backgroundColor: MomentColors.card,
      foregroundColor: MomentColors.primaryText,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    dividerTheme: const DividerThemeData(color: MomentColors.hairline),
  );
}

/// 头像先不做上传：圆形，取角色名的第一个字。
class MomentAvatar extends StatelessWidget {
  const MomentAvatar({super.key, required this.name, this.size = 42});

  final String name;
  final double size;

  static const List<Color> _palette = <Color>[
    Color(0xFFDCE6F7),
    Color(0xFFF6E2DC),
    Color(0xFFE2EDE3),
    Color(0xFFEDE2F4),
    Color(0xFFF4EDDC),
    Color(0xFFDCEAEE),
  ];

  static const List<Color> _ink = <Color>[
    Color(0xFF3C5A88),
    Color(0xFF8A5340),
    Color(0xFF3F6B4A),
    Color(0xFF6A4A86),
    Color(0xFF7A6228),
    Color(0xFF35616B),
  ];

  static String initialOf(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    var hash = 0;
    for (final unit in trimmed.codeUnits) {
      hash = (hash + unit) % 9973;
    }
    final index = hash % _palette.length;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: _palette[index], shape: BoxShape.circle),
      child: Text(
        initialOf(trimmed),
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w600,
          color: _ink[index],
        ),
      ),
    );
  }
}

/// 帖子里本该放图的空位。生图接口还没接，先放一张本地 SVG 占位。
const String _momentPlaceholderSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="900" height="675" viewBox="0 0 900 675">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#EDF1F7"/>
      <stop offset="1" stop-color="#D9E1EE"/>
    </linearGradient>
  </defs>
  <rect width="900" height="675" fill="url(#bg)"/>
  <circle cx="660" cy="180" r="72" fill="#F7F9FC"/>
  <path d="M0 675 L250 400 L420 560 L560 430 L900 675 Z" fill="#C6D2E4"/>
  <path d="M0 675 L180 520 L330 620 L470 520 L620 620 L900 500 L900 675 Z" fill="#B3C1D6"/>
</svg>
''';

class MomentPlaceholderImage extends StatelessWidget {
  const MomentPlaceholderImage({super.key});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SvgPicture.string(_momentPlaceholderSvg, fit: BoxFit.cover),
      ),
    );
  }
}

String momentRelativeTime(DateTime time) {
  final now = DateTime.now();
  final diff = now.difference(time);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
  if (diff.inHours < 24) return '${diff.inHours}小时前';
  if (diff.inDays < 30) return '${diff.inDays}天前';
  return '${time.year}-${time.month.toString().padLeft(2, '0')}-'
      '${time.day.toString().padLeft(2, '0')}';
}

class MomentPostCard extends StatelessWidget {
  const MomentPostCard({super.key, required this.post});

  final MomentPost post;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: MomentColors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          MomentAvatar(name: post.author, size: 42),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  post.author,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: MomentColors.name,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  post.text,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.45,
                    color: MomentColors.primaryText,
                  ),
                ),
                if (post.hasImage) ...<Widget>[
                  const SizedBox(height: 10),
                  const MomentPlaceholderImage(),
                ],
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Text(
                      momentRelativeTime(post.createdAt),
                      style: const TextStyle(
                        fontSize: 12,
                        color: MomentColors.secondaryText,
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Lucide.Heart,
                      size: 16,
                      color: MomentColors.secondaryText,
                    ),
                    if (post.likes.isNotEmpty) ...<Widget>[
                      const SizedBox(width: 4),
                      Text(
                        '${post.likes.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: MomentColors.secondaryText,
                        ),
                      ),
                    ],
                    const SizedBox(width: 16),
                    const Icon(
                      Lucide.MessageCircle,
                      size: 16,
                      color: MomentColors.secondaryText,
                    ),
                    if (post.comments.isNotEmpty) ...<Widget>[
                      const SizedBox(width: 4),
                      Text(
                        '${post.comments.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: MomentColors.secondaryText,
                        ),
                      ),
                    ],
                  ],
                ),
                if (post.likes.isNotEmpty || post.comments.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    decoration: BoxDecoration(
                      color: MomentColors.commentBlock,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (post.likes.isNotEmpty) ...<Widget>[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Icon(
                                  Lucide.Heart,
                                  size: 13,
                                  color: MomentColors.name,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  post.likes.join('、'),
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    height: 1.35,
                                    color: MomentColors.name,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (post.comments.isNotEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: Divider(
                                height: 1,
                                thickness: 1,
                                color: MomentColors.hairline,
                              ),
                            ),
                        ],
                        for (final comment in post.comments)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  height: 1.4,
                                  color: MomentColors.primaryText,
                                ),
                                children: <InlineSpan>[
                                  TextSpan(
                                    text: '${comment.author}：',
                                    style: const TextStyle(
                                      color: MomentColors.name,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  TextSpan(text: comment.text),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
