import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/presentation/viewmodel/navigation_notifier.dart';

void main() {
  test('the app opens on Whispers, not the Feed', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(navigationNotifierProvider), whispersTabIndex);
    // With the Feed on, it is the tab after the Feed.
    expect(whispersTabIndex, 1);
  });
}
