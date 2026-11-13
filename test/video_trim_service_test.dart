import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/data/services/video_trim_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('serafim/video_trim');
  final calls = <MethodCall>[];

  tearDown(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  void answer(Object? Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (c) {
          calls.add(c);
          return Future.value(handler(c));
        });
  }

  test(
    'asks the phone to trim in milliseconds and returns the new file',
    () async {
      answer((_) => '/cache/trimmed/trim-1.mp4');
      final out = await MethodChannelVideoTrimService(supported: true).trim(
        path: '/dcim/clip.mp4',
        start: const Duration(seconds: 2, milliseconds: 500),
        end: const Duration(seconds: 12),
      );
      expect(out, '/cache/trimmed/trim-1.mp4');
      expect(calls.single.method, 'trim');
      expect(calls.single.arguments, {
        'path': '/dcim/clip.mp4',
        'startMs': 2500,
        'endMs': 12000,
      });
    },
  );

  test('an answer with no file is an error, not a silent success', () {
    answer((_) => null);
    expect(
      MethodChannelVideoTrimService(supported: true).trim(
        path: '/a.mp4',
        start: Duration.zero,
        end: const Duration(seconds: 3),
      ),
      throwsStateError,
    );
  });

  test('cancel is passed on', () async {
    answer((_) => null);
    await MethodChannelVideoTrimService(supported: true).cancel();
    expect(calls.single.method, 'cancel');
  });
}
