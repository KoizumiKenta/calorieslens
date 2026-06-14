import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'core/state/providers.dart';
import 'core/sync/sync_engine.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const CalorieLensApp(),
    ),
  );
}

class CalorieLensApp extends ConsumerStatefulWidget {
  const CalorieLensApp({super.key});

  @override
  ConsumerState<CalorieLensApp> createState() => _CalorieLensAppState();
}

class _CalorieLensAppState extends ConsumerState<CalorieLensApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Pull anything logged on other devices for an already-authenticated
    // session — login only syncs on a fresh sign-in. No-ops when signed out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncEngineProvider.notifier).syncNow();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-sync when the app comes back to the foreground so a second device
    // picks up changes made while it was backgrounded.
    if (state == AppLifecycleState.resumed) {
      ref.read(syncEngineProvider.notifier).syncNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'CalorieLens',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: router,
    );
  }
}
