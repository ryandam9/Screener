import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

enum AppNotificationKind { marketAlert, watchlistAlert, dataHealth, sample }

enum NotificationPermissionStatus { enabled, blocked, unsupported }

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
    this.kind = AppNotificationKind.marketAlert,
    this.silent = false,
    this.actionLabel,
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

  /// Selects a user-controllable Android channel. Channel ids are versioned:
  /// Android freezes a channel's behaviour after it is created.
  final AppNotificationKind kind;

  /// Useful for watchlist children: the consolidated digest makes the sound,
  /// while direct links add detail without making the phone chime repeatedly.
  final bool silent;

  /// Optional foreground action. The body itself remains tappable too.
  final String? actionLabel;
}

/// Posts notifications, and says whether it is allowed to.
///
/// An interface rather than the plugin directly: the digest logic is worth
/// testing, and a widget test cannot post a system notification.
abstract class Notifier {
  /// True when notifications can actually be shown — permission granted and
  /// the platform supported.
  Future<bool> ensurePermission();

  Future<NotificationPermissionStatus> permissionStatus();

  /// Opens this app's notification controls when the platform exposes them.
  Future<bool> openSettings();

  Future<void> show(AppNotification notification);

  Future<void> cancelAll();
}

/// Ids are fixed per kind of notification, so a new digest replaces the one
/// from yesterday rather than stacking up in the shade.
class NotificationIds {
  const NotificationIds._();

  static const digest = 1;
  static const test = 2;
  static const dataHealth = 3;

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

  static const _smallIcon = 'ic_stat_screener';

  Future<void> initialise() async {
    if (_initialised) return;
    _initialised = true;

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(_smallIcon),
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
  Future<NotificationPermissionStatus> permissionStatus() async {
    await initialise();
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return (await android?.areNotificationsEnabled() ?? true)
          ? NotificationPermissionStatus.enabled
          : NotificationPermissionStatus.blocked;
    }
    if (defaultTargetPlatform == TargetPlatform.linux) {
      return NotificationPermissionStatus.enabled;
    }
    return NotificationPermissionStatus.unsupported;
  }

  @override
  Future<bool> openSettings() async {
    await initialise();
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return false;
    return await android.openAppNotificationSettings() ?? false;
  }

  @override
  Future<void> show(AppNotification notification) async {
    await initialise();
    final channel = _channelFor(notification.kind);
    await _plugin.show(
      id: notification.id,
      title: notification.title,
      body: notification.body,
      payload: notification.payload,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          icon: _smallIcon,
          importance: channel.importance,
          priority: channel.priority,
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
          groupAlertBehavior: notification.group == null
              ? GroupAlertBehavior.all
              : GroupAlertBehavior.summary,
          silent: notification.silent,
          onlyAlertOnce: notification.isGroupSummary,
          category: AndroidNotificationCategory.recommendation,
          actions: notification.actionLabel == null
              ? const []
              : [
                  AndroidNotificationAction(
                    'open',
                    notification.actionLabel!,
                    showsUserInterface: true,
                  ),
                ],
        ),
        linux: const LinuxNotificationDetails(),
      ),
    );
  }

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  static _AndroidChannel _channelFor(AppNotificationKind kind) =>
      switch (kind) {
        AppNotificationKind.marketAlert => const _AndroidChannel(
          id: 'market_alerts_v2',
          name: 'Market alerts',
          description: 'Consolidated updates from selected growth screens.',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        AppNotificationKind.watchlistAlert => const _AndroidChannel(
          id: 'watchlist_alerts_v1',
          name: 'Watchlist alerts',
          description: 'Direct alerts for starred tickers entering a screen.',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        AppNotificationKind.dataHealth => const _AndroidChannel(
          id: 'data_health_v1',
          name: 'Data health',
          description: 'Low-priority warnings when market data stays stale.',
          importance: Importance.low,
          priority: Priority.low,
        ),
        AppNotificationKind.sample => const _AndroidChannel(
          id: 'notification_preview_v1',
          name: 'Notification previews',
          description: 'Sample notifications sent from Settings.',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      };
}

class _AndroidChannel {
  const _AndroidChannel({
    required this.id,
    required this.name,
    required this.description,
    required this.importance,
    required this.priority,
  });

  final String id;
  final String name;
  final String description;
  final Importance importance;
  final Priority priority;
}
