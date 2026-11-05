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
import '../widgets/watchlist_star.dart';
import 'reports_screen.dart';
import '../info/page_info.dart';
import '../widgets/info_dialog.dart';

/// Width at which the digest moves into a column of its own.
const double _twoColumnWidth = 820;

/// Data source status, cache controls, appearance and the daily digest.
///
/// Laid out as the approved mockup: a compact title bar, then general
/// settings on the left and the digest on the right, with About spanning the
/// foot of the page. On a handset the two columns stack.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final narrow = MediaQuery.sizeOf(context).width < _twoColumnWidth;

    final general = <Widget>[
      const _DataSourcesSection(),
      const _AppearanceSection(),
      const _WatchlistSection(),
      const _ReportsSection(),
    ];

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        shape: Border(bottom: BorderSide(color: colors.divider)),
        // "More" is the handset tab this screen sits behind; the desktop
        // sidebar calls the same screen Settings, and the title follows it.
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(narrow ? 'More' : 'Settings'),
            const SizedBox(height: 3),
            Text(
              'Data, appearance and your daily digest',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                letterSpacing: 0,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
        actions: const [
          InfoButton(info: PageInfos.settings),
          SizedBox(width: 4),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final twoColumns = constraints.maxWidth >= _twoColumnWidth;
          final padding = twoColumns ? 20.0 : 16.0;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(padding, padding, padding, 28),
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (twoColumns)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: general,
                            ),
                          ),
                          const SizedBox(width: 18),
                          const Expanded(child: _DigestPanel()),
                        ],
                      )
                    else ...[
                      ...general,
                      const _DigestPanel(),
                    ],
                    const _AboutSection(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DataSourcesSection extends StatelessWidget {
  const _DataSourcesSection();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final sync = context.read<DbSyncService>();
    final colors = context.colors;
    final busy = appState.anyBusy;

    return _SettingsSection(
      title: 'Data sources',
      child: _SettingsCard(
        children: [
          for (final market in Market.values) _MarketStatusRow(market: market),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _CompactButton(
                      label: 'Re-download',
                      icon: Icons.refresh,
                      onPressed: busy ? null : appState.redownloadAll,
                    ),
                    _CompactButton(
                      label: 'Clear cache',
                      icon: Icons.delete_outline,
                      onPressed: busy
                          ? null
                          : () => _clearCache(context, appState, sync),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Bucket: ${Uri.tryParse(sync.baseUrl)?.host.nonEmpty ?? sync.baseUrl}',
                  style: TextStyle(fontSize: 11, color: colors.textTertiary),
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
    await appState.refreshAll();
  }
}

extension on String {
  String? get nonEmpty => isEmpty ? null : this;
}

/// One published file: market and object key, its state, size and stamp.
class _MarketStatusRow extends StatelessWidget {
  const _MarketStatusRow({required this.market});

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
      SyncPhase.ready => (Icons.check, colors.positive, 'Up to date'),
      SyncPhase.error => (Icons.error_outline, colors.negative, 'Failed'),
      SyncPhase.downloading => (
        Icons.downloading,
        colors.neutral,
        'Downloading',
      ),
      _ => (Icons.sync, colors.neutral, 'Checking'),
    };

    return _SettingRow(
      title: Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(icon, size: 15, color: tint),
              ),
            ),
            TextSpan(text: market.label),
            TextSpan(
              text: ' · ${market.objectKey}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w400,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: [
        status,
        if (asset != null) Fmt.bytes(asset.sizeBytes),
      ].join(' · '),
      // Its own line, as in the mockup: the stamp under the status.
      footer: asset == null && state.error == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (asset != null)
                  Text(
                    'Synced ${Fmt.relativeStamp(asset.syncedAt)}',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: colors.textSecondary,
                    ),
                  ),
                if (state.error != null)
                  Text(
                    state.error!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: colors.negative),
                  ),
              ],
            ),
      trailing: IconButton(
        tooltip: 'Check for updates',
        iconSize: 17,
        color: colors.textTertiary,
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.refresh),
        onPressed: state.isBusy ? null : () => appState.refresh(market),
      ),
    );
  }
}

class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    return _SettingsSection(
      title: 'Appearance',
      child: _SettingsCard(
        children: [
          LayoutBuilder(
            builder: (context, constraints) => _SettingRow(
              // The pills want ~170dp; under that much room beside the label,
              // they go below it rather than squeezing it.
              trailingBelow:
                  constraints.maxWidth <
                  300 * MediaQuery.textScalerOf(context).scale(1),
              title: const Text('Theme'),
              subtitle: switch (settings.themeMode) {
                ThemeMode.system => 'Follow system',
                ThemeMode.light => 'Always light',
                ThemeMode.dark => 'Always dark',
              },
              trailing: _InlineSegments<ThemeMode>(
                value: settings.themeMode,
                options: const {
                  ThemeMode.light: 'Light',
                  ThemeMode.system: 'System',
                  ThemeMode.dark: 'Dark',
                },
                onChanged: settings.setThemeMode,
              ),
            ),
          ),
          _SettingRow(
            title: const Text('Compact rows'),
            subtitle: 'Fit more instruments on screen',
            onTap: () => settings.setCompactRows(!settings.compactRows),
            trailing: Checkbox(
              value: settings.compactRows,
              onChanged: (value) => settings.setCompactRows(value ?? false),
            ),
          ),
        ],
      ),
    );
  }
}

class _WatchlistSection extends StatelessWidget {
  const _WatchlistSection();

  @override
  Widget build(BuildContext context) {
    final watchlist = context.watch<WatchlistController>();
    return _SettingsSection(
      title: 'Watchlist',
      child: _SettingsCard(
        children: [
          _SettingRow(
            title: const Text('Starred tickers'),
            subtitle: watchlist.isEmpty
                ? 'Nothing starred yet'
                // Only the files that have something starred, so a market you
                // do not follow does not sit here reading "0".
                : [
                    for (final market in Market.values)
                      if (watchlist.countFor(market) > 0)
                        '${watchlist.countFor(market)} ${market.label}',
                  ].join(' · '),
            trailing: watchlist.isEmpty
                ? null
                : TextButton(
                    onPressed: () => confirmClearWatchlist(context, watchlist),
                    child: const Text('Clear'),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ReportsSection extends StatelessWidget {
  const _ReportsSection();

  @override
  Widget build(BuildContext context) {
    return _SettingsSection(
      title: 'Reports',
      child: _SettingsCard(
        children: [
          _SettingRow(
            title: const Text('Runs and CSV export'),
            subtitle: 'Every published run, exportable as CSV',
            trailing: Icon(
              Icons.arrow_forward,
              size: 17,
              color: context.colors.textSecondary,
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ReportsScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return _SettingsSection(
      title: 'About Stocks Analysis',
      child: _SettingsCard(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reads the growth-screener SQLite databases published to '
                  's3://hive-in-the-cloud and renders them on device. Files are '
                  'cached locally, so everything except the refresh works '
                  'without a connection.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.6,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Figures are screener output — window endpoints, not live '
                  'quotes — and are not investment advice.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.5,
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
    // Guarded: the callback runs a frame later, and a screen torn down in
    // between leaves this State without a context to read the notifier from.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshPermission();
    });
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
    final blocked = permission == NotificationPermissionStatus.blocked;
    final statusStyle = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      color: enabled ? colors.positive : colors.textSecondary,
    );

    final hasActivity = digest.lastAttempt != null || last != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingsSection(
          title: 'Daily digest',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SettingsCard(
                children: [
                  _SettingRow(
                    title: const Text('Screen alerts'),
                    subtitle:
                        'A calm summary when new tickers enter your 7-day '
                        'screens',
                    onTap: _busy ? null : () => _setEnabled(!enabled),
                    trailing: Checkbox(
                      value: enabled,
                      onChanged: _busy
                          ? null
                          : (value) => _setEnabled(value ?? false),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        // Separate Texts rather than one string, so each half
                        // can take its own colour when the system blocks us.
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Icon(
                              enabled ? Icons.check : Icons.pause,
                              size: 13,
                              color: statusStyle.color,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              enabled ? 'Alerts on' : 'Alerts off',
                              style: statusStyle,
                            ),
                            Text(' · ', style: statusStyle),
                            Text(
                              switch (permission) {
                                NotificationPermissionStatus.blocked =>
                                  'System blocked',
                                NotificationPermissionStatus.unsupported =>
                                  'In-app only',
                                NotificationPermissionStatus.enabled =>
                                  'System allowed',
                                null => 'Checking permission',
                              },
                              style: blocked
                                  ? statusStyle.copyWith(color: colors.negative)
                                  : statusStyle,
                            ),
                          ],
                        ),
                      ),
                      PageTransitionSwitcher(
                        duration: AppMotion.contentDuration(context),
                        // Transparent, not the card colour: the fill is painted
                        // as a ColoredBox around the child, and one between the
                        // card's Material and the rows inside it swallows their
                        // ink splashes. The card paints the surface.
                        transitionBuilder:
                            (child, animation, secondaryAnimation) =>
                                FadeThroughTransition(
                                  animation: animation,
                                  secondaryAnimation: secondaryAnimation,
                                  fillColor: Colors.transparent,
                                  child: child,
                                ),
                        child: enabled
                            ? _AlertPreferences(
                                key: const ValueKey(
                                  'enabled-alert-preferences',
                                ),
                                settings: settings,
                                scheduleLabel: _scheduleLabel(
                                  context,
                                  settings,
                                ),
                                onPickTime: _pickTime,
                                onChanged: () => DigestScheduler.configure(
                                  enabled: settings.digestEnabled,
                                  times: settings.checkTimes,
                                ),
                              )
                            : Padding(
                                key: const ValueKey(
                                  'disabled-alert-explanation',
                                ),
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  10,
                                  16,
                                  16,
                                ),
                                child: Text(
                                  DigestScheduler.isSupported
                                      ? 'Enable alerts to choose markets, timing and delivery style.'
                                      : 'On desktop, checks run when the app opens because the app cannot be woken reliably.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.5,
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _CompactButton(
                          label: 'Check now',
                          icon: _busy ? null : Icons.refresh,
                          primary: true,
                          busy: _busy,
                          onPressed: _busy ? null : _checkNow,
                        ),
                        _CompactButton(
                          label: 'Send sample',
                          icon: Icons.notifications_outlined,
                          onPressed: _busy ? null : _sendSample,
                        ),
                        if (blocked)
                          _CompactButton(
                            label: 'System settings',
                            icon: Icons.settings_outlined,
                            onPressed: _openSystemSettings,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              PageTransitionSwitcher(
                duration: AppMotion.contentDuration(context),
                // See above: the default fill is the canvas colour, which is
                // a ColoredBox all the same.
                transitionBuilder: (child, animation, secondaryAnimation) =>
                    FadeThroughTransition(
                      animation: animation,
                      secondaryAnimation: secondaryAnimation,
                      fillColor: Colors.transparent,
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
            ],
          ),
        ),
        if (hasActivity)
          _SettingsSection(
            title: 'Activity',
            child: _SettingsCard(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                          height: 1.5,
                          color: colors.textSecondary,
                        ),
                      ),
                      if (digest.lastError != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          digest.lastError!,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.negative,
                          ),
                        ),
                      ],
                      if (last != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${last.$1} — ${last.$2}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.6,
                            color: colors.textTertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
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
    final labelStyle = TextStyle(fontSize: 12, color: colors.textSecondary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // No rule above: the schedule reads as part of the status block.
        _SettingRow(
          title: Text('Checks around $scheduleLabel'),
          subtitle: DigestScheduler.isSupported
              ? 'Android chooses the exact time based on network and battery '
                    'conditions.'
              : 'Runs on the next app open on this desktop.',
          trailing: DigestScheduler.isSupported
              ? Icon(Icons.chevron_right, color: colors.textSecondary)
              : null,
          onTap: DigestScheduler.isSupported ? onPickTime : null,
        ),
        Divider(height: 1, color: colors.divider),
        if (DigestScheduler.isSupported) ...[
          _SettingRow(
            title: const Text('Follow-up check'),
            subtitle: 'Try again about two hours later',
            onTap: () async {
              await settings.setFollowUpCheck(!settings.followUpCheck);
              await onChanged();
            },
            trailing: Checkbox(
              value: settings.followUpCheck,
              onChanged: (value) async {
                await settings.setFollowUpCheck(value ?? false);
                await onChanged();
              },
            ),
          ),
          Divider(height: 1, color: colors.divider),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'DELIVERY',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.1,
                  color: colors.textTertiary,
                ),
              ),
              const SizedBox(height: 4),
              RadioGroup<AlertDeliveryMode>(
                groupValue: settings.alertDeliveryMode,
                onChanged: (value) {
                  if (value != null) settings.setAlertDeliveryMode(value);
                },
                child: Column(
                  children: [
                    for (final mode in AlertDeliveryMode.values)
                      InkWell(
                        borderRadius: BorderRadius.circular(AppRadii.control),
                        onTap: () => settings.setAlertDeliveryMode(mode),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Radio<AlertDeliveryMode>(
                                value: mode,
                                visualDensity: VisualDensity.compact,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 9),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        mode.label,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: colors.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        mode.description,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          height: 1.45,
                                          color: colors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text('Markets', style: labelStyle),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final market in Market.values)
                    _CheckChip(
                      label: market.label,
                      value: settings.alertMarkets.contains(market),
                      onChanged: (selected) {
                        final next = settings.alertMarkets;
                        selected ? next.add(market) : next.remove(market);
                        settings.setAlertMarkets(next);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Text('Minimum weekly move', style: labelStyle),
              const SizedBox(height: 8),
              DropdownButtonFormField<double>(
                initialValue: settings.minimumAlertMove,
                // Without this the button's Row sizes to the widest item and
                // overflows the field: "Use screen cut-off" wants 53px more
                // than a 320dp phone leaves it.
                isExpanded: true,
                isDense: true,
                style: TextStyle(
                  fontFamily: kFontFamily,
                  fontSize: 13,
                  color: colors.textPrimary,
                ),
                decoration: const InputDecoration(isDense: true),
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
              const SizedBox(height: 8),
              Text(
                'Applied after the screen’s published cut-off.',
                style: TextStyle(fontSize: 11, color: colors.textTertiary),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: colors.divider),
        _SettingRow(
          title: const Text('Stale-data warning'),
          subtitle:
              'A quiet alert only after repeated failures and data older '
              'than 24 hours',
          onTap: () => settings.setDataHealthAlerts(!settings.dataHealthAlerts),
          trailing: Checkbox(
            value: settings.dataHealthAlerts,
            onChanged: (value) => settings.setDataHealthAlerts(value ?? false),
          ),
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

/// A heading and the card under it, with the gap to the next section.
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
                color: context.colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// A bordered card whose children are separated by hairlines.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // A Material rather than a decorated box: rows inside are tappable, and
    // ink splashes are painted by the nearest Material ancestor.
    return Material(
      color: colors.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.panel),
        side: BorderSide(color: colors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, color: colors.divider),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Label, explanation and a control on the right — the unit of the page.
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    this.subtitle,
    this.footer,
    this.trailing,
    this.onTap,
    this.trailingBelow = false,
  });

  final Widget title;
  final String? subtitle;
  final Widget? footer;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Puts the control under the label, for a narrow card.
  final bool trailingBelow;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DefaultTextStyle.merge(
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
          child: title,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: colors.textSecondary,
            ),
          ),
        ],
        if (footer != null) footer!,
      ],
    );
    final content = Padding(
      padding: EdgeInsets.fromLTRB(16, 14, trailing == null ? 16 : 8, 14),
      child: trailingBelow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [text, const SizedBox(height: 10), ?trailing],
            )
          : Row(
              children: [
                Expanded(child: text),
                if (trailing != null) ...[const SizedBox(width: 12), trailing!],
              ],
            ),
    );
    return onTap == null ? content : InkWell(onTap: onTap, child: content);
  }
}

/// Light · System · Dark: a row of small pills, the chosen one filled.
class _InlineSegments<T> extends StatelessWidget {
  const _InlineSegments({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final MapEntry(key: option, value: label) in options.entries)
          Semantics(
            button: true,
            selected: option == value,
            excludeSemantics: true,
            label: label,
            onTap: () => onChanged(option),
            child: Material(
              color: option == value ? colors.interactive : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => onChanged(option),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 36),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: option == value
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: option == value
                              ? colors.onInteractive
                              : colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A small outlined (or filled, for the primary) action button.
class _CompactButton extends StatelessWidget {
  const _CompactButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.primary = false,
    this.busy = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool primary;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = ButtonStyle(
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(
          fontFamily: kFontFamily,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      iconSize: const WidgetStatePropertyAll(15),
      foregroundColor: primary
          ? null
          : WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled)
                  ? colors.textTertiary
                  : colors.textPrimary,
            ),
    );
    final leading = busy
        ? const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : icon == null
        ? null
        : Icon(icon);
    final text = Text(label);
    if (primary) {
      return leading == null
          ? FilledButton(onPressed: onPressed, style: style, child: text)
          : FilledButton.icon(
              onPressed: onPressed,
              style: style,
              icon: leading,
              label: text,
            );
    }
    return leading == null
        ? OutlinedButton(onPressed: onPressed, style: style, child: text)
        : OutlinedButton.icon(
            onPressed: onPressed,
            style: style,
            icon: leading,
            label: text,
          );
  }
}

/// A bordered checkbox with its label, for picking several of a few.
class _CheckChip extends StatelessWidget {
  const _CheckChip({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.control),
        side: BorderSide(color: colors.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: value,
                visualDensity: VisualDensity.compact,
                onChanged: (next) => onChanged(next ?? false),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
