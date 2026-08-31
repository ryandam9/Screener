import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/market.dart';
import '../../state/watchlist_controller.dart';
import '../../theme/app_theme.dart';

/// Whether [ticker] is starred, subscribing the caller to later changes.
///
/// Every list that renders a ticker calls this, so a star added on one screen
/// shows up on the rest of them without any of them being told about it.
bool isStarred(BuildContext context, Market market, String ticker) =>
    context.watch<WatchlistController>().contains(market, ticker);

/// The background a list row carries when its ticker is starred, or null.
///
/// The star at the end of a row is a control, not a mark: it is 18px of
/// outline-versus-fill at the far edge, which is not something you can pick
/// out while scanning a screenful of tickers for the ones you follow. The
/// whole row is tinted instead, so a starred ticker reads as starred in the
/// 7-day list, the 30-day list, the price history, and everywhere else it
/// turns up.
///
/// Pass [selected] for lists that also mark the row the detail pane is
/// showing: that is where you are right now, and it wins.
Color? starredRowColor(
  BuildContext context,
  Market market,
  String ticker, {
  bool selected = false,
}) {
  final colors = context.colors;
  if (selected) return colors.interactiveSurface;
  return isStarred(context, market, ticker) ? colors.starredSurface : null;
}
