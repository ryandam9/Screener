import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/db_sync_service.dart';
import 'data/sqlite_platform.dart';
import 'state/app_state.dart';
import 'state/settings_controller.dart';
import 'state/watchlist_controller.dart';
import 'theme/app_theme.dart';
import 'ui/screens/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureDatabaseFactory();
  final preferences = await SharedPreferences.getInstance();
  runApp(ScreenerApp(preferences: preferences));
}

class ScreenerApp extends StatelessWidget {
  const ScreenerApp({super.key, required this.preferences, this.syncService});

  final SharedPreferences preferences;

  /// Overrides the S3 client, so tests can drive the app without network.
  final DbSyncService? syncService;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<DbSyncService>(
          create: (_) => syncService ?? DbSyncService(preferences: preferences),
          dispose: (_, service) => service.dispose(),
        ),
        ChangeNotifierProvider(create: (_) => SettingsController(preferences)),
        ChangeNotifierProvider(create: (_) => WatchlistController(preferences)),
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
            home: const AppShell(),
          );
        },
      ),
    );
  }
}
