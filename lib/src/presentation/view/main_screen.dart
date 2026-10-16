import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/presentation/view/chat_list_page.dart';
import 'package:serafim/src/presentation/view/discover_page.dart';
import 'package:serafim/src/presentation/view/profile_page.dart';

import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';
import 'package:serafim/src/presentation/viewmodel/navigation_notifier.dart';
import 'package:serafim/src/providers/push_providers.dart';
import 'package:serafim/src/utils/app_bottom_nav.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';

// Import your actual screen widgets here
class MainScreen extends ConsumerWidget {
  const MainScreen({super.key});

  // List of screens corresponding to each tab index
  static const List<Widget> _screens = [
    ChatListPage(),
    DiscoverPage(),
    ProfilePage(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(navigationNotifierProvider);

    // Keeps the websocket connected and receipts flowing on every tab, not
    // only while a conversation is open.
    ref.watch(chatViewModelProvider);

    // Registers this phone for push notifications while signed in.
    ref.watch(pushLifecycleProvider);

    return Scaffold(
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
    );
  }
}
