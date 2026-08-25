import 'package:flutter/material.dart';

import '../../data/db_sync_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';

/// When this market's file was last downloaded.
///
/// Per file rather than per app: the two are fetched independently, and one
/// can be a day behind the other when a publish fails or a download is
/// interrupted. The dashboard is where that has to be visible — it is the
/// screen that answers "is what I am looking at current".
class RefreshStamp extends StatelessWidget {
  const RefreshStamp({
    super.key,
    required this.asset,
    this.busy = false,
    this.fromCache = false,
    this.dense = false,
  });

  /// The downloaded file, or null when nothing has been fetched yet.
  final DbAsset? asset;

  /// A download is running right now.
  final bool busy;

  /// The app is serving the cached copy because the last refresh failed.
  final bool fromCache;

  /// Tighter type, for the handset's smaller cards.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final stamp = asset?.syncedAt;

    final (Color, String) status;
    if (busy) {
      status = (colors.neutral, 'Refreshing…');
    } else if (stamp == null) {
      status = (colors.textTertiary, 'Not downloaded yet');
    } else if (fromCache) {
      // "Cached" earns the warning colour: the figures are real, but they are
      // not today's, and the difference matters on a screener.
      status = (colors.warning, 'Cached · ${Fmt.relativeStamp(stamp)}');
    } else {
      status = (colors.positive, 'Refreshed ${Fmt.relativeStamp(stamp)}');
    }
    final (tint, label) = status;

    return Row(
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
  }
}
