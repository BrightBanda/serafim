import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/data/models/app_settings.dart';
import 'package:serafim/src/presentation/view/auth_gate.dart';
import 'package:serafim/src/providers/settings_providers.dart';
import 'package:serafim/src/utils/rebuild_all.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  // Draw behind the status/navigation bars; every screen keeps its content in
  // the safe area itself.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // The very first frame already uses the saved theme.
  AppColors.apply(
    ThemeChoice.parse(
      prefs.getString('settings.themeChoice'),
    ).resolve(PlatformDispatcher.instance.platformBrightness),
  );

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const SerafimApp(),
    ),
  );
}

class SerafimApp extends ConsumerStatefulWidget {
  const SerafimApp({super.key});

  @override
  ConsumerState<SerafimApp> createState() => _SerafimAppState();
}

class _SerafimAppState extends ConsumerState<SerafimApp>
    with WidgetsBindingObserver {
  Brightness? _applied;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The phone switched between light and dark while "Match system" is on.
  @override
  void didChangePlatformBrightness() {
    if (ref.read(settingsProvider).themeChoice == ThemeChoice.system) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final brightness = settings.themeChoice.resolve(
      PlatformDispatcher.instance.platformBrightness,
    );

    final changed = _applied != null && _applied != brightness;
    AppColors.apply(brightness);
    _applied = brightness;
    if (changed) {
      // Colors are read while building, so const subtrees need a nudge.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) rebuildEverythingBelow(this.context);
      });
    }

    final isLight = brightness == Brightness.light;
    final base = isLight ? ThemeData.light() : ThemeData.dark();

    return MaterialApp(
      title: 'Serafim',
      debugShowCheckedModeBanner: false,
      navigatorKey: ref.watch(navigatorKeyProvider),
      // Colors switch instantly; no cross-fade between palettes.
      themeAnimationDuration: Duration.zero,
      theme: base.copyWith(
        scaffoldBackgroundColor: AppColors.paper,
        canvasColor: AppColors.paper,
        dialogTheme: DialogThemeData(backgroundColor: AppColors.paperAlt),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppColors.paperRaised,
          contentTextStyle: TextStyle(color: AppColors.text),
        ),
        colorScheme: base.colorScheme.copyWith(
          primary: AppColors.primary,
          surface: AppColors.paper,
        ),
      ),
      // Text size setting and status-bar icon contrast for the active theme.
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
          statusBarBrightness: isLight ? Brightness.light : Brightness.dark,
          systemNavigationBarColor: AppColors.paper,
          systemNavigationBarIconBrightness: isLight
              ? Brightness.dark
              : Brightness.light,
          systemNavigationBarDividerColor: Colors.transparent,
        ),
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(settings.textSize.scale)),
          child: child!,
        ),
      ),
      home: const AuthGate(),
    );
  }
}
