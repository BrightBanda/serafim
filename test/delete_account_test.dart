import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/data/models/profile.dart';
import 'package:serafim/src/presentation/view/settings/delete_account_page.dart';
import 'package:serafim/src/presentation/view/settings_page.dart';
import 'package:serafim/src/presentation/viewmodel/profile_view_model.dart';
import 'package:serafim/src/providers/profile_providers.dart';
import 'package:serafim/src/providers/update_providers.dart';
import 'package:serafim/src/utils/serafim_button.dart';

class _Profile extends ProfileViewModel {
  @override
  FutureOr<Profile?> build() => Profile(
    userId: 'me',
    displayName: 'Alice',
    username: 'alice',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

Future<void> _pump(WidgetTester t, Widget home) async {
  t.view.physicalSize = const Size(800, 1800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        profileViewModelProvider.overrideWith(_Profile.new),
        installedVersionProvider.overrideWith((ref) => null),
      ],
      child: MaterialApp(home: home),
    ),
  );
  await t.pumpAndSettle();
}

bool _enabled(WidgetTester t) =>
    t
        .widget<SerafimButton>(find.byKey(const ValueKey('delete-account-go')))
        .onPressed !=
    null;

void main() {
  testWidgets('not on the main settings page any more', (t) async {
    await _pump(t, const SettingsPage());
    expect(find.text('Delete account'), findsNothing);
  });

  testWidgets('typing works, and only the username unlocks it', (t) async {
    await _pump(t, const DeleteAccountPage());
    expect(find.textContaining('alice'), findsWidgets);
    expect(_enabled(t), isFalse);

    final field = find.descendant(
      of: find.byKey(const ValueKey('delete-account-confirm')),
      matching: find.byType(TextField),
    );
    for (final text in ['a', 'al', 'ali', 'alic']) {
      await t.enterText(field, text);
      await t.pump();
      expect(_enabled(t), isFalse);
    }
    await t.enterText(field, '@Alice');
    await t.pump();
    expect(_enabled(t), isTrue);
    expect(t.takeException(), isNull);
  });
}
