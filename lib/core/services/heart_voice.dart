// ---------------------------------------------------------------------------
// 心声偷看：角色说话/发动态时，模型在同一次生成里附上一段「心里真正想的」。
//
// 只有开了心声的角色才有；心声跟正文一起生成、一起存，不是点开才临时问 AI。
// 心声纯给主人偷看：不进上下文、不进摘要、不计 token，角色彼此不知道。
//
// 微信（群聊/私聊）走纯文本，用 [[心声]]...[[/心声]] 标记附在正文末尾；
// 朋友圈走 JSON，每条 post 多给一个 heart 字段。两套解析互不干扰。
// ---------------------------------------------------------------------------

/// 微信文本里心声段的开始/结束标记。
const String heartVoiceOpen = '[[心声]]';
const String heartVoiceClose = '[[/心声]]';

/// 让微信生成器在正文末尾附一段心声。只有角色开了心声才传 true。
/// 加在 _writeChatRules 之后，作为最后一条规矩。
void writeHeartVoiceRule(StringBuffer buffer, String speakerName) {
  buffer.writeln();
  buffer.writeln('【心声（只有你能看到，别写进消息正文）】');
  buffer.writeln(
    '在你要发出的那些话后面，另起一行，用 $heartVoiceOpen 开头、'
    '$heartVoiceClose 结尾，写一段「$speakerName 嘴上没说、心里真正想的话」。',
  );
  buffer.writeln(
    '这段心声必须是这个人真实的、甚至和嘴上那句相反的想法：'
    '可以嘴硬心软、口是心非、有小心思或不爽。1~2 句，口语，简短。'
    '这是给主人偷看的隐私，角色本人不会说出来、对方也不知道。',
  );
  buffer.writeln(
    '没有心声可写时也要给一段（哪怕只是「其实没说什么，就是想发句消息」）。'
    '标记和正文分开，正文里绝不要出现心声标记。',
  );
}

/// 从微信生成结果里剥出心声，返回 (去掉心声后的正文, 心声)。
/// 没标记或没开心声时 heartVoice 为空，正文原样返回。
({String text, String heartVoice}) splitHeartVoice(String raw) {
  final start = raw.indexOf(heartVoiceOpen);
  if (start < 0) return (text: raw, heartVoice: '');
  final end = raw.indexOf(heartVoiceClose, start + heartVoiceOpen.length);
  final before = raw.substring(0, start);
  if (end < 0) {
    // 只有开标记没有闭标记：把开标记之后当心声，正文保留前面的。
    final heart = raw.substring(start + heartVoiceOpen.length).trim();
    return (text: before.trimRight(), heartVoice: heart);
  }
  final heart = raw
      .substring(start + heartVoiceOpen.length, end)
      .trim();
  final after = raw.substring(end + heartVoiceClose.length);
  final text = '$before$after'.trim();
  return (text: text, heartVoice: heart);
}

/// 朋友圈 JSON 里心声字段的写法说明，追加到 userPrompt 的输出格式要求里。
String get momentHeartVoiceRule =>
    '每条动态的 JSON 里，若这个角色开了心声，多给一个 "heart" 字段：'
    '写他嘴上没说、心里真正想的话（1~2 句，可以和动态内容相反、嘴硬心软）。'
    '这是给主人偷看的隐私，不写进 text，对方不知道。';
