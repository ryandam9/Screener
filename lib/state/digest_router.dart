import 'package:flutter/foundation.dart';

import '../models/growth_window.dart';
import '../models/market.dart';

enum NotificationDestination { screen, stock, dataSources }

/// A stable, typed destination carried by every notification.
///
/// URI payloads remain readable in Android debugging tools, while parsing in
/// one place prevents every shell from growing its own string conventions.
@immutable
class NotificationRoute {
  const NotificationRoute.screen({this.market, required this.window})
    : destination = NotificationDestination.screen,
      ticker = null;

  const NotificationRoute.stock({
    required this.market,
    required this.ticker,
    this.window = GrowthWindow.sevenDays,
  }) : destination = NotificationDestination.stock;

  const NotificationRoute.dataSources()
    : destination = NotificationDestination.dataSources,
      market = null,
      ticker = null,
      window = null;

  final NotificationDestination destination;
  final Market? market;
  final String? ticker;
  final GrowthWindow? window;

  String toPayload() {
    final query = <String, String>{
      if (market != null) 'market': market!.id,
      if (ticker != null) 'ticker': ticker!,
      if (window != null) 'window': window!.label,
    };
    return Uri(
      scheme: 'screener',
      host: switch (destination) {
        NotificationDestination.screen => 'screen',
        NotificationDestination.stock => 'stock',
        NotificationDestination.dataSources => 'data-sources',
      },
      queryParameters: query.isEmpty ? null : query,
    ).toString();
  }

  static NotificationRoute? tryParse(String? payload) {
    if (payload == null) return null;

    // Keep notifications posted by older app versions useful after upgrade.
    if (payload == 'digest:7d') {
      return const NotificationRoute.screen(window: GrowthWindow.sevenDays);
    }

    final uri = Uri.tryParse(payload);
    if (uri == null || uri.scheme != 'screener') return null;
    final market = Market.fromId(uri.queryParameters['market']);
    final window = GrowthWindow.fromLabel(uri.queryParameters['window']);
    switch (uri.host) {
      case 'screen':
        if (window == null) return null;
        return NotificationRoute.screen(market: market, window: window);
      case 'stock':
        final ticker = uri.queryParameters['ticker']?.trim();
        if (market == null || ticker == null || ticker.isEmpty) return null;
        return NotificationRoute.stock(
          market: market,
          ticker: ticker,
          window: window ?? GrowthWindow.sevenDays,
        );
      case 'data-sources':
        return const NotificationRoute.dataSources();
      default:
        return null;
    }
  }
}

/// A request from outside the widget tree to open notification content.
class DigestRouter extends ChangeNotifier {
  NotificationRoute? _pending;

  NotificationRoute? get pending => _pending;
  bool get hasPendingRoute => _pending != null;

  /// Compatibility for callers interested only in the original digest route.
  bool get showSevenDayList =>
      _pending?.destination == NotificationDestination.screen &&
      _pending?.window == GrowthWindow.sevenDays;

  void request(NotificationRoute route) {
    _pending = route;
    notifyListeners();
  }

  void requestPayload(String? payload) {
    final route = NotificationRoute.tryParse(payload);
    if (route != null) request(route);
  }

  void requestSevenDayList() =>
      request(const NotificationRoute.screen(window: GrowthWindow.sevenDays));

  /// Called by whichever shell acted on the request.
  NotificationRoute? consume() {
    final route = _pending;
    _pending = null;
    return route;
  }
}
