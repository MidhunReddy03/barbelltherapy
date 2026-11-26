import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// "More" hub: Plans & Add-ons, Payments & Dues, Announcements,
/// Reports, Message Templates, Backup & Restore, Settings.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = <_MoreItem>[
      const _MoreItem(
        icon: Icons.card_membership_outlined,
        title: 'Plans & Add-ons',
        subtitle: 'Plan prices, durations, admission fee presets',
        route: '/more/plans',
      ),
      const _MoreItem(
        icon: Icons.payments_outlined,
        title: 'Payments & Dues',
        subtitle: 'Pending dues list, Day Book, payment receipts',
        route: '/more/payments',
      ),
      const _MoreItem(
        icon: Icons.campaign_outlined,
        title: 'Announcements',
        subtitle: 'Bulk WhatsApp broadcasts filtered by member status',
        route: '/more/announcements',
      ),
      const _MoreItem(
        icon: Icons.assessment_outlined,
        title: 'Reports & Exports',
        subtitle: 'Export Excel sheets & monthly PDF accounting packs',
        route: '/more/reports',
      ),
      const _MoreItem(
        icon: Icons.message_outlined,
        title: 'Message Templates',
        subtitle: 'Customize English & Telugu WhatsApp notification copy',
        route: '/more/templates',
      ),
      const _MoreItem(
        icon: Icons.backup_outlined,
        title: 'Backup & Restore',
        subtitle: 'Export encrypted offline ZIP snapshot of database',
        route: '/more/backup',
      ),
      const _MoreItem(
        icon: Icons.settings_outlined,
        title: 'Settings',
        subtitle: 'Gym profile, PIN lock, theme mode, default language',
        route: '/more/settings',
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgDark,
        elevation: 0,
        title: Text(
          'MORE',
          style: AppTheme.dsp(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimaryDark,
            letterSpacing: 0.04,
          ),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final item = items[i];
          return _MoreTile(
            item: item,
            onTap: () => context.go(item.route),
          );
        },
      ),
    );
  }
}

class _MoreItem {
  const _MoreItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({required this.item, required this.onTap});

  final _MoreItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderDark),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.surfaceRaisedDark,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.borderDark),
                ),
                child: Icon(item.icon, color: AppColors.accent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimaryDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondaryDark,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: AppColors.textSecondaryDark,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
