import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:serafim/src/presentation/view/image_editor_page.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// Shows the picture about to be sent, full screen, with Send and an Edit
/// button. Editing is optional: most pictures are just sent.
///
/// Returns the bytes to send (edited or not), or null if the person backed
/// out.
Future<Uint8List?> previewImage(
  BuildContext context,
  Uint8List bytes, {
  int maxSide = 1280,
  int quality = 75,
}) => Navigator.of(context).push<Uint8List>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) =>
        ImagePreviewPage(bytes: bytes, maxSide: maxSide, quality: quality),
  ),
);

class ImagePreviewPage extends StatefulWidget {
  const ImagePreviewPage({
    super.key,
    required this.bytes,
    this.maxSide = 1280,
    this.quality = 75,
  });

  final Uint8List bytes;
  final int maxSide;
  final int quality;

  @override
  State<ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<ImagePreviewPage> {
  late Uint8List _bytes = widget.bytes;

  Future<void> _edit() async {
    final edited = await editImage(
      context,
      _bytes,
      maxSide: widget.maxSide,
      quality: widget.quality,
    );
    // Backing out of the editor keeps the picture as it was.
    if (edited != null && mounted) setState(() => _bytes = edited);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: InteractiveViewer(
                maxScale: 5,
                child: Center(child: Image.memory(_bytes, fit: BoxFit.contain)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('preview-edit'),
                    onPressed: _edit,
                    icon: const Icon(Icons.tune, size: 18),
                    label: const Text('EDIT'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54, width: 1.5),
                      shape: const RoundedRectangleBorder(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    key: const ValueKey('preview-send'),
                    onTap: () => Navigator.of(context).pop(_bytes),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        border: Border.all(color: AppColors.line, width: 2),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'SEND',
                            style: AppTextStyles.buttonLabel.copyWith(
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.send, size: 16, color: Colors.white),
                        ],
                      ),
                    ),
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
