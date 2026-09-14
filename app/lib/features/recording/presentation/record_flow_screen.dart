/// The record tab — a state-machine driven flow (§8, §9).
///
/// One route, rendered as the right phase: pre-run, live, or complete. The UI
/// never mutates the machine; it only maps [`RunStatus`] to screens.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../engine/models.dart';
import '../../../persistence/persistence.dart';
import '../application/recording_controller.dart';
import 'live_run_screen.dart';
import 'pre_run_screen.dart';
import 'run_complete_screen.dart';

class RecordFlowScreen extends ConsumerStatefulWidget {
  const RecordFlowScreen({super.key});

  @override
  ConsumerState<RecordFlowScreen> createState() => _RecordFlowScreenState();
}

class _RecordFlowScreenState extends ConsumerState<RecordFlowScreen> {
  @override
  void initState() {
    super.initState();
    // Keep a fresh session ready whenever the flow has none (including after
    // a dismissed run), so visiting the tab always shows the pre-run screen.
    ref.listenManual(recordingControllerProvider, (_, next) {
      if (next == null) {
        _ensure();
      }
    });
    _ensure();
  }

  void _ensure() {
    final controller = ref.read(recordingControllerProvider.notifier);
    if (ref.read(recordingControllerProvider) == null) {
      final snapshot = ref.read(runSnapshotProvider);
      if (snapshot != null) {
        // M13 §28: an interrupted run was left behind — resume it instead of
        // starting a fresh session.
        controller.resumeFromSnapshot(snapshot);
      } else {
        controller.ensureSession(ref.read(routeRepositoryProvider));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(recordingControllerProvider);
    final status = state?.status ?? RunStatus.idle;
    return switch (status) {
      RunStatus.running || RunStatus.paused => LiveRunScreen(state: state!),
      RunStatus.finishing || RunStatus.completed =>
        RunCompleteScreen(state: state!),
      _ => PreRunScreen(state: state),
    };
  }
}