import 'dart:io';

import 'package:flutter/material.dart';
import 'package:serafim/src/utils/limited_gif.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// One picture in the viewer, with what can be done to it.
typedef GalleryImage = ({
  String path,
  Future<void> Function()? onSave,
  Future<void> Function()? onDelete,
});

/// Opens [images] full screen at [initialIndex]; swipe sideways to move
/// through them (the pictures that were sent together).
Future<void> openChatImageGallery(
  BuildContext context,
  List<GalleryImage> images, {
  int initialIndex = 0,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) =>
        ChatImageGallery(images: images, initialIndex: initialIndex),
  ),
);

class ChatImageGallery extends StatefulWidget {
  const ChatImageGallery({
    super.key,
    required this.images,
    this.initialIndex = 0,
  });

  final List<GalleryImage> images;
  final int initialIndex;

  @override
  State<ChatImageGallery> createState() => _ChatImageGalleryState();
}

class _ChatImageGalleryState extends State<ChatImageGallery> {
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  /// While a picture is zoomed in, dragging pans it instead of turning the
  /// page.
  bool _zoomed = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.images;
    final current = images[_index];
    final width =
        (MediaQuery.sizeOf(context).width *
                MediaQuery.devicePixelRatioOf(context))
            .round();
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: images.length > 1
            ? Text(
                '${_index + 1} of ${images.length}',
                style: AppTextStyles.fieldLabel.copyWith(color: Colors.white),
              )
            : null,
        actions: [
          if (current.onDelete case final delete?)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                Navigator.of(context).pop();
                delete();
              },
            ),
          if (current.onSave case final save?)
            IconButton(
              tooltip: 'Download',
              icon: const Icon(Icons.download_outlined),
              onPressed: save,
            ),
        ],
      ),
      body: PageView.builder(
        controller: _pages,
        physics: _zoomed
            ? const NeverScrollableScrollPhysics()
            : const PageScrollPhysics(),
        itemCount: images.length,
        onPageChanged: (i) => setState(() {
          _index = i;
          _zoomed = false;
        }),
        itemBuilder: (_, i) {
          final path = images[i].path;
          return _ZoomablePage(
            key: ValueKey(path),
            onZoomChanged: (zoomed) {
              if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
            },
            child: isGifPath(path)
                ? LimitedGif(path: path, cacheWidth: width)
                : Image.file(
                    File(path),
                    cacheWidth: width,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 40,
                    ),
                  ),
          );
        },
      ),
    );
  }
}

class _ZoomablePage extends StatefulWidget {
  const _ZoomablePage({
    super.key,
    required this.child,
    required this.onZoomChanged,
  });

  final Widget child;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomablePage> createState() => _ZoomablePageState();
}

class _ZoomablePageState extends State<_ZoomablePage> {
  final _transform = TransformationController();

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InteractiveViewer(
    transformationController: _transform,
    maxScale: 5,
    onInteractionEnd: (_) =>
        widget.onZoomChanged(_transform.value.getMaxScaleOnAxis() > 1.01),
    child: Center(child: widget.child),
  );
}
