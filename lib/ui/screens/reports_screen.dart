import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/csv_export.dart';
import '../../data/market_database.dart';
import '../../models/growth_window.dart';
import '../../models/market.dart';
import '../../models/run_details.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../widgets/panels.dart';
import '../widgets/run_panels.dart';
import '../info/page_info.dart';
import '../widgets/info_dialog.dart';

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

/// Everything Reports shows for one market: its window inventory and, when the
/// file publishes them, the run metadata and screen funnel behind it.
class _MarketReport {
  const _MarketReport({
    required this.market,
    required this.runs,
    required this.metadata,
    required this.funnel,
  });

  final Market market;
  final List<RunInfo> runs;
  final RunMetadata? metadata;
  final List<FunnelStage> funnel;
}

class _ReportsScreenState extends State<ReportsScreen> {
  Future<List<_MarketReport>>? _future;
  String _signature = '';
  String? _exporting;

  Future<List<_MarketReport>> _load(AppState appState) async {
    final reports = <_MarketReport>[];
    for (final market in Market.values) {
      final database = appState.databaseOf(market);
      if (database == null) continue;
      reports.add(
        _MarketReport(
          market: market,
          runs: await database.allRuns(),
          metadata: await database.runMetadata(),
          funnel: await database.screenFunnel(),
        ),
      );
    }
    return reports;
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
      appBar: AppBar(
        title: const Text('Reports'),
        actions: const [
          InfoButton(info: PageInfos.reports),
          SizedBox(width: 4),
        ],
      ),
      // Its own selection area, not the app's: the run ids and stamps here
      // are meant to be copied, and a selection that spans routes is what
      // crashes the framework.
      body: SelectionArea(
        child: FutureBuilder<List<_MarketReport>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return StatusView(
                icon: Icons.error_outline,
                title: 'Could not read the run metadata',
                message: '${snapshot.error}',
              );
            }
            final reports = snapshot.data;
            if (reports == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (reports.isEmpty || reports.every((r) => r.runs.isEmpty)) {
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
                for (final report in reports) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 6, 2, 10),
                    child: Text(
                      '${report.market.label} — ${report.market.objectKey}',
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
                        for (final run in report.runs) ...[
                          _RunTile(
                            run: run,
                            busy:
                                _exporting ==
                                '${report.market.id}-${run.window.name}',
                            onExport: run.rowCount == 0
                                ? null
                                : () => _export(
                                    appState.databaseOf(report.market)!,
                                    run.window,
                                  ),
                          ),
                          if (run != report.runs.last)
                            Divider(
                              height: 1,
                              color: colors.divider,
                              indent: 16,
                            ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _Provenance(report: report),
                  const SizedBox(height: 22),
                ],
                Text(
                  'CSV exports carry every published column, unchanged.',
                  style: TextStyle(fontSize: 11.5, color: colors.textTertiary),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The run metadata and screen funnel for one market, side by side where the
/// window is wide enough to read them together.
class _Provenance extends StatelessWidget {
  const _Provenance({required this.report});

  final _MarketReport report;

  @override
  Widget build(BuildContext context) {
    final metadata = report.metadata;
    final funnel = report.funnel;

    if (metadata == null && funnel.isEmpty) {
      return _MissingNote(market: report.market);
    }

    final panels = <Widget>[
      if (metadata != null) RunMetadataPanel(metadata: metadata),
      if (funnel.isNotEmpty) ScreenFunnelPanel(stages: funnel),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (panels.length < 2 || constraints.maxWidth < 780) {
          return Column(
            children: [
              for (var i = 0; i < panels.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                panels[i],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: panels[0]),
            const SizedBox(width: 12),
            Expanded(child: panels[1]),
          ],
        );
      },
    );
  }
}

/// Older files carry no `run_metadata` or `screen_funnel`, and saying so beats
/// leaving a gap where the other market has two panels.
class _MissingNote extends StatelessWidget {
  const _MissingNote({required this.market});

  final Market market;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 15, color: colors.textTertiary),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            'This ${market.objectKey} publishes no run metadata or screen '
            'funnel — the windows above are all it records about its run.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: colors.textTertiary,
            ),
          ),
        ),
      ],
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
                fontWeight: FontWeight.w600,
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
