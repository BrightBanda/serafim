import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/presentation/view/auth_gate.dart';
import 'package:serafim/src/presentation/view/chat_list_page.dart';
import 'package:serafim/src/presentation/view/chat_test_screen.dart';
import 'package:serafim/src/presentation/view/chat_thread_page.dart';
import 'package:serafim/src/presentation/viewmodel/navigation_notifier.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';

// Import your actual screen widgets here
class MainScreen extends ConsumerWidget {
  const MainScreen({super.key});

  // List of screens corresponding to each tab index
  static const List<Widget> _screens = [
    ChatListPage(),
    Center(child: Text('Discover')),
    Home(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(navigationNotifierProvider);

    return Scaffold(
      backgroundColor: AppColors.paper,
      // IndexedStack preserves the scroll position and state of each tab screen
      body: IndexedStack(index: currentIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          ref.read(navigationNotifierProvider.notifier).setIndex(index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Discover',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
