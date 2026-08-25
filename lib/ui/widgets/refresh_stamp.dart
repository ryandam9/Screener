import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';

/// When the data on screen was produced.
///
/// The run's own stamp, from `run_metadata` — not when this device downloaded
/// the file. The two are different questions, and only one of them says
/// whether the figures are today's: a file can be fetched five times a day and
/// still describe yesterday's prices. The download time stays available in the
/// tooltip, where it answers "did my copy fail to update".
///
/// Per market, because the two runs are independent: on the day this was
/// written the ASX file finished at 08:00 UTC with prices as of the 25th,
/// while the US file finished at 00:41 UTC with prices as of the 24th.
class RefreshStamp extends StatelessWidget {
  const RefreshStamp({
    super.key,
    required this.state,
    this.dense = false,
  });

  final MarketState state;

  /// Tighter type, for the handset's smaller cards.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final published = state.publishedAt?.toLocal();
    final downloaded = state.asset?.syncedAt;

    final (Color, String) status;
    if (state.isBusy) {
      status = (colors.neutral, 'Refreshing…');
    } else if (downloaded == null) {
      status = (colors.textTertiary, 'Not downloaded yet');
    } else if (published == null) {
      // An older file with no run stamp at all: the download time is the only
      // date there is, and it is labelled as what it is.
      status = (
        colors.textTertiary,
        'Downloaded ${Fmt.relativeStamp(downloaded)}',
      );
    } else if (state.usingCache) {
      // The figures are real, but the last check failed, so nothing here can
      // promise they are the newest published.
      status = (colors.warning, 'Cached · ${Fmt.relativeStamp(published)}');
    } else {
      status = (colors.positive, 'Refreshed ${Fmt.relativeStamp(published)}');
    }
    final (tint, label) = status;

    final stamp = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: dense ? 10.5 : 11.5,
              color: colors.textTertiary,
            ),
          ),
        ),
      ],
    );

    final detail = [
      if (state.dataAsOf case final asOf?) 'Prices as of ${Fmt.date(asOf)}',
      if (published != null) 'Run finished ${Fmt.dateTime(published)}',
      if (downloaded != null)
        'Downloaded to this device ${Fmt.dateTime(downloaded)}',
      if (state.usingCache) 'The last check for a newer file failed',
    ].join('\n');

    return detail.isEmpty ? stamp : Tooltip(message: detail, child: stamp);
  }
}
