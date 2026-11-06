import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:serafim/src/data/services/media_library.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:serafim/src/utils/themes/app_text_styles.dart';

/// The most that can be chosen at once: each one takes memory while it is being
/// prepared.
const maxMediaPick = 4;

String formatMediaDuration(Duration d) {
  final seconds = d.inSeconds % 60;
  final minutes = d.inMinutes % 60;
  final two = seconds.toString().padLeft(2, '0');
  return d.inHours > 0
      ? '${d.inHours}:${minutes.toString().padLeft(2, '0')}:$two'
      : '$minutes:$two';
}

/// One photo or video: its small picture, its length if a video, and its
/// number in the selection. Loads only when built, so only what is on screen
/// costs memory.
class MediaThumb extends StatefulWidget {
  const MediaThumb({
    super.key,
    required this.media,
    required this.position,
    required this.onTap,
    this.side = 200,
  });

  final DeviceMedia media;

  /// 1, 2, … in the selection; null when not selected.
  final int? position;
  final VoidCallback onTap;
  final int side;

  @override
  State<MediaThumb> createState() => _MediaThumbState();
}

class _MediaThumbState extends State<MediaThumb> {
  late Future<Uint8List?> _bytes = widget.media.thumbnail(widget.side);

  @override
  void didUpdateWidget(MediaThumb old) {
    super.didUpdateWidget(old);
    if (old.media.id != widget.media.id) {
      _bytes = widget.media.thumbnail(widget.side);
    }
  }

  @override
  Widget build(BuildContext context) {
    final position = widget.position;
    return GestureDetector(
      key: ValueKey('media-${widget.media.id}'),
      onTap: widget.onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: AppColors.paperRaised,
            child: FutureBuilder<Uint8List?>(
              future: _bytes,
              builder: (_, snap) {
                final bytes = snap.data;
                if (bytes == null) return const SizedBox.shrink();
                return Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  cacheWidth: widget.side,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => Icon(
                    Icons.broken_image_outlined,
                    color: AppColors.textDim,
                  ),
                );
              },
            ),
          ),
          if (widget.media.isVideo)
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                color: Colors.black54,
                child: Text(
                  '▶ ${formatMediaDuration(widget.media.duration)}',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
          if (position != null) ...[
            ColoredBox(color: AppColors.primary.withValues(alpha: 0.35)),
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Text(
                  '$position',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Asks for access to the phone's media, in place. Android's own prompt only
/// appears when this is tapped. After a refusal Android may stop asking, so it
/// then offers the settings instead.
class MediaAccessCard extends StatelessWidget {
  const MediaAccessCard({
    super.key,
    required this.text,
    required this.refused,
    required this.onAllow,
    required this.onSettings,
  });

  final String text;
  final bool refused;
  final VoidCallback onAllow;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.paper,
        border: Border.all(color: AppColors.lineSoft, width: 1.5),
      ),
      child: Row(
        children: [
          Icon(Icons.perm_media_outlined, color: AppColors.primaryPale),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              refused ? 'Serafim needs access to show these here.' : text,
              style: AppTextStyles.smallDim.copyWith(color: AppColors.text),
            ),
          ),
          TextButton(
            key: ValueKey(refused ? 'media-settings' : 'media-allow'),
            onPressed: refused ? onSettings : onAllow,
            child: Text(
              refused ? 'Settings' : 'Allow',
              style: AppTextStyles.linkText,
            ),
          ),
        ],
      ),
    );
  }
}

/// A selection, in the order it was tapped, up to [maxMediaPick].
class MediaSelection {
  final List<DeviceMedia> items = [];

  int? positionOf(DeviceMedia m) {
    final i = items.indexWhere((x) => x.id == m.id);
    return i < 0 ? null : i + 1;
  }

  /// False when it was already full.
  bool toggle(DeviceMedia m) {
    final i = items.indexWhere((x) => x.id == m.id);
    if (i >= 0) {
      items.removeAt(i);
      return true;
    }
    if (items.length >= maxMediaPick) return false;
    items.add(m);
    return true;
  }
}
