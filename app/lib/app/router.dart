/// Route table for the app (§42): HOME / RECORD / ROUTES.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/home/presentation/home_screen.dart';
import '../features/recording/presentation/record_flow_screen.dart';
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
    ],
    errorBuilder: (context, state) => const _NotFound(),
  );
}

class _NotFound extends StatelessWidget {
  const _NotFound();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: Text('Nothing here', style: Theme.of(context).textTheme.titleMedium)),
    );
  }
}