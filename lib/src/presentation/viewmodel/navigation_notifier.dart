import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/core/config/feature_flags.dart';

/// Where Chats sits in the bottom bar: after the Feed when there is one.
int get chatsTabIndex => FeatureFlags.posts ? 1 : 0;

class NavigationNotifier extends Notifier<int> {
  @override
  int build() {
    // The app opens on Chats, not the Feed.
    return chatsTabIndex;
  }

  void setIndex(int index) {
    state = index;
  }
}

final navigationNotifierProvider = NotifierProvider<NavigationNotifier, int>(
  NavigationNotifier.new,
);
