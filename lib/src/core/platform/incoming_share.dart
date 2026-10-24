import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Text (usually a link) that another app shared to Serafim and that has not
/// been sent anywhere yet.
///
/// Android hands it over through the `serafim/share` channel: once at start
/// (the app was opened by the share) and again whenever a share arrives while
/// the app is already running. It stays here until the chat picker has taken
/// it, so a share made while signed out is not lost on the way to the login
/// screen.
class IncomingShare extends Notifier<String?> {
  static const _channel = MethodChannel('serafim/share');

  @override
  String? build() => null;

  /// Starts listening, and picks up whatever the app was opened with.
  /// Harmless where there is no such channel (iOS, desktop, tests).
  Future<void> attach() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shared') offer(call.arguments as String?);
    });
    try {
      offer(await _channel.invokeMethod<String>('takeShared'));
    } on MissingPluginException {
      // Nothing can be shared to this platform.
    }
  }

  /// Keeps [text] for the picker, if it is worth sending.
  void offer(String? text) {
    final clean = text?.trim();
    if (clean == null || clean.isEmpty) return;
    state = clean.length > maxSharedLength
        ? clean.substring(0, maxSharedLength)
        : clean;
  }

  /// The picker has it now.
  void consume() => state = null;
}

/// Messages are short; a share longer than this is cut rather than refused.
const int maxSharedLength = 4000;

final incomingShareProvider = NotifierProvider<IncomingShare, String?>(
  IncomingShare.new,
);
