import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// A quiet monogram leaves the row’s price movement as the visual signal.
class TickerAvatar extends StatelessWidget {
  const TickerAvatar({super.key, required this.ticker, this.size = 38});

  final String ticker;
  final double size;

  String get _initials {
    final cleaned = ticker.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (cleaned.isEmpty) return '?';
    return cleaned.substring(0, cleaned.length >= 2 ? 2 : 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.neutralSurface,
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Text(
        _initials,
        style: TextStyle(
          fontSize: size * 0.34,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: colors.textSecondary,
        ),
      ),
    );
  }
}
