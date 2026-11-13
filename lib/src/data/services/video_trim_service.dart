import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Cuts a part out of a video on this phone.
abstract interface class VideoTrimService {
  /// Whether this platform can trim. Where it can't, videos send whole.
  bool get supported;

  /// Writes [start]..[end] of the video at [path] to a new file and returns
  /// its path. The caller owns that file and deletes it when done.
  Future<String> trim({
    required String path,
    required Duration start,
    required Duration end,
  });

  /// Stops a trim in progress.
  Future<void> cancel();
}

/// Android's Media3 Transformer, through `VideoTrimmer.kt`.
class MethodChannelVideoTrimService implements VideoTrimService {
  MethodChannelVideoTrimService({
    MethodChannel? channel,
    bool? supported,
  }) : _channel = channel ?? const MethodChannel('serafim/video_trim'),
       supported = supported ?? (!kIsWeb && Platform.isAndroid);

  final MethodChannel _channel;

  @override
  final bool supported;

  @override
  Future<String> trim({
    required String path,
    required Duration start,
    required Duration end,
  }) async {
    final out = await _channel.invokeMethod<String>('trim', {
      'path': path,
      'startMs': start.inMilliseconds,
      'endMs': end.inMilliseconds,
    });
    if (out == null) throw StateError('The trimmer returned no file.');
    return out;
  }

  @override
  Future<void> cancel() => _channel.invokeMethod<void>('cancel');
}
