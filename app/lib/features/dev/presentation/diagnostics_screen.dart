/// Developer diagnostics screen — M15 Phase 10 (§35 outline).
///
/// Deliberately utilitarian: a live readout of what the app knows right now,
/// so a developer standing outside with a phone can answer "why did the ghost
/// jump?" without guessing. Exposed only through the dev-tools gate
/// (`devToolsEnabledProvider`); the screen itself stays route-registered so
/// tests and deep links can reach it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/dependencies.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/units.dart';
import '../../../engine/fake_engine.dart';
import '../../../engine/models.dart';
import '../../../persistence/persistence.dart';
import '../application/fixture_export.dart';
import '../../recording/application/recording_controller.dart';

class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final engine = ref.watch(engineServiceProvider);
    final live = ref.watch(recordingControllerProvider);
    final snapshot = ref.watch(runSnapshotProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostics')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            _Section(
              title: 'ENGINE',
              rows: [
                _row('Implementation', engine.engineDescription),
                _row('Type', engine.runtimeType.toString()),
                _row('Run status', live?.status.name ?? '—'),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _Section(
              title: 'GPS',
              rows: [
                _row('Latitude', live?.currentPosition?.latitude.toStringAsFixed(6) ?? '—'),
                _row('Longitude', live?.currentPosition?.longitude.toStringAsFixed(6) ?? '—'),
                _row('Quality', live?.gpsQuality ?? '—'),
                _row('Pace', live?.pace.formatPace() ?? '—'),
                _row('Started', live?.startedAt?.toLocal().toIso8601String() ?? '—'),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _Section(
              title: 'TRACK',
              rows: [
                _row('Elapsed', live?.elapsed.format() ?? '—'),
                _row('Distance', live?.distance.format() ?? '—'),
                _row(
                  'Session points',
                  '${ref.read(recordingControllerProvider.notifier).currentTrack()?.length ?? 0}',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _Section(
              title: 'ROUTE',
              rows: [
                _row('Name', live?.route?.name ?? 'new route'),
                _row('Progress', live == null
                    ? '—'
                    : '${(live.routeProgress * 100).toStringAsFixed(1)} %'),
                _row(
                  'Geometry points',
                  '${live?.route?.geometry.length ?? 0}',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _Section(
              title: 'GHOST',
              rows: _ghostRow(live?.ghostGap),
            ),
            const SizedBox(height: AppSpacing.md),
            _Section(
              title: 'PERSISTENCE',
              rows: snapshot == null
                  ? [_row('Recovery snapshot', 'none')]
                  : [
                      _row('Status', snapshot.status.name),
                      _row('Start', snapshot.startedAt.toLocal().toIso8601String()),
                      _row('Moving', Elapsed.seconds(snapshot.movingSeconds).format()),
                      _row('Distance', Distance.meters(snapshot.distanceMeters).format()),
                      _row('Loop', Distance.meters(snapshot.loopMeters).format()),
                      _row('Route id', snapshot.routeId ?? '—'),
                      _row('Recovery', 'available'),
                    ],
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              key: const ValueKey('export-fixture'),
              onPressed: _copied ? null : _exportFixture,
              icon: const Icon(Icons.copy_rounded),
              label: Text(_copied ? 'Fixture JSON copied' : 'Export run as fixture JSON'),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }

  List<_Row> _ghostRow(GhostState? gap) {
    if (gap == null) {
      return [
        _row('Racing', 'no'),
        _row('Gap', '—'),
      ];
    }
    final direction = gap.ahead ? 'ahead' : 'behind';
    return [
      _row('Racing', 'yes'),
      _row('Gap', '${gap.timeDifference.format()} $direction'),
      _row(
        'At distance',
        gap.distance.format(),
      ),
    ];
  }

  _Row _row(String label, String value) => _Row(label, value);

  /// Exports the current in-flight track (or the most recent persisted run)
  /// as a raw-GPS fixture and copies it to the clipboard.
  Future<void> _exportFixture() async {
    final live = ref.read(recordingControllerProvider);
    final fixes = _exportFixes(live);
    final route = _exportRoute(live);
    if (fixes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No track to export yet.')),
      );
      return;
    }
    final json = buildFixtureJson(route: route, fixes: fixes);
    await Clipboard.setData(ClipboardData(text: json));
    setState(() => _copied = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fixture JSON copied to clipboard.')),
      );
    }
  }

  List<TrackPoint> _exportFixes(LiveRunState? live) {
    final liveTrack =
        ref.read(recordingControllerProvider.notifier).currentTrack();
    if (liveTrack != null && liveTrack.isNotEmpty) {
      return liveTrack;
    }
    final activities = ref.read(activityRepositoryProvider);
    for (final activity in activities) {
      if (activity.track case final track? when track.isNotEmpty) {
        return track;
      }
    }
    return const [];
  }

  List<GeoPoint> _exportRoute(LiveRunState? live) {
    if (live?.route != null) {
      return live!.route!.geometry;
    }
    final activities = ref.read(activityRepositoryProvider);
    for (final activity in activities) {
      final geometry = ref
          .read(routeRepositoryProvider)
          .where((r) => r.id == activity.routeId)
          .map((r) => r.geometry)
          .firstOrNull;
      if (geometry != null) {
        return geometry;
      }
    }
    return FakeEngineService.riverLoop;
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows});

  final String title;
  final List<_Row> rows;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: textTheme.labelMedium?.copyWith(color: AppColors.pb),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final row in rows) ...[
              row,
              if (row != rows.last) const Divider(height: AppSpacing.lg),
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 132,
          child: Text(
            label,
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}