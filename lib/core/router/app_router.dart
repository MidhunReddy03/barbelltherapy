import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth_lock/lock_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/members/enroll/enroll_screen.dart';
import '../../features/members/enroll/enroll_success.dart';
import '../../features/members/member_profile_screen.dart';
import '../../features/members/members_screen.dart';
import '../../features/more/announcements_screen.dart';
import '../../features/more/backup_screen.dart';
import '../../features/more/more_screen.dart';
import '../../features/more/payments_screen.dart';
import '../../features/more/plans_screen.dart';
import '../../features/more/reports_screen.dart';
import '../../features/more/settings_screen.dart';
import '../../features/more/templates_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/reminders/reminders_screen.dart';
import '../providers/providers.dart';

import '../../core/theme/app_colors.dart';

/// Navigation shell matching the HTML design (.nav and .nb):
/// height 76px, background #1F2226, top border #32373D, active top bar indicator #D98A5B.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: Container(
        height: 76,
        decoration: const BoxDecoration(
          color: AppColors.surfaceDark,
          border: Border(top: BorderSide(color: AppColors.borderDark)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _NavItem(
              index: 0,
              label: 'Home',
              icon: Icons.dashboard_outlined,
              activeIcon: Icons.dashboard,
              isSelected: shell.currentIndex == 0,
              onTap: () => shell.goBranch(0, initialLocation: shell.currentIndex == 0),
            ),
            _NavItem(
              index: 1,
              label: 'Members',
              icon: Icons.groups_outlined,
              activeIcon: Icons.groups,
              isSelected: shell.currentIndex == 1,
              onTap: () => shell.goBranch(1, initialLocation: shell.currentIndex == 1),
            ),
            _NavItem(
              index: 2,
              label: 'Reminders',
              icon: Icons.notifications_outlined,
              activeIcon: Icons.notifications,
              isSelected: shell.currentIndex == 2,
              onTap: () => shell.goBranch(2, initialLocation: shell.currentIndex == 2),
            ),
            _NavItem(
              index: 3,
              label: 'More',
              icon: Icons.menu,
              activeIcon: Icons.menu,
              isSelected: shell.currentIndex == 3,
              onTap: () => shell.goBranch(3, initialLocation: shell.currentIndex == 3),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.index,
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.isSelected,
    required this.onTap,
  });

  final int index;
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = isSelected ? AppColors.accentHighlight : AppColors.textSecondaryDark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(minWidth: 56),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Top active indicator bar (28x3px in #D98A5B)
            Container(
              width: 28,
              height: 3,
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Icon(isSelected ? activeIcon : icon, size: 22, color: fg),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final onboardingComplete = ref.watch(onboardingCompleteProvider);
  final lockEnabled = ref.watch(appLockEnabledProvider);
  final locked = ref.watch(lockedProvider);

  return GoRouter(
    initialLocation: '/home',
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final location = state.matchedLocation;
      if (!onboardingComplete) {
        return location == '/onboarding' ? null : '/onboarding';
      }
      if (lockEnabled && locked) {
        return location == '/lock' ? null : '/lock';
      }
      if (location == '/onboarding' || location == '/lock') {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        name: 'onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/lock',
        name: 'lock',
        builder: (context, state) => const LockScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/home',
              name: 'home',
              builder: (context, state) => const HomeScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/members',
              name: 'members',
              builder: (context, state) => const MembersScreen(),
              routes: [
                GoRoute(
                  path: 'enroll',
                  name: 'enroll',
                  builder: (context, state) => const EnrollScreen(),
                  routes: [
                    GoRoute(
                      path: 'success',
                      name: 'enrollSuccess',
                      builder: (context, state) {
                        final args = state.extra as EnrollSuccessArgs?;
                        if (args == null) {
                          // Deep-link safety: restart the enroll flow.
                          return const EnrollScreen();
                        }
                        return EnrollSuccessScreen(args: args);
                      },
                    ),
                  ],
                ),
                GoRoute(
                  path: ':id',
                  name: 'memberProfile',
                  builder: (context, state) {
                    final id = int.tryParse(state.pathParameters['id'] ?? '');
                    if (id == null) {
                      return const MembersScreen();
                    }
                    return MemberProfileScreen(memberId: id);
                  },
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/reminders',
              name: 'reminders',
              builder: (context, state) => const RemindersScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/more',
              name: 'more',
              builder: (context, state) => const MoreScreen(),
              routes: [
                GoRoute(
                  path: 'settings',
                  name: 'settings',
                  builder: (context, state) => const SettingsScreen(),
                ),
                GoRoute(
                  path: 'plans',
                  name: 'plans',
                  builder: (context, state) => const PlansScreen(),
                ),
                GoRoute(
                  path: 'payments',
                  name: 'payments',
                  builder: (context, state) => const PaymentsScreen(),
                ),
                GoRoute(
                  path: 'templates',
                  name: 'templates',
                  builder: (context, state) => const TemplatesScreen(),
                ),
                GoRoute(
                  path: 'announcements',
                  name: 'announcements',
                  builder: (context, state) => const AnnouncementsScreen(),
                ),
                GoRoute(
                  path: 'reports',
                  name: 'reports',
                  builder: (context, state) => const ReportsScreen(),
                ),
                GoRoute(
                  path: 'backup',
                  name: 'backup',
                  builder: (context, state) => const BackupScreen(),
                ),
              ],
            ),
          ]),
        ],
      ),
    ],
  );
});
