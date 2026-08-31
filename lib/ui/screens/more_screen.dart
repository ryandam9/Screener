import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/db_sync_service.dart';
import '../../models/market.dart';
import '../../state/app_state.dart';
import '../../state/settings_controller.dart';
import '../../state/watchlist_controller.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../services/digest_scheduler.dart';
import '../../services/notifier.dart';
import '../../services/digest_service.dart';
import '../widgets/panels.dart';
import '../widgets/watchlist_star.dart';
import 'history_screen.dart';
import 'reports_screen.dart';
import '../info/page_info.dart';
import '../widgets/info_dialog.dart';

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

    final sections = <Widget>[
      _Section(
        title: 'Data sources',
        children: [
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
        ],
      ),
      _Section(
        title: 'Appearance',
        children: [
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
        ],
      ),
      const _Section(title: 'Daily digest', children: [_DigestPanel()]),
      _Section(
        title: 'Reports',
        children: [
          Panel(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    Icons.description_outlined,
                    color: colors.interactive,
                  ),
                  title: const Text('Runs and CSV export'),
                  subtitle: const Text(
                    'Every published run, exportable as CSV',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ReportsScreen(),
                    ),
                  ),
                ),
                Divider(height: 1, color: colors.divider, indent: 16),
                ListTile(
                  leading: Icon(
                    Icons.candlestick_chart_outlined,
                    color: colors.interactive,
                  ),
                  title: const Text('Price history'),
                  subtitle: const Text(
                    'Every ticker the run collected, charted',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const HistoryScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      _Section(
        title: 'Watchlist',
        children: [
          Panel(
            child: ListTile(
              title: const Text('Starred tickers'),
              subtitle: Text(
                watchlist.isEmpty
                    ? 'Nothing starred yet'
                    // Only the files that have something starred, so a market
                    // you do not follow does not sit here reading "0".
                    : [
                        for (final market in Market.values)
                          if (watchlist.countFor(market) > 0)
                            '${watchlist.countFor(market)} ${market.label}',
                      ].join(' · '),
              ),
              trailing: watchlist.isEmpty
                  ? null
                  : TextButton(
                      onPressed: () =>
                          confirmClearWatchlist(context, watchlist),
                      child: const Text('Clear'),
                    ),
            ),
          ),
        ],
      ),
      _Section(
        title: 'About',
        children: [
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
    ];

    return Scaffold(
      appBar: AppBar(
        // "More" is the handset tab this screen sits behind; the desktop
        // sidebar calls the same screen Settings, and the title follows it.
        title: Text(
          MediaQuery.sizeOf(context).width < 820 ? 'More' : 'Settings',
        ),
        actions: const [
          InfoButton(info: PageInfos.settings),
          SizedBox(width: 4),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // As many columns as the width can hold without any of them getting
          // narrow: one column of settings on a wide window is mostly empty
          // space, and so is two on a very wide one.
          final columns = constraints.maxWidth >= 1120
              ? 3
              : constraints.maxWidth >= 820
              ? 2
              : 1;
          if (columns == 1) {
            return ListView(
              padding: const EdgeInsets.only(bottom: 28),
              children: sections,
            );
          }

          // Dealt round-robin rather than split by height: the sections are
          // close enough in size that this keeps the columns even, and it
          // keeps Data sources and Appearance at the top of the eye's path.
          final dealt = [
            for (var column = 0; column < columns; column++)
              <Widget>[
                for (var i = column; i < sections.length; i += columns)
                  sections[i],
              ],
          ];

          return SingleChildScrollView(
            padding: const EdgeInsets.only(right: 16, bottom: 28),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final column in dealt)
                  Expanded(child: Column(children: column)),
              ],
            ),
          );
        },
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
          'Every file is deleted and downloaded again. The app will not work '
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

/// A settings section: its heading and the panels under it.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Uniform spacing above every section, so the two columns start their
        // headings on the same line as each other.
        SectionHeader(
          title: title,
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        ),
        ...children,
      ],
    );
  }
}

/// Turns the scheduled refresh and its alerts on, and says what last went out.
class _DigestPanel extends StatefulWidget {
  const _DigestPanel();

  @override
  State<_DigestPanel> createState() => _DigestPanelState();
}

class _DigestPanelState extends State<_DigestPanel> {
  bool _busy = false;

  Future<void> _setEnabled(bool value) async {
    final settings = context.read<SettingsController>();
    final notifier = context.read<Notifier>();
    final messenger = ScaffoldMessenger.of(context);

    if (value) {
      // Asked for at the moment it is turned on, rather than at first launch:
      // a permission prompt makes sense when it follows a decision.
      final granted = await notifier.ensurePermission();
      if (!granted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Notifications are blocked for this app in system settings.',
            ),
          ),
        );
        return;
      }
    }

    await settings.setDigestEnabled(value);
    await DigestScheduler.configure(enabled: value);
  }

  /// "9:00 AM and 11:00 AM", in the reader's own clock format.
  String _scheduleLabel(BuildContext context) {
    final times = [
      for (final at in DigestScheduler.refreshTimes) at.format(context),
    ];
    if (times.length < 2) return times.join();
    return '${times.take(times.length - 1).join(', ')} and ${times.last}';
  }

  Future<void> _sendNow() async {
    final digest = context.read<DigestService>();
    final notifier = context.read<Notifier>();
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _busy = true);
    try {
      final granted = await notifier.ensurePermission();
      if (!granted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Notifications are blocked.')),
        );
        return;
      }
      final result = await digest.run(force: true);
      final digestResult = result.digest;
      final refreshed = result.refreshed;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            digestResult == null || digestResult.isEmpty
                ? 'Nothing published in the 7-day window yet.'
                : refreshed.isEmpty
                ? digestResult.title
                : '${digestResult.title} · '
                      '${refreshed.map((m) => m.objectKey).join(', ')} refreshed',
          ),
        ),
      );
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Digest failed: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final settings = context.watch<SettingsController>();
    final digest = context.read<DigestService>();
    final enabled = settings.digestEnabled;
    final last = digest.lastSentText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          child: Column(
            children: [
              SwitchListTile(
                value: enabled,
                title: const Text('Refresh and alerts'),
                subtitle: const Text(
                  'Fetch every file on a schedule, and notify when a ticker '
                  'joins the 7-day screen',
                ),
                onChanged: (value) => _setEnabled(value),
              ),
              Divider(height: 1, color: colors.divider, indent: 16),
              ListTile(
                enabled: enabled,
                // The times sit in the title rather than in a trailing widget:
                // at 320dp two of them fill the whole tile.
                title: Text('Refreshes at ${_scheduleLabel(context)}'),
                subtitle: Text(
                  DigestScheduler.isSupported
                      ? 'The app is woken to fetch every file and check the '
                            'screen, whether or not it is open'
                      : 'This desktop cannot be woken on a schedule; the '
                            'check runs when the app is next opened',
                ),
              ),
              Divider(height: 1, color: colors.divider, indent: 16),
              ListTile(
                enabled: !_busy,
                leading: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.notifications_active_outlined),
                title: const Text('Check now'),
                subtitle: const Text(
                  'Fetches every file and posts what is new',
                ),
                onTap: _busy ? null : _sendNow,
              ),
            ],
          ),
        ),
        if (last != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Last sent ${digest.lastSentDay ?? '—'}',
                  style: TextStyle(fontSize: 11.5, color: colors.textTertiary),
                ),
                const SizedBox(height: 2),
                Text(
                  '${last.$1} — ${last.$2}',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
