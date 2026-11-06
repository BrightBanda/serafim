import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/utils/serafim_loader.dart';

void main() {
  group('its movement', () {
    test('squashes on the floor, then leaps and spins', () {
      final squashed = loaderPoseAt(0.12);
      expect(squashed.lift, 0);
      expect(squashed.scaleY, lessThan(0.75));
      expect(squashed.scaleX, greaterThan(1.15));
      expect(squashed.turn, 0);

      final top = loaderPoseAt(0.62);
      expect(top.lift, closeTo(1, 0.01));
      expect(top.turn.abs(), closeTo(3.14, 0.1));
      expect(top.shadow, lessThan(squashed.shadow));
    });

    test('is a smooth loop: no jump where one bounce meets the next', () {
      for (var beat = 1; beat <= 12; beat++) {
        final before = loaderPoseAt(beat - 0.0005);
        final after = loaderPoseAt(beat + 0.0005);
        expect(before.lift, closeTo(after.lift, 0.01));
        expect(after.scaleY, closeTo(1, 0.02));
        // A full turn looks the same as none.
        expect(before.turn.abs(), closeTo(6.2832, 0.01));
      }
    });

    test('pulls a new face every bounce, and spins both ways', () {
      final faces = [for (var b = 0; b < 6; b++) loaderPoseAt(b + 0.5).face];
      expect(faces.toSet(), hasLength(6));
      expect(loaderPoseAt(0.6).turn.sign, -loaderPoseAt(1.6).turn.sign);
    });
  });

  group('the widget', () {
    testWidgets('moving it never rebuilds its page', (t) async {
      var builds = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (_) {
              builds++;
              return const Center(child: SerafimLoader());
            },
          ),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await t.pump(const Duration(milliseconds: 16));
      }
      expect(builds, 1);
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('serafim-loader')),
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );
    });

    testWidgets('stops when its page is off screen', (t) async {
      await t.pumpWidget(
        const MaterialApp(
          home: TickerMode(enabled: false, child: SerafimLoader()),
        ),
      );
      await t.pump();
      expect(t.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('stands still when the phone asks for less motion', (t) async {
      await t.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: SerafimLoader(),
          ),
        ),
      );
      await t.pump();
      expect(t.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('goes away cleanly', (t) async {
      await t.pumpWidget(const MaterialApp(home: SerafimLoader()));
      await t.pump(const Duration(milliseconds: 100));
      await t.pumpWidget(const SizedBox());
      await t.pump();
      expect(t.binding.hasScheduledFrame, isFalse);
      expect(t.takeException(), isNull);
    });
  });

  test('drawing a frame is cheap', () {
    final clock = Stopwatch()..start();
    for (var i = 0; i < 2000; i++) {
      final recorder = ui.PictureRecorder();
      SerafimLoaderPainter(
        beats: AlwaysStoppedAnimation(i * 0.01),
        ink: Colors.white,
        accent: Colors.purple,
        fill: Colors.black,
      ).paint(Canvas(recorder), const Size.square(170));
      recorder.endRecording().dispose();
    }
    clock.stop();
    final perFrame = clock.elapsedMicroseconds / 2000;
    // ignore: avoid_print
    print('loader frame: ${perFrame.toStringAsFixed(1)} µs');
    // A 60 Hz frame is 16 667 µs. Measured on a desktop, so a wide margin.
    expect(perFrame, lessThan(1000));
  });
}
