import 'package:flutter/material.dart';

import '../../models/facets.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';

/// What a fund holds, as a chip: `Crypto`, `Precious Metals`, `Fixed Income`.
///
/// Coloured by the category rather than at random, so the same category is the
/// same colour in every list. That is the whole point of the chip — a
/// screenful of rows can be read for what kind of thing moved without reading
/// a single name.
///
/// Only the ASX file labels its rows, so most callers have nothing to draw;
/// [maybe] returns null for them rather than making every call site repeat the
/// same check.
class CategoryChip extends StatelessWidget {
  const CategoryChip({super.key, required this.category, this.dense = false});

  final String category;

  /// Matches the tighter type of a dense list row.
  final bool dense;

  /// The chip for [category], or null when there is nothing to show.
  static Widget? maybe(String? category, {bool dense = false}) {
    if (category == null || category.isEmpty) return null;
    return CategoryChip(category: category, dense: dense);
  }

  /// Foreground and background, in that order.
  ///
  /// Deliberately not a rainbow: six hues, distinct at chip size and in both
  /// themes, assigned by name so a category keeps its colour as lists are
  /// sorted and filtered.
  static const _palette = <(Color, Color)>[
    (Color(0xFF1F6F5C), Color(0xFFD9EFE8)),
    (Color(0xFF2C5AA0), Color(0xFFDDE7F7)),
    (Color(0xFF8A5A2B), Color(0xFFF6E7D5)),
    (Color(0xFF6A4C93), Color(0xFFEBE2F6)),
    (Color(0xFF9C2C4E), Color(0xFFF8DFE6)),
    (Color(0xFF2F6E8F), Color(0xFFDCECF4)),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // The catch-all is the one category that means "no category", so it reads
    // as the absence of a colour rather than as a sixth kind of fund.
    final (foreground, background) = category == kMiscLabel
        ? (colors.neutral, colors.neutralSurface)
        : _colorsFor(category);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 8,
        vertical: dense ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: category == kMiscLabel
            ? background
            : (isDark ? foreground.withValues(alpha: 0.3) : background),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        Fmt.titleCase(category),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: dense ? 10 : 11,
          fontWeight: FontWeight.w600,
          color: isDark && category != kMiscLabel
              ? Color.lerp(foreground, Colors.white, 0.55)
              : foreground,
        ),
      ),
    );
  }

  /// Hashed by name rather than by position in a list: the set of categories
  /// the pipeline publishes has already grown twice, and a positional palette
  /// would recolour every existing chip when it grows again.
  static (Color, Color) _colorsFor(String category) {
    var hash = 0;
    for (final unit in category.toLowerCase().codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return _palette[hash % _palette.length];
  }
}
