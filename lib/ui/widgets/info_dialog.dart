import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// One piece of an info sheet.
///
/// The screens describe their help as data rather than widgets, so every sheet
/// in the app is laid out, spaced and coloured by the same code.
sealed class InfoBlock {
  const InfoBlock();
}

/// A section heading, optionally with an icon beside it.
class InfoHeading extends InfoBlock {
  const InfoHeading(this.text, {this.icon});

  final String text;
  final IconData? icon;
}

/// A paragraph of running text.
class InfoParagraph extends InfoBlock {
  const InfoParagraph(this.text);

  final String text;
}

/// A bulleted list. Each entry may be `('Lead-in', 'the rest')` or plain text.
class InfoBullets extends InfoBlock {
  const InfoBullets(this.items, {this.icon = Icons.circle});

  final List<InfoBullet> items;
  final IconData icon;
}

class InfoBullet {
  const InfoBullet({required this.text, this.lead});

  /// Bold lead-in, e.g. the name of the thing being explained.
  final String? lead;
  final String text;
}

/// A worked example, set apart from the explanation around it.
class InfoExample extends InfoBlock {
  const InfoExample({required this.title, required this.lines});

  final String title;
  final List<String> lines;
}

/// A caveat worth not missing.
class InfoNote extends InfoBlock {
  const InfoNote(this.text, {this.icon = Icons.info_outline});

  final String text;
  final IconData icon;
}

/// A horizontal rule between two parts of a sheet.
class InfoDivider extends InfoBlock {
  const InfoDivider();
}

/// Everything one screen's info button has to say.
class PageInfo {
  const PageInfo({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.blocks,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<InfoBlock> blocks;
}

/// Opens [info] as a dialog, fading and scaling in.
Future<void> showPageInfo(BuildContext context, PageInfo info) {
  return showModal<void>(
    context: context,
    configuration: const FadeScaleTransitionConfiguration(
      transitionDuration: Duration(milliseconds: 220),
      reverseTransitionDuration: Duration(milliseconds: 160),
    ),
    builder: (context) => InfoDialog(info: info),
  );
}

/// The info sheet itself: a header, the scrollable body, and a close button.
class InfoDialog extends StatelessWidget {
  const InfoDialog({super.key, required this.info});

  final PageInfo info;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final media = MediaQuery.of(context);
    // Wide enough to read comfortably, never taller than the window.
    final width = media.size.width.clamp(0.0, 560.0);
    final maxHeight = media.size.height * 0.86;

    return Dialog(
      backgroundColor: colors.card,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      // Its own selection area: the sheets explain the data and get quoted.
      child: SelectionArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width, maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Header(info: info),
              Divider(height: 1, color: colors.divider),
              Flexible(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  shrinkWrap: true,
                  children: [
                    for (final block in info.blocks) _BlockView(block: block),
                  ],
                ),
              ),
              Divider(height: 1, color: colors.divider),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.info});

  final PageInfo info;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.positiveSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(info.icon, size: 21, color: colors.positive),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  info.title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  info.subtitle,
                  style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close, size: 20),
            color: colors.textTertiary,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _BlockView extends StatelessWidget {
  const _BlockView({required this.block});

  final InfoBlock block;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    switch (block) {
      case InfoHeading(:final text, :final icon):
        return Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 17, color: colors.positive),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        );

      case InfoParagraph(:final text):
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.55,
              color: colors.textSecondary,
            ),
          ),
        );

      case InfoBullets(:final items, :final icon):
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 6, right: 10),
                        child: Icon(
                          icon,
                          size: icon == Icons.circle ? 6 : 15,
                          color: colors.positive,
                        ),
                      ),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              if (item.lead != null)
                                TextSpan(
                                  text: '${item.lead} — ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: colors.textPrimary,
                                  ),
                                ),
                              TextSpan(text: item.text),
                            ],
                          ),
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.5,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );

      case InfoExample(:final title, :final lines):
        return Container(
          margin: const EdgeInsets.only(top: 4, bottom: 12),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
          decoration: BoxDecoration(
            color: colors.pageBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    size: 15,
                    color: colors.textTertiary,
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.1,
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    line,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: colors.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
            ],
          ),
        );

      case InfoNote(:final text, :final icon):
        return Container(
          margin: const EdgeInsets.only(top: 6, bottom: 10),
          padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
          decoration: BoxDecoration(
            color: colors.warningSurface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: colors.warning),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: colors.warning,
                  ),
                ),
              ),
            ],
          ),
        );

      case InfoDivider():
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Divider(height: 1, color: colors.divider),
        );
    }
  }
}

/// The button that opens a screen's info sheet. Lives in the app bar.
class InfoButton extends StatelessWidget {
  const InfoButton({super.key, required this.info, this.dense = false});

  final PageInfo info;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'About this page',
      icon: Icon(Icons.info_outline, size: dense ? 19 : 22),
      onPressed: () => showPageInfo(context, info),
    );
  }
}
