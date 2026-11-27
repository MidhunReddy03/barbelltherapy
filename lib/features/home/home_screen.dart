import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/repositories/dashboard_repository.dart';

final dashboardStatsProvider =
    StreamProvider.autoDispose<DashboardStats>((ref) {
  return ref.watch(dashboardRepositoryProvider).watchStats();
});

/// Home dashboard matching the exact design in GymDesk App Screens (page_0015adac.html).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gymName = ref.watch(gymNameProvider);
    final statsAsync = ref.watch(dashboardStatsProvider);
    final now = DateTime.now();

    final greeting = now.hour < 12
        ? 'Good morning'
        : now.hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    final dateStr = DateFormat('EEE d MMM').format(now);

    final showFloatingEnroll =
        !(kIsWeb && MediaQuery.sizeOf(context).width >= 820);

    return Scaffold(
      backgroundColor: kIsWeb ? Theme.of(context).scaffoldBackgroundColor : AppColors.bgDark,
      body: SafeArea(
        child: statsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
          error: (error, _) => Center(
            child: EmptyState(
              icon: Icons.error_outline,
              title: 'Something went wrong',
              hint: 'Couldn\'t load the dashboard. Tap to retry.',
              action: PrimaryButton(
                label: 'Retry',
                onPressed: () => ref.invalidate(dashboardStatsProvider),
              ),
            ),
          ),
          data: (stats) => RefreshIndicator(
            color: AppColors.accent,
            backgroundColor: AppColors.surfaceDark,
            onRefresh: () async => ref.invalidate(dashboardStatsProvider),
            child: Stack(
              children: [
                ListView(
                  padding: EdgeInsets.fromLTRB(
                    kIsWeb ? 24 : 18,
                    kIsWeb ? 20 : 16,
                    kIsWeb ? 24 : 18,
                    90,
                  ),
                  children: [
                    // Top Bar Header
                    _Header(dateStr: dateStr, greeting: greeting, gymName: gymName),
                    const SizedBox(height: 14),

                    // Responsive Metric Stat Grid
                    _StatGrid(stats: stats),
                    const SizedBox(height: 12),

                    // Reminders Banner
                    if (stats.pendingReminders > 0) ...[
                      _RemindersBanner(stats: stats),
                      const SizedBox(height: 12),
                    ],

                    // Pending Dues Card
                    _PendingDuesCard(stats: stats),
                    const SizedBox(height: 12),

                    // Joined vs Lapsed Summary Cards
                    _JoinedLapsedRow(stats: stats),
                    const SizedBox(height: 20),
                  ],
                ),

                if (showFloatingEnroll)
                // Floating Enroll Button matching HTML design:
                // height 50px, border-radius 25px, background #D98A5B, text #17191C, bold
                Positioned(
                  right: 18,
                  bottom: 18,
                  child: Material(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(25),
                    elevation: 6,
                    shadowColor: Colors.black.withValues(alpha: 0.4),
                    child: InkWell(
                      onTap: () => context.go('/members/enroll'),
                      borderRadius: BorderRadius.circular(25),
                      child: Container(
                        height: 50,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person_add_alt_1, size: 20, color: Theme.of(context).colorScheme.onPrimary),
                            const SizedBox(width: 8),
                            Text(
                              'Enroll',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.dateStr,
    required this.greeting,
    required this.gymName,
  });

  final String dateStr;
  final String greeting;
  final String gymName;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$dateStr · $greeting',
                style: AppTheme.cap(color: AppColors.textSecondaryDark),
              ),
              const SizedBox(height: 2),
              Text(
                gymName.toUpperCase(),
                style: AppTheme.dsp(fontSize: 30, fontWeight: FontWeight.w700, color: AppColors.textPrimaryDark),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        // Notifications button (44x44 card with dot)
        InkWell(
          onTap: () => context.go('/reminders'),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 44,
            height: 44,
            decoration: AppTheme.cardDecoration(),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.notifications_none, size: 22, color: AppColors.textPrimaryDark),
                Positioned(
                  top: 10,
                  right: 11,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats});

  final DashboardStats stats;

  @override
  Widget build(BuildContext context) {
    final cards = [
      // Active
      _MetricCard(
        dotColor: AppColors.statusActive,
        capLabel: 'ACTIVE',
        value: '${stats.activeMembers}',
        subtitle: '+${stats.joinedThisMonth} this month',
        subtitleColor: AppColors.statusActive,
        onTap: () => context.go('/members'),
      ),
      // Expiring this week
      _MetricCard(
        dotColor: AppColors.statusExpiring,
        capLabel: 'EXPIRING THIS WEEK',
        value: '${stats.expiringThisWeek}',
        valueColor: AppColors.statusExpiring,
        subtitle: 'Tap to view',
        subtitleColor: AppColors.textSecondaryDark,
        onTap: () => context.go('/members'),
      ),
      // Today
      _MetricCard(
        capLabel: 'TODAY',
        value: AppFormatters.money(stats.todaysCollection),
        subtitle: '${stats.todayPaymentCount} payments',
        subtitleColor: AppColors.textSecondaryDark,
        onTap: () => context.go('/more/payments'),
      ),
      // This month
      _MetricCard(
        capLabel: 'THIS MONTH',
        value: AppFormatters.money(stats.monthRevenue),
        subtitle: '+${stats.joinedThisMonth} new joins',
        subtitleColor: AppColors.statusActive,
        onTap: () => context.go('/more/payments'),
      ),
    ];

    if (kIsWeb) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final cols = constraints.maxWidth >= 700 ? 4 : 2;
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 128,
            ),
            itemCount: cards.length,
            itemBuilder: (_, i) => cards[i],
          );
        },
      );
    }

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.55,
      children: cards,
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.capLabel,
    required this.value,
    this.valueColor,
    required this.subtitle,
    this.subtitleColor,
    this.dotColor,
    this.onTap,
  });

  final String capLabel;
  final String value;
  final Color? valueColor;
  final String subtitle;
  final Color? subtitleColor;
  final Color? dotColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (dotColor != null) ...[
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                ),
              ],
              Text(
                capLabel,
                style: AppTheme.cap(color: dotColor != null ? AppColors.textPrimaryDark : AppColors.textSecondaryDark),
              ),
            ],
          ),
          Text(
            value,
            style: AppTheme.dsp(
              fontSize: 36,
              fontWeight: FontWeight.w600,
              color: valueColor ?? AppColors.textPrimaryDark,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: subtitleColor ?? AppColors.textSecondaryDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _RemindersBanner extends StatelessWidget {
  const _RemindersBanner({required this.stats});

  final DashboardStats stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.accentDarkContainer,
        borderRadius: BorderRadius.circular(AppColors.radius),
        border: Border.all(color: AppColors.accentDarkBorder),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${stats.pendingReminders} REMINDERS TODAY',
                  style: AppTheme.dsp(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.textPrimaryDark),
                ),
                const SizedBox(height: 2),
                Text(
                  'Expiring memberships & dues to follow up',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondaryDark),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => context.go('/reminders'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.onAccent,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }
}

class _PendingDuesCard extends StatelessWidget {
  const _PendingDuesCard({required this.stats});

  final DashboardStats stats;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PENDING DUES', style: AppTheme.cap(color: AppColors.textSecondaryDark)),
                const SizedBox(height: 2),
                RichText(
                  text: TextSpan(
                    text: AppFormatters.money(stats.totalDue),
                    style: AppTheme.dsp(
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      color: stats.totalDue > 0 ? AppColors.statusExpired : AppColors.statusActive,
                    ),
                    children: [
                      TextSpan(
                        text: ' from ${stats.membersWithDues} member${stats.membersWithDues == 1 ? '' : 's'}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondaryDark,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () => context.go('/more/payments'),
            style: OutlinedButton.styleFrom(
              backgroundColor: AppColors.surfaceRaisedDark,
              foregroundColor: AppColors.textPrimaryDark,
              side: const BorderSide(color: AppColors.borderDark),
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            child: const Text('View'),
          ),
        ],
      ),
    );
  }
}

class _JoinedLapsedRow extends StatelessWidget {
  const _JoinedLapsedRow({required this.stats});

  final DashboardStats stats;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('JOINED', style: AppTheme.cap(color: AppColors.textSecondaryDark)),
                Text(
                  '+${stats.joinedThisMonth}',
                  style: AppTheme.dsp(fontSize: 28, fontWeight: FontWeight.w600, color: AppColors.statusActive),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('LAPSED', style: AppTheme.cap(color: AppColors.textSecondaryDark)),
                Text(
                  '${stats.lapsedThisMonth}',
                  style: AppTheme.dsp(fontSize: 28, fontWeight: FontWeight.w600, color: AppColors.statusExpired),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
