import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/csv_export.dart';
import '../../data/market_database.dart';
import '../../models/growth_window.dart';
import '../../models/market.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../widgets/panels.dart';

/// Every published run, with a CSV export per window.
///
/// The desktop layout has room to show the whole run inventory at once, and a
/// file system to export to — so this is where the provenance the other
/// screens only hint at is laid out in full.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Future<List<RunInfo>>? _future;
  String _signature = '';
  String? _exporting;

  Future<List<RunInfo>> _load(AppState appState) async {
    final runs = <RunInfo>[];
    for (final market in Market.values) {
      final database = appState.databaseOf(market);
      if (database == null) continue;
      runs.addAll(await database.allRuns());
    }
    return runs;
  }

  Future<void> _export(MarketDatabase database, GrowthWindow window) async {
    final key = '${database.market.id}-${window.name}';
    setState(() => _exporting = key);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final file = await exportWindowCsv(database, window);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Exported to ${file.path}'),
          duration: const Duration(seconds: 6),
        ),
      );
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $error')));
    } finally {
      if (mounted) setState(() => _exporting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final colors = context.colors;

    final signature = [
      for (final market in Market.values)
        '${market.id}:${appState.stateOf(market).asset?.syncedAt.millisecondsSinceEpoch ?? 0}',
    ].join('|');
    if (signature != _signature) {
      _signature = signature;
      _future = _load(appState);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: FutureBuilder<List<RunInfo>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return StatusView(
              icon: Icons.error_outline,
              title: 'Could not read the run metadata',
              message: '${snapshot.error}',
            );
          }
          final runs = snapshot.data;
          if (runs == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (runs.isEmpty) {
            return StatusView(
              icon: Icons.cloud_off,
              title: 'No runs available',
              message: 'Download the databases to see their runs.',
              actionLabel: 'Download',
              onAction: () => appState.refreshAll(force: true),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              for (final market in Market.values)
                if (appState.databaseOf(market) != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 6, 2, 10),
                    child: Text(
                      '${market.label} — ${market.objectKey}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  Panel(
                    margin: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (final run in runs.where(
                          (r) => r.market == market,
                        )) ...[
                          _RunTile(
                            run: run,
                            busy:
                                _exporting == '${market.id}-${run.window.name}',
                            onExport: run.rowCount == 0
                                ? null
                                : () => _export(
                                    appState.databaseOf(market)!,
                                    run.window,
                                  ),
                          ),
                          if (run != runs.where((r) => r.market == market).last)
                            Divider(
                              height: 1,
                              color: colors.divider,
                              indent: 16,
                            ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              Text(
                'CSV exports carry every published column, unchanged.',
                style: TextStyle(fontSize: 11.5, color: colors.textTertiary),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RunTile extends StatelessWidget {
  const _RunTile({required this.run, required this.busy, this.onExport});

  final RunInfo run;
  final bool busy;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final startedAt = run.runStartedAt;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              run.window.label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  run.rowCount == 0
                      ? 'No rows published'
                      : '${Fmt.integer(run.rowCount)} ${run.market.instrumentNoun}',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'data as of ${Fmt.date(run.dataAsOf)}'
                  '${startedAt == null ? '' : ' · run ${Fmt.relativeStamp(startedAt)}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (run.runId != null)
            Flexible(
              child: Text(
                run.runId!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11, color: colors.textTertiary),
              ),
            ),
          const SizedBox(width: 12),
          SizedBox(
            width: 116,
            child: OutlinedButton.icon(
              onPressed: busy ? null : onExport,
              icon: busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined, size: 16),
              label: Text(busy ? 'Saving…' : 'CSV'),
            ),
          ),
        ],
      ),
    );
  }
}
