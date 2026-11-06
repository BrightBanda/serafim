import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/presentation/view/auth_gate.dart';
import 'package:serafim/src/core/config/app_config.dart';
import 'package:serafim/src/presentation/viewmodel/auth_view_model.dart';
import 'package:serafim/src/providers/app_providers.dart';
import 'package:serafim/src/providers/auth_providers.dart';
import 'package:serafim/src/utils/serafim_loader.dart';

void main() {
  testWidgets('the mascot stays up a while however fast the app loads, then '
      'goes, without restarting what is behind it', (t) async {
    // A configuration problem is the quickest thing the gate can show.
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              supabaseUrl: '',
              supabasePublishableKey: '',
              apiBaseUrl: '',
            ),
          ),
        ],
        child: const MaterialApp(home: AuthGate()),
      ),
    );
    await t.pump();
    final message = find.text('Not configured');
    expect(
      WidgetsBinding.instance.sendFramesToEngine,
      isFalse,
      reason: 'the logo stays while the first screen is built',
    );
    expect(find.byType(SerafimLoader), findsOneWidget);
    final behind = t.element(message);

    await t.pump(const Duration(milliseconds: 700));
    expect(WidgetsBinding.instance.sendFramesToEngine, isTrue);
    await t.pump(const Duration(milliseconds: 1700));
    expect(find.byType(SerafimLoader), findsOneWidget, reason: 'still up');

    await t.pump(const Duration(milliseconds: 800));
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 16));
    expect(find.byType(SerafimLoader), findsNothing, reason: 'gone');
    expect(identical(t.element(message), behind), isTrue, reason: 'kept');
  });

  testWidgets('while it is still loading after that, the one mascot stays', (
    t,
  ) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              supabaseUrl: 'https://x.example',
              supabasePublishableKey: 'k',
              apiBaseUrl: 'https://x.example',
            ),
          ),
          authStatusProvider.overrideWithValue(AuthStatus.unknown),
        ],
        child: const MaterialApp(home: AuthGate()),
      ),
    );
    await t.pump(const Duration(seconds: 1));
    expect(WidgetsBinding.instance.sendFramesToEngine, isFalse);
    await t.pump(const Duration(milliseconds: 1100));
    expect(
      WidgetsBinding.instance.sendFramesToEngine,
      isTrue,
      reason: 'loading is slow: the logo does not wait for ever',
    );
    expect(find.byType(SerafimLoader), findsOneWidget);
    await t.pump(const Duration(seconds: 3));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(SerafimLoader), findsOneWidget, reason: 'never two');
  });
}
