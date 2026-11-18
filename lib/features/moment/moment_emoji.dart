import 'package:flutter/material.dart';

import 'moment_models.dart';
import 'moment_widgets.dart';

/// 配图：不用画，直接把 emoji 摆进画布。
///
/// 规则很简单：正文里命中的词换成对应 emoji，一个大的在中间，
/// 最多两个小的错落放；一个都没命中就从常用池里按帖子 id 取，
/// 所以同一条帖子的图永远是同一张。
const Map<String, String> momentEmojiTable = <String, String>{
  // 吃
  '烧烤': '🍢',
  '烤串': '🍢',
  '火锅': '🍲',
  '面条': '🍜',
  '拉面': '🍜',
  '泡面': '🍜',
  '加面': '🍜',
  '米饭': '🍚',
  '外卖': '🥡',
  '便当': '🍱',
  '早饭': '🥐',
  '早餐': '🥐',
  '饺子': '🥟',
  '包子': '🥟',
  '馒头': '🍞',
  '面包': '🍞',
  '鸡蛋': '🥚',
  '土豆': '🥔',
  '葱': '🌿',
  '蔬菜': '🥬',
  '水果': '🍎',
  '苹果': '🍎',
  '香蕉': '🍌',
  '西瓜': '🍉',
  '橘子': '🍊',
  '蛋糕': '🍰',
  '冰棍': '🍦',
  '雪糕': '🍦',
  '奶茶': '🧋',
  '咖啡': '☕',
  '啤酒': '🍺',
  '酒': '🍶',
  '茶': '🍵',
  '牛奶': '🥛',
  '糖': '🍬',
  '辣': '🌶️',
  // 天气、时间
  '下雨': '🌧️',
  '雨': '🌧️',
  '雪': '❄️',
  '晴': '☀️',
  '太阳': '☀️',
  '晒': '☀️',
  '风': '🌬️',
  '台风': '🌪️',
  '云': '☁️',
  '雷': '⛈️',
  '热': '🥵',
  '冷': '🥶',
  '晚上': '🌙',
  '夜': '🌙',
  '早上': '🌅',
  '月': '🌙',
  // 物件
  '灯': '💡',
  '风扇': '🌀',
  '空调': '❄️',
  '手机': '📱',
  '耳机': '🎧',
  '电视': '📺',
  '书': '📖',
  '鞋': '👞',
  '皮鞋': '👞',
  '伞': '☂️',
  '包': '👜',
  '钱包': '👛',
  '钥匙': '🔑',
  '快递': '📦',
  '床': '🛏️',
  '椅子': '🪑',
  '衣服': '👕',
  '帽子': '🧢',
  '眼镜': '👓',
  '相机': '📷',
  '信': '✉️',
  '笔': '✒️',
  '纸': '📄',
  // 场景、交通
  '超市': '🛒',
  '市场': '🏪',
  '菜市场': '🏪',
  '家': '🏠',
  '回家': '🏠',
  '街': '🛣️',
  '路上': '🛣️',
  '公司': '🏢',
  '办公室': '🏢',
  '上班': '🏢',
  '下班': '🌆',
  '学校': '🏫',
  '医院': '🏥',
  '公园': '🌳',
  '车站': '🚉',
  '地铁': '🚇',
  '公交': '🚌',
  '车': '🚗',
  '自行车': '🚲',
  '飞机': '✈️',
  '医院挂号': '🏥',
  // 动物、人
  '猫': '🐱',
  '狗': '🐶',
  '鸟': '🐦',
  '鱼': '🐟',
  '蚊子': '🦟',
  '孩子': '🧒',
  '老板': '🧑',
  '朋友': '🧑',
  // 抽象
  '钱': '💰',
  '涨价': '📈',
  '便宜': '🏷️',
  '穷': '💸',
  '累': '😩',
  '困': '😴',
  '笑': '😄',
  '哭': '😢',
  '生气': '😠',
  '烦': '😑',
  '无聊': '😑',
  '音乐': '🎵',
  '电影': '🎬',
  '游戏': '🎮',
  '照片': '🖼️',
  '生日': '🎂',
  '礼物': '🎁',
};

/// 没命中任何词时用的池子，风格日常、好认。
const List<String> _momentEmojiPool = <String>[
  '🌿',
  '🍃',
  '🌤️',
  '🌙',
  '✨',
  '🎈',
  '🧸',
  '🪴',
  '📷',
  '🎧',
  '🍀',
  '🕯️',
  '🧵',
  '🪁',
  '🍋',
  '🌰',
  '🐚',
  '🪶',
  '🌾',
  '☕',
];

/// 按正文和帖子 id 生成 1~3 个 emoji。同样的输入永远同样的输出。
List<String> momentEmojisFor(String text, String seed) {
  final picked = <String>[];
  final body = text.replaceAll(RegExp(r'\s+'), '');
  // 长的词优先，避免「雨」把「下雨」抢了。
  final keys = momentEmojiTable.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final key in keys) {
    if (!body.contains(key)) continue;
    final emoji = momentEmojiTable[key]!;
    if (picked.contains(emoji)) continue;
    picked.add(emoji);
    if (picked.length >= 3) break;
  }
  if (picked.isEmpty) {
    final hash = _seedOf(seed);
    for (var i = 0; i < 3; i++) {
      final emoji = _momentEmojiPool[(hash + i * 7) % _momentEmojiPool.length];
      if (!picked.contains(emoji)) picked.add(emoji);
    }
  }
  return picked;
}

int _seedOf(String seed) {
  var hash = 0;
  for (final unit in seed.codeUnits) {
    hash = (hash * 31 + unit) % 99991;
  }
  return hash;
}

/// 帖子配图。纯 emoji，白底，最多三个，位置按帖子 id 定死。
class MomentEmojiImage extends StatelessWidget {
  const MomentEmojiImage({super.key, required this.post});

  final MomentPost post;

  @override
  Widget build(BuildContext context) {
    final emojis = momentEmojisFor(post.text, post.id);
    final hash = _seedOf(post.id);
    final main = emojis.isEmpty ? '🌿' : emojis[0];
    final second = emojis.length > 1 ? emojis[1] : null;
    final third = emojis.length > 2 ? emojis[2] : null;
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: MomentColors.hairline),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            children: <Widget>[
              Align(
                alignment: const Alignment(0, 0.18),
                child: Text(
                  main,
                  style: const TextStyle(fontSize: 96, height: 1.1),
                ),
              ),
              if (second != null)
                Align(
                  alignment: const Alignment(0.62, -0.62),
                  child: Transform.rotate(
                    angle: (hash % 7 - 3) / 100.0,
                    child: Text(
                      second,
                      style: const TextStyle(fontSize: 44, height: 1.1),
                    ),
                  ),
                ),
              if (third != null)
                Align(
                  alignment: const Alignment(-0.66, 0.72),
                  child: Transform.rotate(
                    angle: (hash % 5 - 2) / 90.0,
                    child: Text(
                      third,
                      style: const TextStyle(fontSize: 34, height: 1.1),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
