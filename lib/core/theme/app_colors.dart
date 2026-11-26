import 'package:material_ui/material_ui.dart';

/// Design-system colors from the GymDesk App Screens HTML.
class AppColors {
  AppColors._();

  // Dark theme surfaces
  static const Color bgDark = Color(0xFF17191C);
  static const Color surfaceDark = Color(0xFF1F2226);
  static const Color surfaceRaisedDark = Color(0xFF282C31);
  static const Color borderDark = Color(0xFF32373D);

  // Light theme surfaces
  static const Color bgLight = Color(0xFFFAF9F5);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceRaisedLight = Color(0xFFF1EFEA);
  static const Color borderLight = Color(0xFFE2DDD5);

  // Accent (Terracotta / Copper)
  static const Color accent = Color(0xFFD98A5B);
  static const Color accentHighlight = Color(0xFFE0966A);
  static const Color onAccent = Color(0xFF17191C);
  static const Color accentDarkContainer = Color(0xFF2A2420);
  static const Color accentDarkBorder = Color(0xFF4A3A2E);

  // Text
  static const Color textPrimaryDark = Color(0xFFEEEAE3);
  static const Color textSecondaryDark = Color(0xFFA5A199);
  static const Color textMutedDark = Color(0xFF78746D);

  static const Color textPrimaryLight = Color(0xFF1F2226);
  static const Color textSecondaryLight = Color(0xFF6B6760);

  // Status colors (matching HTML screens)
  static const Color statusActive = Color(0xFF8DBB9A);
  static const Color statusExpiring = Color(0xFFDDB872);
  static const Color statusExpired = Color(0xFFDE8A82);
  static const Color statusFrozen = Color(0xFF8DB0D0);
  static const Color statusUpcoming = Color(0xFFA78BFA);
  static const Color statusNoPlan = Color(0xFFA5A199);

  // WhatsApp Message Preview
  static const Color whatsappBubble = Color(0xFF22352C);
  static const Color whatsappText = Color(0xFFE4EEE7);

  /// Radius used by cards / sheets (14px from HTML design).
  static const double radius = 14;

  /// Minimum tap target.
  static const double minTapTarget = 48;
}
