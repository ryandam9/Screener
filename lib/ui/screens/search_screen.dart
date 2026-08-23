import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/market_database.dart';
import '../../models/market.dart';
import '../../models/stock_row.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/panels.dart';
import '../widgets/stock_tile.dart';
import 'stock_detail_screen.dart';
import '../info/page_info.dart';
import '../widgets/info_dialog.dart';

/// Search across both markets at once.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  String _term = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      if (mounted) setState(() => _term = value.trim());
    });
  }

  Future<List<StockRow>> _search(AppState appState) async {
    if (_term.isEmpty) return const [];
    final results = <StockRow>[];
    for (final market in Market.values) {
      final database = appState.databaseOf(market);
      if (database == null) continue;
      final window = database.availableWindows.contains(appState.selectedWindow)
          ? appState.selectedWindow
          : (database.availableWindows.isEmpty
                ? null
                : database.availableWindows.first);
      if (window == null) continue;
      results.addAll(
        await database.stocks(window, StockQuery(search: _term, limit: 40)),
      );
    }
    results.sort((a, b) {
      // Exact ticker matches first, then by size of the move.
      final upper = _term.toUpperCase();
      final aExact = a.ticker.toUpperCase() == upper ? 0 : 1;
      final bExact = b.ticker.toUpperCase() == upper ? 0 : 1;
      if (aExact != bExact) return aExact.compareTo(bExact);
      return b.pctChange.compareTo(a.pctChange);
    });
    return results;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final colors = context.colors;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search ticker or company',
            isDense: true,
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _controller.clear();
                      setState(() => _term = '');
                    },
                  ),
          ),
          onChanged: _onChanged,
        ),
        actions: const [
          InfoButton(info: PageInfos.search),
          SizedBox(width: 8),
        ],
      ),
      body: _term.isEmpty
          ? StatusView(
              icon: Icons.search,
              title: 'Search both markets',
              message:
                  'Matches on ticker and company name in the '
                  '${appState.selectedWindow.longLabel.toLowerCase()} window.',
            )
          : FutureBuilder<List<StockRow>>(
              future: _search(appState),
              builder: (context, snapshot) {
                final rows = snapshot.data;
                if (rows == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (rows.isEmpty) {
                  return StatusView(
                    icon: Icons.search_off,
                    title: 'No matches for "$_term"',
                    message:
                        'The screener only publishes instruments that met its '
                        'growth threshold in this run.',
                  );
                }
                return ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (context, _) =>
                      Divider(height: 1, color: colors.divider, indent: 66),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return StockTile(
                      row: row,
                      showMarketBadge: true,
                      opensTo: (_) => StockDetailScreen(
                        market: row.market,
                        ticker: row.ticker,
                        initialWindow: row.window,
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
