import 'package:flutter/material.dart';

/// The round monogram shown next to each ticker.
///
/// Colour is derived from the ticker so a symbol keeps the same badge
/// everywhere in the app.
class TickerAvatar extends StatelessWidget {
  const TickerAvatar({super.key, required this.ticker, this.size = 38});

  final String ticker;
  final double size;

  static const _palette = <(Color, Color)>[
    (Color(0xFF1F6F5C), Color(0xFFD9EFE8)),
    (Color(0xFF2C5AA0), Color(0xFFDDE7F7)),
    (Color(0xFF8A5A2B), Color(0xFFF6E7D5)),
    (Color(0xFF6A4C93), Color(0xFFEBE2F6)),
    (Color(0xFF9C2C4E), Color(0xFFF8DFE6)),
    (Color(0xFF2F6E8F), Color(0xFFDCECF4)),
    (Color(0xFF4B6043), Color(0xFFE4EDDE)),
    (Color(0xFF3D4451), Color(0xFFE4E7EC)),
  ];

  (Color, Color) get _colors {
    if (ticker.isEmpty) return _palette.last;
    var hash = 0;
    for (final unit in ticker.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return _palette[hash % _palette.length];
  }

  String get _initials {
    final cleaned = ticker.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (cleaned.isEmpty) return '?';
    return cleaned.substring(0, cleaned.length >= 2 ? 2 : 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final (foreground, background) = _colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isDark ? foreground.withValues(alpha: 0.28) : background,
        shape: BoxShape.circle,
      ),
      child: Text(
        _initials,
        style: TextStyle(
          fontSize: size * 0.34,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: isDark ? background : foreground,
        ),
      ),
    );
  }
}
