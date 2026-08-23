import 'dart:convert';

import 'growth_window.dart';

/// The `run_metadata` row: how the published run was produced.
class RunMetadata {
  const RunMetadata({
    required this.runId,
    required this.status,
    this.codeRevision,
    this.exchange,
    this.instrumentType,
    this.dataAsOf,
    this.startedAt,
    this.finishedAt,
    this.universeTotal,
    this.universeScreened,
    this.provider,
    this.sourceRunId,
    this.sourceStatus,
    this.settings = const {},
  });

  final String? runId;
  final String? status;
  final String? codeRevision;
  final String? exchange;
  final String? instrumentType;
  final String? dataAsOf;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  /// Instruments known to the provider, before the screen.
  final int? universeTotal;

  /// Instruments the run actually examined.
  final int? universeScreened;

  final String? provider;
  final String? sourceRunId;
  final String? sourceStatus;

  /// Parsed `settings_json`; empty when absent or unparseable.
  final Map<String, Object?> settings;

  bool get succeeded => status?.toLowerCase() == 'success';

  /// How long the run took, when both ends are published.
  Duration? get duration {
    final start = startedAt;
    final end = finishedAt;
    if (start == null || end == null) return null;
    final elapsed = end.difference(start);
    return elapsed.isNegative ? null : elapsed;
  }

  /// Settings worth surfacing, in a stable order, as label/value pairs.
  ///
  /// The JSON also carries the per-window thresholds, which the funnel already
  /// names ("Return above 25.0%"), so they are not repeated here.
  List<(String, String)> get headlineSettings {
    final pairs = <(String, String)>[];
    void add(String label, String key, {String suffix = ''}) {
      final value = settings[key];
      if (value == null) return;
      pairs.add((label, '$value$suffix'));
    }

    add('Minimum price', 'min_price');
    add('Minimum median volume', 'min_median_volume');
    add('Minimum coverage', 'min_coverage');
    add('Minimum observation ratio', 'min_observation_ratio');
    add('Maximum data age', 'max_data_age_days', suffix: ' days');
    add('Endpoint window', 'endpoint_window', suffix: ' days');
    add('Price history sampling', 'price_history_sampling');
    return pairs;
  }

  static RunMetadata fromMap(Map<String, Object?> map) {
    Map<String, Object?> settings = const {};
    final raw = _string(map['settings_json']);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, Object?>) settings = decoded;
      } on FormatException {
        // Unparseable settings are not worth failing the whole screen over.
      }
    }

    return RunMetadata(
      runId: _string(map['run_id']),
      status: _string(map['status']),
      codeRevision: _string(map['code_revision']),
      exchange: _string(map['exchange']),
      instrumentType: _string(map['instrument_type']),
      dataAsOf: _string(map['data_as_of']),
      startedAt: _date(map['started_at']),
      finishedAt: _date(map['finished_at']),
      universeTotal: _int(map['universe_total']),
      universeScreened: _int(map['universe_screened']),
      provider: _string(map['provider']),
      sourceRunId: _string(map['source_run_id']),
      sourceStatus: _string(map['source_status']),
      settings: settings,
    );
  }

  static String? _string(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static DateTime? _date(Object? value) {
    final text = _string(value);
    return text == null ? null : DateTime.tryParse(text)?.toLocal();
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }
}

/// One step of `screen_funnel`: how many instruments survived a stage.
class FunnelStage {
  const FunnelStage({
    required this.window,
    required this.position,
    required this.stage,
    required this.count,
  });

  final GrowthWindow? window;
  final int position;
  final String stage;
  final int count;

  static FunnelStage? fromMap(Map<String, Object?> map) {
    final stage = RunMetadata._string(map['stage']);
    final count = RunMetadata._int(map['count']);
    if (stage == null || count == null) return null;

    // The column holds the window's table suffix without its leading
    // underscore, e.g. "7_days".
    final raw = RunMetadata._string(map['window']);
    return FunnelStage(
      window: raw == null ? null : GrowthWindow.fromTableName('_$raw'),
      position: RunMetadata._int(map['position']) ?? 0,
      stage: stage,
      count: count,
    );
  }
}
