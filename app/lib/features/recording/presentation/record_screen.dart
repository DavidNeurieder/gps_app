/// Pre-run recording screen (M6).
///
/// M6 will build the full recording state machine
/// (`preparing` → `GPS acquiring` → `ready` → `running` → …). Until then this
/// is a placeholder that proves navigation and the primary action hook up.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class RecordScreen extends StatelessWidget {
  const RecordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('New run')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.gps_fixed, size: 48, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(
              'Recording arrives with M6',
              style: textTheme.titleMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}