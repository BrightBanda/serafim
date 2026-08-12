import 'package:flutter_riverpod/flutter_riverpod.dart';

class NavigationNotifier extends Notifier<int> {
  @override
  int build() {
    // Default starting tab index (0 = Home/Feed)
    return 0;
  }

  void setIndex(int index) {
    state = index;
  }
}

final navigationNotifierProvider = NotifierProvider<NavigationNotifier, int>(
  NavigationNotifier.new,
);
