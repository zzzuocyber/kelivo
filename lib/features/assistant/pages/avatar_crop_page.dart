import 'dart:io';

import 'package:flutter/material.dart';
import 'package:profile_image_cropper/profile_image_cropper.dart';
import 'package:uuid/uuid.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/snackbar.dart';

/// 手机端头像裁剪页。
///
/// 圆形半透明遮罩仅作预览（头像显示为圆形），实际保存的是 1:1 正方形完整图，
/// 不做圆形裁切、不留透明角。cropper 的遮罩是 RepaintBoundary 的兄弟节点，
/// 不进入 toImage 结果，因此输出天然是正方形原图像素。
class AvatarCropPage extends StatefulWidget {
  const AvatarCropPage({super.key, required this.imagePath});
  final String imagePath;

  @override
  State<AvatarCropPage> createState() => _AvatarCropPageState();
}

class _AvatarCropPageState extends State<AvatarCropPage> {
  final GlobalKey _cropKey = GlobalKey();
  bool _saving = false;

  Future<void> _confirm() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final bytes = await ProfileImageCropper.crop(
        imageCropperKey: _cropKey,
        pixelRatio: 3.0,
      );
      if (bytes == null || !mounted) return;
      final out =
          '${Directory.systemTemp.path}${Platform.pathSeparator}'
          'avatar_crop_${const Uuid().v4()}.png';
      await File(out).writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      Navigator.of(context).pop<String>(out);
    } catch (_) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      showAppSnackBar(
        context,
        message: l10n.assistantEditGeneralErrorMessage,
        type: NotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.assistantEditAvatarCropPageTitle),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _confirm,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.assistantEditAvatarCropConfirm),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: ProfileImageCropper(
                    imageCropperKey: _cropKey,
                    image: Image.file(File(widget.imagePath)),
                    aspectRatio: 1.0,
                    overlayType: OverlayType.circle,
                    overlayColor: Colors.black54,
                    backgroundColor: Colors.black,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                l10n.assistantEditAvatarCropHint,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
