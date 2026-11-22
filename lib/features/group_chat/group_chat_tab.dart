import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/models/assistant.dart';
import '../../core/models/world_book.dart';
import '../../core/providers/assistant_provider.dart';
import '../../core/providers/world_book_provider.dart';
import '../model/widgets/model_select_sheet.dart' show showModelSelector;
import 'group_chat_page.dart';
import 'group_chat_models.dart';

part 'group_chat_settings_tab.dart';

/// 助手设置页「群聊」tab 的对外入口。
/// 用普通函数包裹，方便 assistant_settings_edit_page.dart 里一行调用。
Widget buildGroupChatTab(String assistantId) =>
    _GroupChatTab(assistantId: assistantId);
