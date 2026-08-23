import 'package:flutter/material.dart';

import '../../models/growth_window.dart';
import '../../models/run_details.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import 'panels.dart';

/// The `run_metadata` row: how, when and against what the run was produced.
class RunMetadataPanel extends StatelessWidget {
  const RunMetadataPanel({super.key, required this.metadata});

  final RunMetadata metadata;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final duration = metadata.duration;
    final total = metadata.universeTotal;
    final screened = metadata.universeScreened;

    final rows = <(String, String)>[
      if (metadata.exchange != null || metadata.instrumentType != null)
        (
          'Universe',
          [
            metadata.exchange,
            metadata.instrumentType?.replaceAll('_', ' '),
          ].whereType<String>().join(' · '),
        ),
      if (total != null)
        (
          'Instruments',
          screened == null
              ? Fmt.integer(total)
              : '${Fmt.integer(screened)} screened of ${Fmt.integer(total)}',
        ),
      ('Data as of', Fmt.date(metadata.dataAsOf)),
      if (metadata.startedAt != null)
        ('Run started', Fmt.dateTime(metadata.startedAt!)),
      if (duration != null) ('Run took', _formatDuration(duration)),
      if (metadata.provider != null) ('Price provider', metadata.provider!),
      if (metadata.codeRevision != null)
        ('Code revision', metadata.codeRevision!),
      if (metadata.runId != null) ('Run id', metadata.runId!),
      if (metadata.sourceRunId != null)
        (
          'Source run',
          metadata.sourceStatus == null
              ? metadata.sourceRunId!
              : '${metadata.sourceRunId!} (${metadata.sourceStatus})',
        ),
      ...metadata.headlineSettings,
    ];

    return Panel(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 3),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Run metadata',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                _StatusChip(
                  label: metadata.status ?? 'unknown',
                  ok: metadata.succeeded,
                ),
              ],
            ),
          ),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: colors.divider, indent: 14),
            MetricRow(label: rows[i].$1, value: rows[i].$2),
          ],
        ],
      ),
    );
  }

  /// `0.4s`, `1m 12s` — runs are short, so minutes are the largest unit shown.
  static String _formatDuration(Duration duration) {
    final seconds = duration.inMilliseconds / 1000;
    if (seconds < 60) return '${seconds.toStringAsFixed(1)}s';
    final minutes = duration.inMinutes;
    return '${minutes}m ${duration.inSeconds - minutes * 60}s';
  }
}

/// `screen_funnel`: how many instruments each stage of the screen let through.
///
/// The table holds every window's stages, and reading five funnels at once is
/// no easier than reading one, so a selector picks the window and the panel
/// draws that funnel alone.
class ScreenFunnelPanel extends StatefulWidget {
  const ScreenFunnelPanel({super.key, required this.stages});

  final List<FunnelStage> stages;

  @override
  State<ScreenFunnelPanel> createState() => _ScreenFunnelPanelState();
}

class _ScreenFunnelPanelState extends State<ScreenFunnelPanel> {
  GrowthWindow? _selected;

  /// Windows the funnel actually covers, shortest first.
  List<GrowthWindow> get _windows {
    final present = {
      for (final stage in widget.stages)
        if (stage.window case final window?) window,
    };
    return [
      for (final window in GrowthWindow.values)
        if (present.contains(window)) window,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final windows = _windows;
    final selected = windows.contains(_selected)
        ? _selected!
        : (windows.isEmpty ? null : windows.first);

    final stages = [
      for (final stage in widget.stages)
        if (stage.window == selected) stage,
    ]..sort((a, b) => a.position.compareTo(b.position));

    // Stages are cumulative, so the first is the widest bar.
    final start = stages.isEmpty ? 0 : stages.first.count;

    return Panel(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Screen funnel',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Instruments surviving each stage of the screen.',
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
          if (windows.length > 1) ...[
            const SizedBox(height: 10),
            PeriodSelector<GrowthWindow>(
              values: windows,
              selected: selected!,
              labelOf: (window) => window.label,
              onChanged: (window) => setState(() => _selected = window),
            ),
          ],
          const SizedBox(height: 12),
          for (var i = 0; i < stages.length; i++)
            _FunnelRow(
              stage: stages[i],
              previous: i == 0 ? null : stages[i - 1].count,
              fraction: start == 0 ? 0 : stages[i].count / start,
            ),
          if (stages.isEmpty)
            Text(
              'No stages published for this window.',
              style: TextStyle(fontSize: 12.5, color: colors.textTertiary),
            ),
        ],
      ),
    );
  }
}

class _FunnelRow extends StatelessWidget {
  const _FunnelRow({
    required this.stage,
    required this.previous,
    required this.fraction,
  });

  final FunnelStage stage;
  final int? previous;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dropped = previous == null ? 0 : previous! - stage.count;
    final empty = stage.count == 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  stage.stage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
                ),
              ),
              const SizedBox(width: 10),
              if (dropped > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    '−${Fmt.integer(dropped)}',
                    style: TextStyle(fontSize: 11.5, color: colors.negative),
                  ),
                ),
              Text(
                Fmt.integer(stage.count),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: empty ? colors.textTertiary : colors.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          // A hairline is still drawn for a zero stage, so the bar reads as a
          // measured nothing rather than a missing row.
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Container(
              height: 6,
              color: colors.neutralSurface,
              alignment: AlignmentDirectional.centerStart,
              child: FractionallySizedBox(
                widthFactor: fraction.clamp(0.0, 1.0),
                child: Container(
                  color: empty ? colors.textTertiary : colors.positive,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.ok});

  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: ok ? colors.positiveSurface : colors.warningSurface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: ok ? colors.positive : colors.warning,
        ),
      ),
    );
  }
}
