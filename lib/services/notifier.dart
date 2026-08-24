import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// One notification to post.
@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    this.payload,
  });

  final int id;
  final String title;
  final String body;

  /// Handed back when the notification is tapped, so the app knows where to go.
  final String? payload;
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
          // The body names several tickers and is longer than one line.
          styleInformation: BigTextStyleInformation(notification.body),
        ),
        linux: const LinuxNotificationDetails(),
      ),
    );
  }

  @override
  Future<void> cancelAll() => _plugin.cancelAll();
}
