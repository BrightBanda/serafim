import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/utils/text_edit_dialog.dart';

/// Opens the dialog from a button and records what it returned. A test fails
/// on any exception, so closing it cleanly is part of every check.
Future<List<String?>> _open(
  WidgetTester t, {
  String initial = 'old',
  String? Function(String)? validate,
  Future<String?> Function(String)? onSave,
}) async {
  final results = <String?>[];
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => results.add(
              await showTextEditDialog(
                context,
                title: 'Edit message',
                initial: initial,
                validate: validate,
                onSave: onSave,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  return results;
}

void main() {
  testWidgets('Save closes the dialog and returns the text', (t) async {
    final results = await _open(t);
    await t.enterText(find.byType(TextField), 'new');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(results, ['new']);
  });

  testWidgets('Cancel closes the dialog and saves nothing', (t) async {
    var saves = 0;
    final results = await _open(
      t,
      onSave: (_) async {
        saves++;
        return null;
      },
    );
    await t.enterText(find.byType(TextField), 'changed');
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(results, [null]);
    expect(saves, 0);
  });

  testWidgets('invalid text is explained and the dialog stays', (t) async {
    final results = await _open(
      t,
      validate: (s) => s.trim().isEmpty ? 'A message cannot be empty.' : null,
    );
    await t.enterText(find.byType(TextField), '   ');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(find.text('A message cannot be empty.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(results, isEmpty);
  });

  testWidgets('an async save shows progress, cannot be dismissed or sent '
      'twice, and closes when it works', (t) async {
    final gate = Completer<String?>();
    var saves = 0;
    final results = await _open(
      t,
      onSave: (_) {
        saves++;
        return gate.future;
      },
    );
    await t.tap(find.text('Save'));
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // A second tap, Cancel and the back button all do nothing meanwhile.
    await t.tap(find.byType(CircularProgressIndicator), warnIfMissed: false);
    await t.tap(find.text('Cancel'), warnIfMissed: false);
    await t.binding.handlePopRoute();
    await t.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(saves, 1);

    gate.complete(null);
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(results, ['old']);
  });

  testWidgets('a failed save keeps the dialog and the text, and says why', (
    t,
  ) async {
    final results = await _open(
      t,
      onSave: (_) async => 'You are offline. Try again when connected.',
    );
    await t.enterText(find.byType(TextField), 'my edit');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(
      find.text('You are offline. Try again when connected.'),
      findsOneWidget,
    );
    expect(find.text('my edit'), findsOneWidget);
    expect(results, isEmpty);

    // Still usable: Cancel closes it cleanly.
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(results, [null]);
  });
}
