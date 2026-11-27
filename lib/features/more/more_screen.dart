import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/web_themes.dart';
import '../../data/repositories/settings_repository.dart';

/// "More" hub: Plans & Add-ons, Payments & Dues, Announcements,
/// Reports, Message Templates, Backup & Restore, Settings.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        icon: Icons.cloud_sync_outlined,
        title: 'Cloud Sync (2 Phones + Web)',
        subtitle: 'Auto-sync members, plans & payments across all devices',
        route: '/more/sync',
      ),
      const _MoreItem(
        icon: Icons.backup_outlined,
        title: 'Backup & Restore',
        subtitle: 'Export offline ZIP snapshot or send to Gmail',
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
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          if (kIsWeb) ...[
            _WebThemePickerCard(ref: ref),
            const SizedBox(height: 14),
          ],
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _MoreTile(
              item: items[i],
              onTap: () => context.go(items[i].route),
            ),
          ],
        ],
      ),
    );
  }
}

class _WebThemePickerCard extends StatelessWidget {
  const _WebThemePickerCard({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(webThemePresetProvider);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: current.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: current.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('WEBSITE UI THEME', style: AppTheme.cap(color: current.textSecondary)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in WebThemePreset.values)
                InkWell(
                  onTap: () => ref
                      .read(settingsRepositoryProvider)
                      .set(SettingKeys.webThemePreset, preset.id),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: preset == current ? preset.surfaceRaised : current.bg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: preset == current ? preset.accent : current.border,
                        width: preset == current ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: preset.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          preset.name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: preset == current ? FontWeight.w700 : FontWeight.w500,
                            color: current.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
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
