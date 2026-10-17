import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Longest voice message.
const maxVoiceDuration = Duration(minutes: 5);

/// Shorter than this is treated as an accidental tap, not a message.
const minVoiceDuration = Duration(milliseconds: 700);

/// Bars in a voice note's waveform.
const waveformBars = 40;

/// Turns microphone levels (dBFS, roughly -60…0) into [bars] values of 0–31,
/// the loudest sample in each slice. Quiet is ~0, shouting is 31.
List<int> waveformFromLevels(List<double> dbfs, {int bars = waveformBars}) {
  if (dbfs.isEmpty) return List.filled(bars, 0);
  int level(double db) {
    if (db.isNaN || db.isInfinite) return 0;
    final t = ((db + 50) / 50).clamp(0.0, 1.0);
    return (t * 31).round();
  }

  return List.generate(bars, (i) {
    final start = (i * dbfs.length / bars).floor();
    final end = math.max(start + 1, ((i + 1) * dbfs.length / bars).floor());
    var peak = -160.0;
    for (var j = start; j < end && j < dbfs.length; j++) {
      peak = math.max(peak, dbfs[j]);
    }
    return level(peak);
  });
}

/// 0:07, 1:30, 4:59.
String formatVoiceDuration(Duration d) {
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

/// What sliding the finger while holding the mic means.
enum RecordGesture { none, cancel, lock }

/// Slide left far enough to cancel; slide up far enough to lock.
RecordGesture recordGestureFor(
  Offset fromStart, {
  double cancelDistance = 90,
  double lockDistance = 70,
}) {
  if (fromStart.dx <= -cancelDistance) return RecordGesture.cancel;
  if (fromStart.dy <= -lockDistance) return RecordGesture.lock;
  return RecordGesture.none;
}
