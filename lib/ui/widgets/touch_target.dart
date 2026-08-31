import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// How wide a dense list action's tap target is.
///
/// 26 is the icon's own footprint, and enough for a mouse pointer that lands
/// where it is aimed. A finger does not: Material and the iOS guidelines both
/// ask for 44, and a miss here does not do nothing — it hits the row beneath
/// and opens a screen the reader did not ask for.
///
/// Only the target grows. The icons stay at their drawn size, so a desktop
/// row looks exactly as it did.
double denseActionSize(BuildContext context) => switch (defaultTargetPlatform) {
  TargetPlatform.android || TargetPlatform.iOS => 44,
  _ => 26,
};
