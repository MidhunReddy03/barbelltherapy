import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/app_image.dart';
import '../../core/widgets/status_pill.dart';
import '../../domain/membership_status.dart';

/// Member card preview (spec 6.4 success screen): photo, name, member code,
/// QR of the member code, plan and end date. Also rendered offstage for
/// "Share member card (image)" capture.
class MemberCard extends StatelessWidget {
  const MemberCard({
    super.key,
    required this.gymName,
    required this.memberName,
    required this.memberCode,
    required this.planName,
    required this.endsLabel,
    this.photoPath,
    this.status,
    this.size = const Size(340, 200),
  });

  final String gymName;
  final String memberName;
  final String memberCode;
  final String planName;
  final String endsLabel;
  final String? photoPath;
  final MembershipStatus? status;
  final Size size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size.width,
      height: size.height,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF181B21), Color(0xFF20242C)],
        ),
        borderRadius: BorderRadius.circular(AppColors.radius),
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  gymName.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: AppColors.textSecondaryDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 44,
                        height: 44,
                        color: AppColors.surfaceRaisedDark,
                        child: (photoPath != null && photoPath!.isNotEmpty)
                            ? AppImage.view(photoPath)
                            : const Icon(
                                Icons.person,
                                color: AppColors.textSecondaryDark,
                              ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            memberName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimaryDark,
                            ),
                          ),
                          Text(
                            memberCode,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  planName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  endsLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondaryDark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: QrImageView(
                  data: memberCode,
                  size: 88,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    color: Colors.black,
                    dataModuleShape: QrDataModuleShape.square,
                  ),
                ),
              ),
              const Spacer(),
              if (status != null) StatusPill(status: status!, compact: true),
            ],
          ),
        ],
      ),
    );
  }
}
