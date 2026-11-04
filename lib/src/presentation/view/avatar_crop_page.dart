import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/image_picking.dart';
import 'package:serafim/src/utils/image_shrink.dart';
import 'package:serafim/src/utils/serafim_button.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Picks a photo, lets the person frame it in a circle, and returns a
/// square picture at most [maxSide] pixels across. Null if they back out.
Future<Uint8List?> pickAvatar(
  BuildContext context, {
  int maxSide = 512,
  int quality = 80,
  VoidCallback? onPicked,
}) async {
  // Picked larger than the result, so the crop still has detail to use.
  final picked = await pickShrunkImage(
    context,
    maxSide: maxSide * 3,
    quality: 90,
    onPicked: onPicked,
  );
  if (picked == null || !context.mounted) return null;
  final cropped = await Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(builder: (_) => AvatarCropPage(bytes: picked)),
  );
  if (cropped == null) return null;
  return shrinkImage(cropped, maxSide: maxSide, quality: quality);
}

/// Square crop with a round guide, the shape the photo is shown in.
class AvatarCropPage extends StatefulWidget {
  const AvatarCropPage({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  State<AvatarCropPage> createState() => _AvatarCropPageState();
}

class _AvatarCropPageState extends State<AvatarCropPage> {
  final _controller = CropController();
  bool _busy = false;

  void _onCropped(CropResult result) {
    if (!mounted) return;
    switch (result) {
      case CropSuccess(:final croppedImage):
        Navigator.of(context).pop(croppedImage);
      case CropFailure():
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't crop that photo. Try another."),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppTopBar(
        title: 'CROP PHOTO',
        onBack: () => Navigator.of(context).pop(),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 24,
                ),
                child: Crop(
                  image: widget.bytes,
                  controller: _controller,
                  withCircleUi: true,
                  aspectRatio: 1,
                  baseColor: Colors.black,
                  maskColor: Colors.black54,
                  cornerDotBuilder: (size, edge) =>
                      const DotControl(color: Colors.white, padding: 6),
                  onCropped: _onCropped,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Drag and pinch to frame your photo.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.smallDim.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SerafimButton(
                    key: const ValueKey('avatar-crop-done'),
                    label: _busy ? 'CROPPING…' : 'USE PHOTO',
                    onPressed: _busy
                        ? null
                        : () {
                            setState(() => _busy = true);
                            _controller.crop();
                          },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
