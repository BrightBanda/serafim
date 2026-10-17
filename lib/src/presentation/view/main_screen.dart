import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/presentation/view/chat_list_page.dart';
import 'package:serafim/src/presentation/view/discover_page.dart';
import 'package:serafim/src/presentation/view/profile_page.dart';

import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';
import 'package:serafim/src/presentation/viewmodel/navigation_notifier.dart';
import 'package:serafim/src/providers/push_providers.dart';
import 'package:serafim/src/utils/app_bottom_nav.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';

/// How long a second back press has to exit the app.
const exitBackWindow = Duration(seconds: 2);

/// Decides what a system back press on the main screen does. Kept apart from
/// the widget so the timing rule can be tested on its own.
class BackToExitGuard {
  BackToExitGuard({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  DateTime? _firstPress;

  /// True when this press should close the app: it came within
  /// [exitBackWindow] of the previous one. Otherwise it starts a new window.
  bool shouldExit() {
    final now = _clock();
    final first = _firstPress;
    if (first != null && now.difference(first) <= exitBackWindow) {
      _firstPress = null;
      return true;
    }
    _firstPress = now;
    return false;
  }
}

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  // List of screens corresponding to each tab index
  static const List<Widget> _screens = [
    ChatListPage(),
    DiscoverPage(),
    ProfilePage(),
  ];

  final _backGuard = BackToExitGuard();

  /// Back on the main screen only. Pages, dialogs and sheets opened on top
  /// are their own routes, so they handle back themselves and never get here.
  void _onBack() {
    // Another tab: back returns to Chats first, like most apps.
    if (ref.read(navigationNotifierProvider) != 0) {
      ref.read(navigationNotifierProvider.notifier).setIndex(0);
      return;
    }
    if (_backGuard.shouldExit()) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      SystemNavigator.pop();
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Press back again to exit'),
          duration: exitBackWindow,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(navigationNotifierProvider);

    // Keeps the websocket connected and receipts flowing on every tab, not
    // only while a conversation is open.
    ref.watch(chatViewModelProvider);

    // Registers this phone for push notifications while signed in.
    ref.watch(pushLifecycleProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.paper,
        // IndexedStack preserves the scroll position and state of each tab screen
        body: IndexedStack(index: currentIndex, children: _screens),
        bottomNavigationBar: AppBottomNav(
          currentIndex: currentIndex,
          onTap: (index) =>
              ref.read(navigationNotifierProvider.notifier).setIndex(index),
          items: const [
            AppBottomNavItem(
              icon: Icons.chat_bubble_outline,
              selectedIcon: Icons.chat_bubble,
              label: 'Chats',
            ),
            AppBottomNavItem(
              icon: Icons.explore_outlined,
              selectedIcon: Icons.explore,
              label: 'Discover',
            ),
            AppBottomNavItem(
              icon: Icons.person_outline,
              selectedIcon: Icons.person,
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
