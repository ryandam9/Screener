import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/db_sync_service.dart';
import '../../models/market.dart';
import '../../state/app_state.dart';
import '../../state/settings_controller.dart';
import '../../state/watchlist_controller.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../widgets/panels.dart';
import 'reports_screen.dart';

/// Data source status, cache controls and appearance settings.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final settings = context.watch<SettingsController>();
    final watchlist = context.watch<WatchlistController>();
    final sync = context.read<DbSyncService>();
    final colors = context.colors;

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          const SectionHeader(
            title: 'Data sources',
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          ),
          Panel(
            child: Column(
              children: [
                for (final market in Market.values) ...[
                  _MarketStatusTile(market: market),
                  if (market != Market.values.last)
                    Divider(height: 1, color: colors.divider, indent: 16),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: appState.anyBusy
                        ? null
                        : () => appState.refreshAll(force: true),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Re-download'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: appState.anyBusy
                        ? null
                        : () => _clearCache(context, appState, sync),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Clear cache'),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'Bucket: ${sync.baseUrl}',
              style: TextStyle(fontSize: 11.5, color: colors.textTertiary),
            ),
          ),
          const SectionHeader(title: 'Appearance'),
          Panel(
            child: Column(
              children: [
                ListTile(
                  title: const Text('Theme'),
                  subtitle: Text(switch (settings.themeMode) {
                    ThemeMode.light => 'Always light',
                    ThemeMode.dark => 'Always dark',
                    ThemeMode.system => 'Follow system',
                  }),
                  trailing: SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode_outlined, size: 18),
                      ),
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.brightness_auto_outlined, size: 18),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode_outlined, size: 18),
                      ),
                    ],
                    selected: {settings.themeMode},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) =>
                        settings.setThemeMode(selection.first),
                  ),
                ),
                Divider(height: 1, color: colors.divider, indent: 16),
                SwitchListTile(
                  value: settings.compactRows,
                  title: const Text('Compact rows'),
                  subtitle: const Text('Fit more instruments on screen'),
                  onChanged: settings.setCompactRows,
                ),
              ],
            ),
          ),
          const SectionHeader(title: 'Reports'),
          Panel(
            child: ListTile(
              leading: Icon(Icons.description_outlined, color: colors.positive),
              title: const Text('Runs and CSV export'),
              subtitle: const Text('Every published run, exportable as CSV'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ReportsScreen()),
              ),
            ),
          ),
          const SectionHeader(title: 'Watchlist'),
          Panel(
            child: ListTile(
              title: const Text('Starred tickers'),
              subtitle: Text(
                watchlist.isEmpty
                    ? 'Nothing starred yet'
                    : '${watchlist.countFor(Market.asx)} ASX · '
                          '${watchlist.countFor(Market.us)} US',
              ),
              trailing: watchlist.isEmpty
                  ? null
                  : TextButton(
                      onPressed: watchlist.clear,
                      child: const Text('Clear'),
                    ),
            ),
          ),
          const SectionHeader(title: 'About'),
          Panel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stocks Analysis',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Reads the growth-screener SQLite databases published to '
                  's3://hive-in-the-cloud and renders them on device. Files are '
                  'cached locally, so everything except the refresh works '
                  'without a connection.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Figures are screener output — window endpoints, not live '
                  'quotes — and are not investment advice.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _clearCache(
    BuildContext context,
    AppState appState,
    DbSyncService sync,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear cached databases?'),
        content: const Text(
          'Both files are deleted and downloaded again. The app will not work '
          'offline until the download finishes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;
    for (final market in Market.values) {
      await sync.deleteCache(market);
    }
    await appState.refreshAll(force: true);
  }
}

class _MarketStatusTile extends StatelessWidget {
  const _MarketStatusTile({required this.market});

  final Market market;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final colors = context.colors;
    final state = appState.stateOf(market);
    final asset = state.asset;

    final (icon, tint, status) = switch (state.phase) {
      SyncPhase.ready when state.usingCache => (
        Icons.cloud_off,
        colors.warning,
        'Cached copy',
      ),
      SyncPhase.ready => (Icons.check_circle, colors.positive, 'Up to date'),
      SyncPhase.error => (Icons.error_outline, colors.negative, 'Failed'),
      SyncPhase.downloading => (
        Icons.downloading,
        colors.neutral,
        'Downloading',
      ),
      _ => (Icons.sync, colors.neutral, 'Checking'),
    };

    return ListTile(
      leading: Icon(icon, color: tint),
      title: Text('${market.label} — ${market.objectKey}'),
      subtitle: Text(
        [
          status,
          if (asset != null) Fmt.bytes(asset.sizeBytes),
          if (asset != null) 'synced ${Fmt.relativeStamp(asset.syncedAt)}',
          if (state.error != null) state.error!,
        ].join(' · '),
        maxLines: 3,
      ),
      trailing: IconButton(
        tooltip: 'Refresh',
        icon: const Icon(Icons.refresh),
        onPressed: state.isBusy
            ? null
            : () => appState.refresh(market, force: true),
      ),
    );
  }
}
