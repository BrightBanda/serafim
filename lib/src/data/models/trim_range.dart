/// The part of a video chosen to send: pure arithmetic, so the screen and its
/// tests agree on what is allowed.
class TrimRange {
  const TrimRange({
    required this.total,
    required this.start,
    required this.end,
    this.minLength = defaultMinLength,
    this.maxLength,
  });

  /// The whole video, from its first to its last frame, or its first
  /// [maxLength] when there is a limit and the video is longer.
  factory TrimRange.whole(
    Duration total, {
    Duration? minLength,
    Duration? maxLength,
  }) => TrimRange(
    total: total,
    start: Duration.zero,
    end: maxLength != null && total > maxLength ? maxLength : total,
    minLength: minLength ?? defaultMinLength,
    maxLength: maxLength,
  );

  /// Shortest clip worth sending.
  static const defaultMinLength = Duration(seconds: 1);

  /// Within this of the whole video counts as untouched: a slider can't be
  /// dragged back to the exact millisecond, and re-encoding for 50 ms of
  /// nothing would only cost quality.
  static const untouchedTolerance = Duration(milliseconds: 100);

  final Duration total;
  final Duration start;
  final Duration end;
  final Duration minLength;

  /// The longest clip allowed (a moment's 60 seconds), or null for no limit.
  final Duration? maxLength;

  Duration get length => end - start;

  /// The shortest clip allowed: [minLength], or the whole video if shorter.
  Duration get _floor => minLength < total ? minLength : total;

  /// True when nearly all of the video is kept; the original is sent as is.
  bool get isWhole =>
      start <= untouchedTolerance && total - end <= untouchedTolerance;

  /// Moves the start: never past the end minus the shortest clip, and never
  /// so far back that the clip would be longer than allowed.
  TrimRange withStart(Duration value) {
    final latest = end - _floor;
    final earliest = maxLength == null ? Duration.zero : end - maxLength!;
    return _copy(
      start: _clamp(
        value,
        earliest < Duration.zero ? Duration.zero : earliest,
        latest < Duration.zero ? Duration.zero : latest,
      ),
    );
  }

  /// Moves the end: never before the start plus the shortest clip, and never
  /// so far on that the clip would be longer than allowed.
  TrimRange withEnd(Duration value) {
    final earliest = start + _floor;
    final latest = maxLength == null ? total : start + maxLength!;
    return _copy(
      end: _clamp(
        value,
        earliest > total ? total : earliest,
        latest > total ? total : latest,
      ),
    );
  }

  /// What the clip should weigh, assuming the video's size is spread evenly
  /// over its length (it isn't quite, so this is only a guide).
  int estimatedBytes(int wholeBytes) {
    if (total <= Duration.zero) return wholeBytes;
    if (isWhole) return wholeBytes;
    return (wholeBytes * length.inMicroseconds / total.inMicroseconds).round();
  }

  TrimRange _copy({Duration? start, Duration? end}) => TrimRange(
    total: total,
    start: start ?? this.start,
    end: end ?? this.end,
    minLength: minLength,
    maxLength: maxLength,
  );

  static Duration _clamp(Duration v, Duration low, Duration high) =>
      v < low ? low : (v > high ? high : v);
}

/// "0:07", "1:05", "1:02:09".
String formatClock(Duration d) {
  final total = d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}
