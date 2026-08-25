import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/db_sync_service.dart';
import 'data/sqlite_platform.dart';
import 'services/digest_scheduler.dart';
import 'services/digest_service.dart';
import 'services/notifier.dart';
import 'state/app_state.dart';
import 'state/digest_router.dart';
import 'state/settings_controller.dart';
import 'state/watchlist_controller.dart';
import 'theme/app_theme.dart';
import 'ui/screens/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureDatabaseFactory();
  final preferences = await SharedPreferences.getInstance();

  final router = DigestRouter();
  final notifier = LocalNotifier(
    onTapPayload: (payload) {
      if (payload == DigestService.tapPayload) router.requestSevenDayList();
    },
  );
  // None of this is worth failing to start over: a desktop with no
  // notification daemon, or a platform the scheduler does not cover, should
  // still get the app.
  try {
    await DigestScheduler.initialise();

    // Only where a tap can actually reach the app: initialising the plugin
    // opens a connection the desktop does not need until something is posted,
    // and the digest is built lazily there anyway.
    if (LocalNotifier.supportsLaunchDetails) {
      await notifier.initialise();
      // The app may have been started by tapping the digest itself, which
      // arrives as a launch detail rather than through the tap callback.
      if (await notifier.launchPayload() == DigestService.tapPayload) {
        router.requestSevenDayList();
      }
    }
  } on Object catch (error) {
    debugPrint('Notifications unavailable: $error');
  }

  runApp(
    ScreenerApp(preferences: preferences, notifier: notifier, router: router),
  );
}

class ScreenerApp extends StatelessWidget {
  const ScreenerApp({
    super.key,
    required this.preferences,
    this.syncService,
    this.notifier,
    this.router,
  });

  final SharedPreferences preferences;

  /// Overrides the S3 client, so tests can drive the app without network.
  final DbSyncService? syncService;

  /// Overrides the notification plugin, so tests can assert what would be
  /// posted without a notification daemon.
  final Notifier? notifier;

  final DigestRouter? router;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<DbSyncService>(
          create: (_) => syncService ?? DbSyncService(preferences: preferences),
          dispose: (_, service) => service.dispose(),
        ),
        Provider<Notifier>(create: (_) => notifier ?? LocalNotifier()),
        ChangeNotifierProvider(create: (_) => router ?? DigestRouter()),
        ChangeNotifierProvider(create: (_) => SettingsController(preferences)),
        ChangeNotifierProvider(create: (_) => WatchlistController(preferences)),
        Provider<DigestService>(
          create: (context) => DigestService(
            preferences: preferences,
            sync: context.read<DbSyncService>(),
            notifier: context.read<Notifier>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) =>
              AppState(syncService: context.read<DbSyncService>())
                ..initialise(),
        ),
      ],
      child: Consumer<SettingsController>(
        builder: (context, settings, _) {
          return MaterialApp(
            title: 'Stocks Analysis',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: settings.themeMode,
            // Selection is per screen, not app-wide. One SelectionArea over
            // the whole navigator crashes the framework when routes come and
            // go under it — the selectable set changes mid-frame and the
            // selection machinery asks a paragraph for boxes before it has
            // been laid out (flutter/flutter#117527, #125065, #152230). The
            // screens where copying text matters wrap themselves instead.
            home: const _DigestOnLaunch(child: AppShell()),
          );
        },
      ),
    );
  }
}

/// Checks the 7-day screen when the app is opened.
///
/// On Android the scheduled refreshes normally get there first; this covers
/// the day the phone was off at nine, and it is the only path on desktop,
/// where nothing wakes the app on a schedule.
class _DigestOnLaunch extends StatefulWidget {
  const _DigestOnLaunch({required this.child});

  final Widget child;

  @override
  State<_DigestOnLaunch> createState() => _DigestOnLaunchState();
}

class _DigestOnLaunchState extends State<_DigestOnLaunch> {
  bool _ran = false;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final settings = context.watch<SettingsController>();

    // Only once the files are open: a comparison run mid-download would be
    // against yesterday's rows, and would then be recorded as the baseline.
    if (!_ran &&
        settings.digestEnabled &&
        appState.allReady &&
        !appState.anyBusy) {
      _ran = true;
      final digest = context.read<DigestService>();
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // An alert that cannot be posted must not take the app down with it.
        // The files were just synced by AppState, so this only compares.
        try {
          await digest.notifyNewcomers();
        } on Object catch (error) {
          debugPrint('Alerts not sent: $error');
        }
      });
    }

    return widget.child;
  }
}
