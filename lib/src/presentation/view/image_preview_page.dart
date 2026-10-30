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

/// Shows separately-sendable photos in a grid. Tapping a tile opens that
/// photo in its own zoomable full-screen viewer. Returns null on cancel.
Future<List<Uint8List>?> previewImages(
  BuildContext context,
  List<Uint8List> photos,
) => Navigator.of(context).push<List<Uint8List>>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => ImageBatchPreviewPage(photos: photos),
  ),
);

class ImageBatchPreviewPage extends StatelessWidget {
  const ImageBatchPreviewPage({super.key, required this.photos});

  final List<Uint8List> photos;

  Future<void> _open(BuildContext context, int index) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => _FullScreenPhoto(bytes: photos[index], index: index),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Cancel',
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Text('${photos.length} PHOTOS'),
    ),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: photos.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemBuilder: (context, index) => GestureDetector(
                key: ValueKey('batch-preview-tile-$index'),
                onTap: () => _open(context, index),
                child: Image.memory(photos[index], fit: BoxFit.cover),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: GestureDetector(
              key: const ValueKey('batch-preview-send'),
              onTap: () => Navigator.of(context).pop(photos),
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
                      'SEND ${photos.length}',
                      style: AppTextStyles.buttonLabel.copyWith(fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.send, size: 16, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _FullScreenPhoto extends StatelessWidget {
  const _FullScreenPhoto({required this.bytes, required this.index});

  final Uint8List bytes;
  final int index;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: ValueKey('batch-preview-fullscreen-$index'),
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text('${index + 1}'),
    ),
    body: Center(
      child: InteractiveViewer(
        maxScale: 5,
        child: Image.memory(bytes, fit: BoxFit.contain),
      ),
    ),
  );
}

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
