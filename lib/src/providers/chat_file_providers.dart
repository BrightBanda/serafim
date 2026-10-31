import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/services/chat_file_service.dart';
import 'package:serafim/src/providers/network_providers.dart';
import 'package:serafim/src/utils/video_thumbnails.dart';

final chatFileServiceProvider = Provider<ChatFileService>(
  (ref) =>
      ChatFileService(ref.watch(apiDioProvider), ref.watch(storageDioProvider)),
);

/// Makes a video's preview picture (null where it can't). Replaced in tests.
final videoThumbnailerProvider =
    Provider<Future<Uint8List?> Function(String path)>(
      (ref) => makeVideoThumbnail,
    );

/// Which way a video or audio file is moving.
enum FileTransferDirection { upload, download }

/// A video or audio file on its way up or down, with progress (0–1).
typedef FileTransfer = ({FileTransferDirection direction, double progress});

/// Videos and audio files being uploaded or downloaded, by message id.
class FileTransfers extends Notifier<Map<String, FileTransfer>> {
  @override
  Map<String, FileTransfer> build() => const {};

  void set(
    String messageId,
    FileTransferDirection direction,
    double progress,
  ) => state = {
    ...state,
    messageId: (direction: direction, progress: progress.clamp(0, 1)),
  };

  void clear(String messageId) => state = {...state}..remove(messageId);
}

final fileTransfersProvider =
    NotifierProvider<FileTransfers, Map<String, FileTransfer>>(
      FileTransfers.new,
    );
