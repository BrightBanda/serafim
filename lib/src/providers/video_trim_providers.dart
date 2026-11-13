import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/services/video_trim_service.dart';

final videoTrimServiceProvider = Provider<VideoTrimService>(
  (ref) => MethodChannelVideoTrimService(),
);
