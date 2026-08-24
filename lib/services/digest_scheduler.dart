import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../data/db_sync_service.dart';
import '../data/sqlite_platform.dart';
import 'digest_service.dart';
import 'notifier.dart';

/// Wakes the app once a day to build and post the digest.
///
/// Android runs the work itself through WorkManager, so the notification
/// arrives whether or not the app is open. Everywhere else the platform has no
/// equivalent the app can rely on, and the digest is built on the next launch
/// instead — which is why [DigestService.run] guards on the day rather than on
/// having been woken.
class DigestScheduler {
  const DigestScheduler._();

  static const uniqueName = 'daily-7d-digest';
  static const taskName = 'daily-7d-digest';

  /// True where a scheduled wake-up is actually available.
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// How long from [now] until the next [at], never zero — a delay of zero
  /// would fire the moment the setting is saved.
  static Duration delayUntil(TimeOfDay at, DateTime now) {
    var next = DateTime(now.year, now.month, now.day, at.hour, at.minute);
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    return next.difference(now);
  }

  /// Registers or cancels the daily task to match the current settings.
  static Future<void> configure({
    required bool enabled,
    required TimeOfDay at,
    DateTime? now,
  }) async {
    if (!isSupported) return;

    final manager = Workmanager();
    if (!enabled) {
      await manager.cancelByUniqueName(uniqueName);
      return;
    }

    await manager.registerPeriodicTask(
      uniqueName,
      taskName,
      frequency: const Duration(hours: 24),
      initialDelay: delayUntil(at, now ?? DateTime.now()),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      // The digest needs the morning's files; without a connection the run
      // would only ever re-summarise yesterday's.
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }

  /// Registers the background entry point. Safe to call on every launch.
  static Future<void> initialise() async {
    if (!isSupported) return;
    await Workmanager().initialize(digestCallbackDispatcher);
  }
}

/// The isolate WorkManager starts when the daily task is due.
///
/// Runs without a widget tree, so it builds its own services rather than
/// reading providers. Returning true tells WorkManager the work is done;
/// returning false would have it retried with backoff.
@pragma('vm:entry-point')
void digestCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != DigestScheduler.taskName) return true;

    WidgetsFlutterBinding.ensureInitialized();
    configureDatabaseFactory();

    final preferences = await SharedPreferences.getInstance();
    // Reload rather than trust the snapshot this isolate started with: the UI
    // isolate may have written since.
    await preferences.reload();

    final sync = DbSyncService(preferences: preferences);
    try {
      await DigestService(
        preferences: preferences,
        sync: sync,
        notifier: LocalNotifier(),
      ).run();
    } on Object {
      // A failed digest is not worth a retry storm; tomorrow's run, or the
      // next launch, produces one.
    } finally {
      sync.dispose();
    }
    return true;
  });
}

/// Whether this platform can be asked to wake the app on a schedule.
///
/// Exposed for the settings screen, which explains the difference rather than
/// silently doing nothing on desktop.
bool get platformSchedulesDigest =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);
