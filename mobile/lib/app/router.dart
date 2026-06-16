import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/state/providers.dart';
import '../features/auth/auth_screen.dart';
import '../features/coach/coach_screen.dart';
import '../features/diary/diary_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/scan/scan_review_screen.dart';
import '../features/scan/scan_screen.dart';
import '../features/search/search_screen.dart';
import '../features/today/today_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/today',
    redirect: (context, state) {
      final hasProfile = ref.read(profileProvider) != null;
      final goingToOnboarding = state.matchedLocation == '/onboarding';
      if (!hasProfile && !goingToOnboarding) return '/onboarding';
      if (hasProfile && goingToOnboarding) return '/today';
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/auth',
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        path: '/scan',
        builder: (context, state) => const ScanScreen(),
      ),
      GoRoute(
        path: '/scan/review',
        builder: (context, state) => const ScanReviewScreen(),
      ),
      GoRoute(
        path: '/search',
        builder: (context, state) => SearchScreen(
          initialMeal: state.uri.queryParameters['meal'],
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/today', builder: (c, s) => const TodayScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/diary', builder: (c, s) => const DiaryScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/coach', builder: (c, s) => const CoachScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/profile', builder: (c, s) => const ProfileScreen()),
          ]),
        ],
      ),
    ],
  );
});

class _AppShell extends StatelessWidget {
  const _AppShell({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      // Scan lives inside the bar as a styled center button — no floating
      // element overlapping content or nav labels.
      bottomNavigationBar: _BottomBar(shell: shell),
    );
  }
}

/// Custom 5-slot bottom bar: four tab branches with a contained "Scan" button
/// in the middle that routes to /scan without floating over anything.
class _BottomBar extends ConsumerWidget {
  const _BottomBar({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 3,
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: Row(
            children: [
              _tab(context, ref, 0, Icons.home_outlined, Icons.home, 'Today'),
              _tab(context, ref, 1, Icons.book_outlined, Icons.book, 'Diary'),
              _scanButton(context),
              _tab(context, ref, 2, Icons.chat_bubble_outline, Icons.chat_bubble, 'Coach'),
              _tab(context, ref, 3, Icons.person_outline, Icons.person, 'Profile'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab(BuildContext context, WidgetRef ref, int branch, IconData icon,
      IconData active, String label) {
    final scheme = Theme.of(context).colorScheme;
    final selected = shell.currentIndex == branch;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: () {
          // Leaving for the Today tab resets the diary's selected day so a
          // "tomorrow" planning session doesn't silently misfile later logs.
          if (branch == 0) {
            ref.read(selectedDateProvider.notifier).state = DateTime.now();
          }
          shell.goBranch(branch, initialLocation: branch == shell.currentIndex);
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? active : icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
          ],
        ),
      ),
    );
  }

  Widget _scanButton(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        onTap: () => context.push('/scan'),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration:
                  BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
              child: Icon(Icons.camera_alt_rounded,
                  color: scheme.onPrimary, size: 24),
            ),
            const SizedBox(height: 2),
            Text('Scan',
                style: TextStyle(
                    fontSize: 11,
                    color: scheme.primary,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
