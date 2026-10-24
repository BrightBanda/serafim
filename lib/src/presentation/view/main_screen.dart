import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/presentation/view/chat_list_page.dart';
import 'package:serafim/src/presentation/view/circles_page.dart';
import 'package:serafim/src/presentation/view/discover_page.dart';
import 'package:serafim/src/core/platform/incoming_share.dart';
import 'package:serafim/src/presentation/view/feed_page.dart';
import 'package:serafim/src/presentation/view/forward_page.dart';

import 'package:serafim/src/core/config/feature_flags.dart';
import 'package:serafim/src/presentation/viewmodel/chat_viewmodel.dart';
import 'package:serafim/src/presentation/viewmodel/navigation_notifier.dart';
import 'package:serafim/src/providers/backup_providers.dart';
import 'package:serafim/src/providers/push_providers.dart';
import 'package:serafim/src/providers/update_providers.dart';
import 'package:serafim/src/utils/update/update_prompt.dart';
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
  bool _promptShown = false;

  @override
  void initState() {
    super.initState();
    // Something shared to Serafim from another app: choose who gets it. This
    // screen only exists once signed in, so a share made before that waits.
    ref.listenManual<String?>(incomingShareProvider, (_, text) {
      if (text == null) return;
      ref.read(incomingShareProvider.notifier).consume();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => ForwardPage.shareText(text)),
        );
      });
    }, fireImmediately: true);

    // Offer a newer version once per launch (unless dismissed for it).
    ref.listenManual<AsyncValue<UpdateStatus>>(updateCheckProvider, (_, next) {
      final status = next.value;
      final update = status?.available;
      if (_promptShown || update == null || status!.mustUpdate) return;
      if (ref
          .read(updateCheckProvider.notifier)
          .isDismissed(update.versionCode)) {
        return;
      }
      _promptShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showUpdatePrompt(context, update);
      });
    }, fireImmediately: true);

    // Automatic backups are checked now and whenever the app comes back, and
    // say how they went (one started by a tap reports on its own screen).
    ref.listenManual<AutoBackupState>(autoBackupProvider, (previous, next) {
      if (previous == null || !previous.running || next.running) return;
      if (!next.lastRunAutomatic || !mounted) return;
      final error = next.lastError;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error == null
                ? 'Automatic backup saved to Google Drive.'
                : 'Automatic backup failed. $error',
          ),
          backgroundColor: error == null ? null : AppColors.rust,
        ),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(autoBackupProvider.notifier).attach();
    });
  }

  /// Tabs actually shown, in the order Feed · Whispers · Discover · Circles.
  /// Feed and Circles only appear when their feature is on — a tab that
  /// cannot do anything is worse than no tab. Profile is not a tab: it lives
  /// in the menu at the right of every top bar.
  ///
  /// The lists are `const`, so the widgets are canonical and an `IndexedStack`
  /// does not throw each tab's state away on rebuild.
  static const _plain = [ChatListPage(), DiscoverPage()];
  static const _withCircles = [ChatListPage(), DiscoverPage(), CirclesPage()];
  static const _withFeed = [FeedPage(), ChatListPage(), DiscoverPage()];
  static const _withBoth = [
    FeedPage(),
    ChatListPage(),
    DiscoverPage(),
    CirclesPage(),
  ];

  static List<Widget> get _screens => FeatureFlags.circles
      ? (FeatureFlags.posts ? _withBoth : _withCircles)
      : (FeatureFlags.posts ? _withFeed : _plain);

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
          items: _navItems,
        ),
      ),
    );
  }
}

/// The bottom bar, in the same order as [_MainScreenState._screens].
final List<AppBottomNavItem> _navItems = [
  if (FeatureFlags.posts)
    const AppBottomNavItem(
      icon: Icons.dynamic_feed_outlined,
      selectedIcon: Icons.dynamic_feed,
      label: 'Feed',
    ),
  const AppBottomNavItem(
    icon: Icons.chat_bubble_outline,
    selectedIcon: Icons.chat_bubble,
    label: 'Whispers',
  ),
  const AppBottomNavItem(
    icon: Icons.explore_outlined,
    selectedIcon: Icons.explore,
    label: 'Discover',
  ),
  if (FeatureFlags.circles)
    const AppBottomNavItem(
      icon: Icons.groups_outlined,
      selectedIcon: Icons.groups,
      label: 'Circles',
    ),
];

/// Where Discover sits in the bar, for screens that jump to it.
int get discoverTabIndex => FeatureFlags.posts ? 2 : 1;
