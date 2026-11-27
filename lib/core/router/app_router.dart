import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/web_themes.dart';
import '../../data/repositories/settings_repository.dart';

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
import '../../features/more/sync_screen.dart';
import '../../features/more/templates_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/reminders/reminders_screen.dart';
import '../providers/providers.dart';

/// Navigation shell matching the HTML design (.nav and .nb) on mobile,
/// and a responsive sidebar + centered workspace ONLY on desktop web (`kIsWeb`).
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    if (kIsWeb && width >= 820) {
      final preset = ref.watch(webThemePresetProvider);
      final gymName = ref.watch(gymNameProvider);
      return Scaffold(
        backgroundColor: preset.bg,
        body: Row(
          children: [
            _WebSidebar(
              shell: shell,
              preset: preset,
              gymName: gymName,
              onSelectTheme: (p) => ref
                  .read(settingsRepositoryProvider)
                  .set(SettingKeys.webThemePreset, p.id),
            ),
            Expanded(
              child: Container(
                color: preset.bg,
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1080),
                  child: shell,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final preset = kIsWeb ? ref.watch(webThemePresetProvider) : null;
    final navBg = preset?.surface ?? AppColors.surfaceDark;
    final navBorder = preset?.border ?? AppColors.borderDark;
    final activeColor = preset?.accentHighlight ?? AppColors.accentHighlight;
    final indicatorColor = preset?.accent ?? AppColors.accent;
    final inactiveColor = preset?.textSecondary ?? AppColors.textSecondaryDark;

    return Scaffold(
      body: kIsWeb
          ? Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: shell,
              ),
            )
          : shell,
      bottomNavigationBar: Container(
        height: 76,
        decoration: BoxDecoration(
          color: navBg,
          border: Border(top: BorderSide(color: navBorder)),
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
              activeColor: activeColor,
              indicatorColor: indicatorColor,
              inactiveColor: inactiveColor,
              onTap: () => shell.goBranch(0, initialLocation: shell.currentIndex == 0),
            ),
            _NavItem(
              index: 1,
              label: 'Members',
              icon: Icons.groups_outlined,
              activeIcon: Icons.groups,
              isSelected: shell.currentIndex == 1,
              activeColor: activeColor,
              indicatorColor: indicatorColor,
              inactiveColor: inactiveColor,
              onTap: () => shell.goBranch(1, initialLocation: shell.currentIndex == 1),
            ),
            _NavItem(
              index: 2,
              label: 'Reminders',
              icon: Icons.notifications_outlined,
              activeIcon: Icons.notifications,
              isSelected: shell.currentIndex == 2,
              activeColor: activeColor,
              indicatorColor: indicatorColor,
              inactiveColor: inactiveColor,
              onTap: () => shell.goBranch(2, initialLocation: shell.currentIndex == 2),
            ),
            _NavItem(
              index: 3,
              label: 'More',
              icon: Icons.menu,
              activeIcon: Icons.menu,
              isSelected: shell.currentIndex == 3,
              activeColor: activeColor,
              indicatorColor: indicatorColor,
              inactiveColor: inactiveColor,
              onTap: () => shell.goBranch(3, initialLocation: shell.currentIndex == 3),
            ),
          ],
        ),
      ),
    );
  }
}

class _WebSidebar extends StatelessWidget {
  const _WebSidebar({
    required this.shell,
    required this.preset,
    required this.gymName,
    required this.onSelectTheme,
  });

  final StatefulNavigationShell shell;
  final WebThemePreset preset;
  final String gymName;
  final ValueChanged<WebThemePreset> onSelectTheme;

  @override
  Widget build(BuildContext context) {
    final navItems = const [
      (0, 'Home', Icons.dashboard_outlined, Icons.dashboard),
      (1, 'Members', Icons.groups_outlined, Icons.groups),
      (2, 'Reminders', Icons.notifications_outlined, Icons.notifications),
      (3, 'More', Icons.tune_outlined, Icons.tune),
    ];

    return Container(
      width: 256,
      decoration: BoxDecoration(
        color: preset.surface,
        border: Border(right: BorderSide(color: preset.border)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: preset.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: preset.accent.withValues(alpha: 0.5)),
                ),
                child: Icon(Icons.fitness_center, color: preset.accent, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BARBELL THERAPY',
                      style: AppTheme.dsp(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: preset.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      gymName,
                      style: TextStyle(fontSize: 11, color: preset.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: () => context.go('/members/enroll'),
              icon: Icon(Icons.person_add_alt_1, size: 18, color: preset.onAccent),
              label: Text(
                'Enroll Member',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: preset.onAccent,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: preset.accent,
                foregroundColor: preset.onAccent,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('NAVIGATION', style: AppTheme.cap(color: preset.textSecondary)),
          const SizedBox(height: 8),
          for (final (idx, label, icon, activeIcon) in navItems) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Material(
                color: shell.currentIndex == idx
                    ? preset.accent.withValues(alpha: 0.14)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: () => shell.goBranch(idx, initialLocation: shell.currentIndex == idx),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: shell.currentIndex == idx
                            ? preset.accent.withValues(alpha: 0.45)
                            : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          shell.currentIndex == idx ? activeIcon : icon,
                          size: 20,
                          color: shell.currentIndex == idx
                              ? preset.accentHighlight
                              : preset.textSecondary,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: shell.currentIndex == idx
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: shell.currentIndex == idx
                                ? preset.textPrimary
                                : preset.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
          const Spacer(),
          Text('WEBSITE THEME', style: AppTheme.cap(color: preset.textSecondary)),
          const SizedBox(height: 8),
          for (final item in WebThemePreset.values) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: InkWell(
                onTap: () => onSelectTheme(item),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: item == preset ? preset.surfaceRaised : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: item == preset ? preset.accent : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: item.accent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item.name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: item == preset ? FontWeight.w600 : FontWeight.w400,
                            color: item == preset ? preset.textPrimary : preset.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (item == preset)
                        Icon(Icons.check, size: 14, color: preset.accentHighlight),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
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
    required this.activeColor,
    required this.indicatorColor,
    required this.inactiveColor,
    required this.onTap,
  });

  final int index;
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool isSelected;
  final Color activeColor;
  final Color indicatorColor;
  final Color inactiveColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = isSelected ? activeColor : inactiveColor;
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
            // Top active indicator bar (28x3px)
            Container(
              width: 28,
              height: 3,
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: isSelected ? indicatorColor : Colors.transparent,
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
        builder: (context, state) => kIsWeb
            ? Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: const OnboardingScreen(),
                ),
              )
            : const OnboardingScreen(),
      ),
      GoRoute(
        path: '/lock',
        name: 'lock',
        builder: (context, state) => kIsWeb
            ? Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: const LockScreen(),
                ),
              )
            : const LockScreen(),
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
                GoRoute(
                  path: 'sync',
                  name: 'sync',
                  builder: (context, state) => const SyncScreen(),
                ),
              ],
            ),
          ]),
        ],
      ),
    ],
  );
});
