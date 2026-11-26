import 'package:material_ui/material_ui.dart';

import '../../domain/membership_status.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/app_image.dart';

/// Colored status pill chip matching GymDesk HTML design:
/// font-size: 11px; font-weight: 600; padding: 3px 9px; border-radius: 8px;
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status, this.compact = false});

  final MembershipStatus status;
  final bool compact;

  static Color colorFor(MembershipStatus status) {
    switch (status) {
      case MembershipStatus.active:
        return AppColors.statusActive;
      case MembershipStatus.expiringSoon:
        return AppColors.statusExpiring;
      case MembershipStatus.expired:
        return AppColors.statusExpired;
      case MembershipStatus.frozen:
        return AppColors.statusFrozen;
      case MembershipStatus.upcoming:
        return AppColors.statusUpcoming;
      case MembershipStatus.noPlan:
        return AppColors.statusNoPlan;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = colorFor(status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// Circle avatar showing a member photo or styled initials in Barlow Condensed.
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({
    super.key,
    required this.name,
    this.photoPath,
    this.radius = 22,
    this.status,
  });

  final String name;
  final String? photoPath;
  final double radius;
  final MembershipStatus? status;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoPath != null && photoPath!.isNotEmpty;
    final fg = status != null ? StatusPill.colorFor(status!) : AppColors.accent;
    final bg = fg.withValues(alpha: 0.15);

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bg,
      ),
      clipBehavior: Clip.antiAlias,
      child: hasPhoto
          ? Stack(
              fit: StackFit.expand,
              children: [
                _initials(fg),
                AppImage.view(
                  photoPath,
                  width: radius * 2,
                  height: radius * 2,
                ),
              ],
            )
          : _initials(fg),
    );
  }

  Widget _initials(Color fg) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    return Center(
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: AppTheme.dsp(
          fontSize: radius * 0.9,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

/// Small rounded badge, e.g. `₹500 due`.
class DueBadge extends StatelessWidget {
  const DueBadge({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.statusExpired.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.statusExpired,
        ),
      ),
    );
  }
}
