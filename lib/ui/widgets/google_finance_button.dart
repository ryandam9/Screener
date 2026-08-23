import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_theme.dart';

/// Opens [url] in the platform browser, and says so when that is not possible.
///
/// url_launcher signals failure two different ways depending on the platform
/// and the reason: it can return false, or it can throw a PlatformException
/// (which is what happens when no application is registered for https at all).
/// Only checking the return value leaves the tap doing nothing at all, so both
/// are handled here, and the URL can still be copied when it cannot be opened.
Future<void> openExternalUrl(BuildContext context, String? url) async {
  final messenger = ScaffoldMessenger.of(context);
  final uri = url == null ? null : Uri.tryParse(url);

  if (uri == null) {
    messenger.showSnackBar(
      const SnackBar(content: Text('This row has no link published')),
    );
    return;
  }

  var launched = false;
  try {
    launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Object {
    launched = false;
  }
  if (launched) return;

  messenger.showSnackBar(
    SnackBar(
      content: const Text('Could not open the link'),
      action: SnackBarAction(
        label: 'Copy',
        onPressed: () => Clipboard.setData(ClipboardData(text: url!)),
      ),
    ),
  );
}

/// One-tap access to the Google Finance page the pipeline published with a row.
///
/// The link used to live behind the detail screen's overflow menu, which meant
/// four taps from a list. It is a button now, wherever a row is shown.
class GoogleFinanceButton extends StatelessWidget {
  const GoogleFinanceButton({
    super.key,
    required this.url,
    required this.ticker,
    this.dense = false,
  });

  final String? url;
  final String ticker;

  /// Tighter, for list rows; the full size is for the detail header.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final size = dense ? 26.0 : 40.0;

    return Tooltip(
      message: '$ticker on Google Finance',
      child: SizedBox(
        width: size,
        height: size,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => openExternalUrl(context, url),
            child: Icon(
              Icons.open_in_new,
              size: dense ? 15 : 20,
              color: dense ? colors.textTertiary : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
