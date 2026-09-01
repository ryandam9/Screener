import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/db_sync_service.dart';
import '../../models/daily_digest.dart';
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

/// Notification preferences, delivery health and a safe in-app preview.
class _DigestPanel extends StatefulWidget {
  const _DigestPanel();

  @override
  State<_DigestPanel> createState() => _DigestPanelState();
}

class _DigestPanelState extends State<_DigestPanel> {
  bool _busy = false;
  DailyDigest? _preview;
  DigestRefresh? _refresh;
  NotificationPermissionStatus? _permission;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshPermission());
  }

  Future<void> _refreshPermission() async {
    final status = await context.read<Notifier>().permissionStatus();
    if (mounted) setState(() => _permission = status);
  }

  Future<void> _setEnabled(bool value) async {
    final settings = context.read<SettingsController>();
    final notifier = context.read<Notifier>();
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _busy = true);
    try {
      if (value) {
        // Asked at the moment it is enabled, when the system prompt has clear
        // context rather than appearing cold on first launch.
        final granted = await notifier.ensurePermission();
        if (!granted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Notifications are blocked. Open system settings to allow them.',
              ),
            ),
          );
          return;
        }
      }

      await settings.setDigestEnabled(value);
      await DigestScheduler.configure(
        enabled: value,
        times: settings.checkTimes,
      );
      if (!value) await notifier.cancelAll();
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not update alerts: $error')),
      );
    } finally {
      if (mounted) {
        await _refreshPermission();
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  String _scheduleLabel(BuildContext context, SettingsController settings) {
    final times = [for (final at in settings.checkTimes) at.format(context)];
    if (times.length < 2) return times.join();
    return '${times.take(times.length - 1).join(', ')} and ${times.last}';
  }

  Future<void> _pickTime() async {
    final settings = context.read<SettingsController>();
    final selected = await showTimePicker(
      context: context,
      initialTime: settings.primaryCheckTime,
      helpText: 'Choose approximate check hour',
    );
    if (selected == null || !mounted) return;
    final hour = TimeOfDay(hour: selected.hour, minute: 0);
    await settings.setPrimaryCheckTime(hour);
    await DigestScheduler.configure(
      enabled: settings.digestEnabled,
      times: settings.checkTimes,
    );
  }

  Future<void> _checkNow() async {
    final digest = context.read<DigestService>();
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _busy = true);
    try {
      final refresh = await digest.refresh(allowHealthAlert: false);
      final preview = await digest.preview();
      if (!mounted) return;
      setState(() {
        _refresh = refresh;
        _preview = preview;
      });
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Check failed: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendSample() async {
    final notifier = context.read<Notifier>();
    final digest = context.read<DigestService>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      if (!await notifier.ensurePermission()) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Notifications are blocked.')),
        );
        return;
      }
      await digest.sendSample();
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Sample notification sent.')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not send sample: $error')),
      );
    } finally {
      if (mounted) {
        await _refreshPermission();
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  Future<void> _openSystemSettings() async {
    final opened = await context.read<Notifier>().openSettings();
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('System notification settings are unavailable here.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final settings = context.watch<SettingsController>();
    final digest = context.read<DigestService>();
    final enabled = settings.digestEnabled;
    final last = digest.lastSentText;
    final permission = _permission;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                value: enabled,
                secondary: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: enabled
                        ? colors.interactiveSurface
                        : colors.neutralSurface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    enabled
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_none_outlined,
                    color: enabled ? colors.interactive : colors.textSecondary,
                  ),
                ),
                title: const Text('Screen alerts'),
                subtitle: const Text(
                  'A calm summary when new tickers enter your 7-day screens',
                ),
                onChanged: _busy ? null : _setEnabled,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _StatusChip(
                      icon: enabled ? Icons.check_circle_outline : Icons.pause,
                      label: enabled ? 'Alerts on' : 'Alerts off',
                      color: enabled ? colors.positive : colors.neutral,
                      surface: enabled
                          ? colors.positiveSurface
                          : colors.neutralSurface,
                    ),
                    _StatusChip(
                      icon: permission == NotificationPermissionStatus.blocked
                          ? Icons.block
                          : Icons.verified_outlined,
                      label: switch (permission) {
                        NotificationPermissionStatus.blocked =>
                          'System blocked',
                        NotificationPermissionStatus.unsupported =>
                          'In-app only',
                        NotificationPermissionStatus.enabled =>
                          'System allowed',
                        null => 'Checking permission',
                      },
                      color: permission == NotificationPermissionStatus.blocked
                          ? colors.negative
                          : colors.textSecondary,
                      surface:
                          permission == NotificationPermissionStatus.blocked
                          ? colors.negativeSurface
                          : colors.neutralSurface,
                    ),
                  ],
                ),
              ),
              PageTransitionSwitcher(
                duration: AppMotion.contentDuration(context),
                transitionBuilder: (child, animation, secondaryAnimation) =>
                    FadeThroughTransition(
                      animation: animation,
                      secondaryAnimation: secondaryAnimation,
                      fillColor: colors.card,
                      child: child,
                    ),
                child: enabled
                    ? _AlertPreferences(
                        key: const ValueKey('enabled-alert-preferences'),
                        settings: settings,
                        scheduleLabel: _scheduleLabel(context, settings),
                        onPickTime: _pickTime,
                        onChanged: () => DigestScheduler.configure(
                          enabled: settings.digestEnabled,
                          times: settings.checkTimes,
                        ),
                      )
                    : Padding(
                        key: const ValueKey('disabled-alert-explanation'),
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Text(
                          DigestScheduler.isSupported
                              ? 'Enable alerts to choose markets, timing and delivery style.'
                              : 'On desktop, checks run when the app opens because the app cannot be woken reliably.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
              ),
              Divider(height: 1, color: colors.divider),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : _checkNow,
                      icon: _busy
                          ? const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh, size: 18),
                      label: const Text('Check now'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _sendSample,
                      icon: const Icon(Icons.notifications_outlined, size: 18),
                      label: const Text('Send sample'),
                    ),
                    if (permission == NotificationPermissionStatus.blocked)
                      TextButton.icon(
                        onPressed: _openSystemSettings,
                        icon: const Icon(Icons.settings_outlined, size: 18),
                        label: const Text('System settings'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        PageTransitionSwitcher(
          duration: AppMotion.contentDuration(context),
          transitionBuilder: (child, animation, secondaryAnimation) =>
              FadeThroughTransition(
                animation: animation,
                secondaryAnimation: secondaryAnimation,
                child: child,
              ),
          child: _preview == null
              ? const SizedBox.shrink(key: ValueKey('no-preview'))
              : _DigestPreview(
                  key: const ValueKey('digest-preview'),
                  digest: _preview!,
                  refresh: _refresh!,
                ),
        ),
        if (digest.lastAttempt != null || last != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Activity',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  [
                    if (digest.lastAttempt != null)
                      'Checked ${Fmt.relativeStamp(digest.lastAttempt!)}',
                    if (digest.lastSuccess != null)
                      'Last successful ${Fmt.relativeStamp(digest.lastSuccess!)}',
                    if (digest.lastSentDay != null)
                      'Alert sent ${digest.lastSentDay}',
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: colors.textTertiary,
                  ),
                ),
                if (digest.lastError != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    digest.lastError!,
                    style: TextStyle(fontSize: 12, color: colors.negative),
                  ),
                ],
                if (last != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    '${last.$1} — ${last.$2}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: colors.textTertiary),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _AlertPreferences extends StatelessWidget {
  const _AlertPreferences({
    super.key,
    required this.settings,
    required this.scheduleLabel,
    required this.onPickTime,
    required this.onChanged,
  });

  final SettingsController settings;
  final String scheduleLabel;
  final VoidCallback onPickTime;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: colors.divider),
        ListTile(
          leading: const Icon(Icons.schedule_outlined),
          title: Text('Checks around $scheduleLabel'),
          subtitle: Text(
            DigestScheduler.isSupported
                ? 'Android chooses the exact time based on network and battery conditions.'
                : 'Runs on the next app open on this desktop.',
          ),
          trailing: DigestScheduler.isSupported
              ? const Icon(Icons.chevron_right)
              : null,
          onTap: DigestScheduler.isSupported ? onPickTime : null,
        ),
        if (DigestScheduler.isSupported)
          SwitchListTile(
            value: settings.followUpCheck,
            title: const Text('Follow-up check'),
            subtitle: const Text('Try again about two hours later'),
            onChanged: (value) async {
              await settings.setFollowUpCheck(value);
              await onChanged();
            },
          ),
        Divider(height: 1, color: colors.divider, indent: 16),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Text(
            'DELIVERY',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: colors.textTertiary,
            ),
          ),
        ),
        RadioGroup<AlertDeliveryMode>(
          groupValue: settings.alertDeliveryMode,
          onChanged: (value) {
            if (value != null) settings.setAlertDeliveryMode(value);
          },
          child: Column(
            children: [
              for (final mode in AlertDeliveryMode.values)
                RadioListTile<AlertDeliveryMode>(
                  value: mode,
                  title: Text(mode.label),
                  subtitle: Text(mode.description),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Text('Markets', style: TextStyle(color: colors.textSecondary)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final market in Market.values)
                FilterChip(
                  label: Text('${market.emoji} ${market.label}'),
                  selected: settings.alertMarkets.contains(market),
                  onSelected: (selected) {
                    final next = settings.alertMarkets;
                    selected ? next.add(market) : next.remove(market);
                    settings.setAlertMarkets(next);
                  },
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: DropdownButtonFormField<double>(
            initialValue: settings.minimumAlertMove,
            decoration: const InputDecoration(
              labelText: 'Minimum weekly move',
              helperText: 'Applied after the screen’s published cut-off',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 0, child: Text('Use screen cut-off')),
              DropdownMenuItem(value: 15, child: Text('15% or more')),
              DropdownMenuItem(value: 25, child: Text('25% or more')),
              DropdownMenuItem(value: 50, child: Text('50% or more')),
            ],
            onChanged: (value) {
              if (value != null) settings.setMinimumAlertMove(value);
            },
          ),
        ),
        SwitchListTile(
          value: settings.dataHealthAlerts,
          title: const Text('Stale-data warning'),
          subtitle: const Text(
            'A quiet alert only after repeated failures and data older than 24 hours',
          ),
          onChanged: settings.setDataHealthAlerts,
        ),
      ],
    );
  }
}

class _DigestPreview extends StatelessWidget {
  const _DigestPreview({
    super.key,
    required this.digest,
    required this.refresh,
  });

  final DailyDigest digest;
  final DigestRefresh refresh;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final failureLabels = refresh.failures.keys
        .map((market) => market.label)
        .join(', ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: refresh.allSucceeded
              ? colors.interactiveSurface
              : colors.warningSurface,
          borderRadius: BorderRadius.circular(AppRadii.panel),
          border: Border.all(
            color: refresh.allSucceeded ? colors.interactive : colors.warning,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  refresh.allSucceeded
                      ? Icons.preview_outlined
                      : Icons.warning_amber_rounded,
                  size: 19,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'In-app preview — nothing was sent',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              refresh.allSucceeded
                  ? digest.title
                  : 'Could not refresh $failureLabels. Showing the cached screen only.',
              style: TextStyle(color: colors.textPrimary),
            ),
            if (refresh.allSucceeded && !digest.isEmpty) ...[
              const SizedBox(height: 3),
              Text(
                digest.body,
                style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.surface,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color surface;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    ),
  );
}
