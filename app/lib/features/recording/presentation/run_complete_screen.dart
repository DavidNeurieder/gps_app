/// Finish experience (§19).
///
/// Not a dashboard yet — just RUN COMPLETE, the result at a glance, and the
/// choice to move on. Detailed results arrive with M11.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/units.dart';
import '../../../engine/models.dart';
import '../application/recording_controller.dart';

class RunCompleteScreen extends ConsumerWidget {
  const RunCompleteScreen({super.key, required this.state});

  final LiveRunState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final controller = ref.read(recordingControllerProvider.notifier);
    final routeName = state.route?.name ?? 'New route';
    final gap = state.ghostGap;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Text(
                'RUN COMPLETE',
                textAlign: TextAlign.center,
                style: textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                routeName,
                textAlign: TextAlign.center,
                style: textTheme.bodyLarge?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                state.distance.format(),
                textAlign: TextAlign.center,
                style: textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                state.elapsed.formatClock(),
                textAlign: TextAlign.center,
                style: textTheme.headlineMedium?.copyWith(
                  color: AppColors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _GapLine(gap: gap),
              const Spacer(),
              FilledButton(
                onPressed: () {
                  controller.dismissRun();
                  context.go('/');
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.you,
                  foregroundColor: AppColors.background,
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text('DONE'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GapLine extends StatelessWidget {
  const _GapLine({required this.gap});

  final GhostState? gap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final gap = this.gap;
    if (gap == null) {
      return Text(
        'First time on this route',
        textAlign: TextAlign.center,
        style: textTheme.bodyMedium,
      );
    }
    final delta = gap.timeDifference.seconds.abs();
    final offset = Elapsed.seconds(delta).format();
    final ahead = gap.ahead;
    final color = ahead ? AppColors.ahead : AppColors.behind;
    final wording = ahead ? 'ahead of PB' : 'behind PB';
    return Text(
      delta == 0 ? 'Tied with PB' : '$offset $wording',
      textAlign: TextAlign.center,
      style: textTheme.titleLarge?.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}