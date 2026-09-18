/// Route table for the app (§42): HOME / RECORD / ROUTES.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/activity/presentation/activity_detail_screen.dart';
import '../features/dev/presentation/diagnostics_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/recording/presentation/record_flow_screen.dart';
import '../features/result/presentation/result_screen.dart';
import '../features/routes/presentation/route_detail_screen.dart';
import '../features/routes/presentation/routes_screen.dart';
import 'app_shell.dart';

/// The triple-tab shell.
GoRouter buildRouter() {
  return GoRouter(
    initialLocation: '/',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const HomeScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/record',
              builder: (context, state) => const RecordFlowScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/routes',
              builder: (context, state) => const RoutesScreen(),
            ),
          ]),
        ],
      ),
// Full-screen overlays pushed above the shell (M11).
      GoRoute(
        path: '/record/result',
        builder: (context, state) => const ResultScreen(),
      ),
      // Developer diagnostics (M15 Phase 10). Always registered so tests and
      // deep links can reach it; only the shell entry button is gated.
      GoRoute(
        path: '/dev/diagnostics',
        builder: (context, state) => const DiagnosticsScreen(),
      ),
      GoRoute(
        path: '/activity/:id',
        builder: (context, state) => ActivityDetailScreen(
          activityId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/route/:id',
        builder: (context, state) =>
            RouteDetailScreen(routeId: state.pathParameters['id']!),
      ),
    ],
    errorBuilder: (context, state) => const _NotFound(),
  );
}

class _NotFound extends StatelessWidget {
  const _NotFound();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text('Nothing here',
            style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}