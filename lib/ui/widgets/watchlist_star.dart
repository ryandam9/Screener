import 'package:flutter/material.dart';

import 'touch_target.dart';
import 'package:provider/provider.dart';

import '../../models/market.dart';
import '../../state/watchlist_controller.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';

/// Stars a ticker from wherever it is listed.
///
/// The detail screen's star confirms with a snackbar; here the fill is the
/// confirmation. A message per tap would stack up as you work down a list.
class WatchlistStar extends StatelessWidget {
  const WatchlistStar({
    super.key,
    required this.market,
    required this.ticker,
    this.dense = false,
  });

  final Market market;
  final String ticker;

  /// Tighter, for list rows.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final watchlist = context.watch<WatchlistController>();
    final starred = watchlist.contains(market, ticker);
    final size = dense ? denseActionSize(context) : 40.0;

    return Tooltip(
      message: starred
          ? 'Remove $ticker from watchlist'
          : 'Add $ticker to watchlist',
      child: SizedBox(
        width: size,
        height: size,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => watchlist.toggle(market, ticker),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: Icon(
                starred ? Icons.star_rounded : Icons.star_border_rounded,
                key: ValueKey(starred),
                size: dense ? 18 : 24,
                color: starred ? colors.warning : colors.textTertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks before emptying the watchlist, and empties it if told to.
///
/// A star is meant to stay put until it is taken off, so the one control that
/// removes the whole list has to ask first — wherever it is offered. It used
/// to ask on the watchlist screen and not on the settings screen, where a
/// stray tap on "Clear" took every starred ticker with no way back.
Future<void> confirmClearWatchlist(
  BuildContext context,
  WatchlistController watchlist,
) async {
  if (watchlist.isEmpty) return;
  final count = watchlist.length;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Clear watchlist?'),
      content: Text('This removes all ${Fmt.integer(count)} starred tickers.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Clear'),
        ),
      ],
    ),
  );
  if (confirmed ?? false) await watchlist.clear();
}
