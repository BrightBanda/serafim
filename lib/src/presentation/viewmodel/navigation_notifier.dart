import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/config/feature_flags.dart';

/// Where Whispers sits in the bottom bar: after the Feed when there is one.
int get whispersTabIndex => FeatureFlags.posts ? 1 : 0;

class NavigationNotifier extends Notifier<int> {
  @override
  int build() {
    // The app opens on Whispers, not the Feed.
    return whispersTabIndex;
  }

  void setIndex(int index) {
    state = index;
  }
}

final navigationNotifierProvider = NotifierProvider<NavigationNotifier, int>(
  NavigationNotifier.new,
);
