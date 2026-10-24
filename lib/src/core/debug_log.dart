import 'dart:io';

import 'package:flutter/foundation.dart';

/// A line of trace for developers, in debug builds only: it does nothing in a
/// release build.
///
/// It goes to the console (on Android that is `adb logcat -s flutter`), and on
/// a desktop build also to `serafim_debug.log` in the system temp folder, so a
/// run can be read without the IDE's console.
void trace(String tag, String message) {
  if (!kDebugMode) return;
  final now = DateTime.now().toIso8601String().substring(11, 23);
  final line = '$now [$tag] $message';
  debugPrint(line);
  if (kIsWeb) return;
  // Unit tests also run in debug mode; keep their chatter out of the file.
  if (Platform.environment.containsKey('FLUTTER_TEST')) return;
  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    try {
      File(
        '${Directory.systemTemp.path}/serafim_debug.log',
      ).writeAsStringSync('$line\n', mode: FileMode.append);
    } catch (_) {
      // Tracing must never break the app.
    }
  }
}
