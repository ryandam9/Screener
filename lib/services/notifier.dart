import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/market.dart';

/// One notification to post.
@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    this.payload,
    this.group,
    this.isGroupSummary = false,
    this.lines = const [],
    this.summaryText,
  });

  final int id;
  final String title;
  final String body;

  /// Handed back when the notification is tapped, so the app knows where to go.
  final String? payload;

  /// Bundles related notifications, so a run that names six tickers collapses
  /// into one entry in the shade rather than six.
  final String? group;

  /// The entry Android shows when the group is collapsed.
  final bool isGroupSummary;

  /// One line per item, listed under the title when the notification is
  /// expanded. A summary that names six tickers is unreadable as one run-on
  /// sentence; a line each is what the shade is built for.
  ///
  /// Android only. Where the platform has no equivalent, [body] is shown, so
  /// it has to stand on its own.
  final List<String> lines;

  /// The short right-hand note above the lines, e.g. `8 ASX · 153 US`.
  final String? summaryText;
}

/// Posts notifications, and says whether it is allowed to.
///
/// An interface rather than the plugin directly: the digest logic is worth
/// testing, and a widget test cannot post a system notification.
abstract class Notifier {
  /// True when notifications can actually be shown — permission granted and
  /// the platform supported.
  Future<bool> ensurePermission();

  Future<void> show(AppNotification notification);

  Future<void> cancelAll();
}

/// Ids are fixed per kind of notification, so a new digest replaces the one
/// from yesterday rather than stacking up in the shade.
class NotificationIds {
  const NotificationIds._();

  static const digest = 1;
  static const test = 2;

  /// One summary per file, so the screens sit in the shade side by side
  /// rather than replacing one another.
  static int digestFor(Market market) => 100 + market.index;

  /// One notification per refreshed file, replaced rather than stacked.
  static int forFile(Market market) => 10 + market.index;

  /// A stable id per ticker, so re-entering the screen replaces the old alert.
  ///
  /// Deliberately not [String.hashCode], which Dart does not promise to keep
  /// stable across runs of the program.
  static int forTicker(String key) {
    var hash = 0;
    for (final unit in key.codeUnits) {
      hash = (hash * 31 + unit) & 0x3fffff;
    }
    return 1000 + hash;
  }

  /// Android's group key for one file's 7-day alerts.
  ///
  /// A group per market rather than one for both: they are separate screens
  /// over separate universes, and bundling them hides whichever file has
  /// fewer names that day behind the other's.
  static String sevenDayGroupFor(Market market) =>
      'seven_day_screen_${market.id}';
}

/// The real notifier, backed by flutter_local_notifications.
///
/// Android and Linux are the platforms this app ships to; the plugin covers
/// both, and both are initialised here so the background isolate and the UI
/// isolate behave identically.
class LocalNotifier implements Notifier {
  LocalNotifier({FlutterLocalNotificationsPlugin? plugin, this.onTapPayload})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// Called with a notification's payload when the app is brought up by a tap.
  final ValueChanged<String?>? onTapPayload;

  bool _initialised = false;

  /// Whether the platform can report the notification that launched the app.
  ///
  /// Only the mobile embeddings implement it; the Linux plugin throws
  /// [UnimplementedError], and asking it anyway costs a D-Bus connection this
  /// app does not otherwise need at startup.
  static bool get supportsLaunchDetails =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static const _channelId = 'daily_digest';
  static const _channelName = 'Daily digest';
  static const _channelDescription =
      'The morning summary of the 7-day growth screen.';

  Future<void> initialise() async {
    if (_initialised) return;
    _initialised = true;

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        linux: LinuxInitializationSettings(defaultActionName: 'Open'),
      ),
      onDidReceiveNotificationResponse: (response) =>
          onTapPayload?.call(response.payload),
    );
  }

  /// The payload of the notification that launched the app, if any.
  Future<String?> launchPayload() async {
    if (!supportsLaunchDetails) return null;
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp ?? false) {
      return details?.notificationResponse?.payload;
    }
    return null;
  }

  @override
  Future<bool> ensurePermission() async {
    await initialise();
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      // Android 13 and up ask; older releases grant at install time and the
      // call returns null, which is not a refusal.
      return await android?.requestNotificationsPermission() ?? true;
    }
    return true;
  }

  @override
  Future<void> show(AppNotification notification) async {
    await initialise();
    await _plugin.show(
      id: notification.id,
      title: notification.title,
      body: notification.body,
      payload: notification.payload,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          styleInformation: notification.lines.isEmpty
              // The body names a company and its move, over two lines.
              ? BigTextStyleInformation(notification.body)
              : InboxStyleInformation(
                  notification.lines,
                  contentTitle: notification.title,
                  summaryText: notification.summaryText,
                ),
          groupKey: notification.group,
          setAsGroupSummary: notification.isGroupSummary,
        ),
        linux: const LinuxNotificationDetails(),
      ),
    );
  }

  @override
  Future<void> cancelAll() => _plugin.cancelAll();
}
