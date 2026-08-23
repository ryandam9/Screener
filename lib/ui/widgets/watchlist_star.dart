import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/market.dart';
import '../../state/watchlist_controller.dart';
import '../../theme/app_theme.dart';

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
    final size = dense ? 26.0 : 40.0;

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
