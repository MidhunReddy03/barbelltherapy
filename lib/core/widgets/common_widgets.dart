import 'package:material_ui/material_ui.dart';

import '../theme/app_colors.dart';

/// Empty state with an icon and a one-line hint (spec 3).
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? hint;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (hint != null) ...[
              const SizedBox(height: 8),
              Text(
                hint!,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Rounded section card matching .card from the HTML design:
/// background: #1F2226; border: 1px solid #32373D; border-radius: 14px;
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
    this.borderColor,
    this.backgroundColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? borderColor;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = backgroundColor ??
        (isDark ? AppColors.surfaceDark : AppColors.surfaceLight);
    final border = borderColor ??
        (isDark ? AppColors.borderDark : AppColors.borderLight);
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(AppColors.radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppColors.radius),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppColors.radius),
            border: Border.all(color: border),
          ),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

/// Big primary action button matching HTML design (Terracotta #D98A5B, text #17191C, weight 700).
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expanded = false,
    this.height = 50,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;
  final double height;

  @override
  Widget build(BuildContext context) {
    final style = ElevatedButton.styleFrom(
      backgroundColor: AppColors.accent,
      foregroundColor: AppColors.onAccent,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      minimumSize: Size(0, height),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    );

    final textWidget = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(label, maxLines: 1),
    );

    final button = icon != null
        ? ElevatedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            label: textWidget,
            style: style,
          )
        : ElevatedButton(
            onPressed: onPressed,
            style: style,
            child: textWidget,
          );

    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Outlined/raised secondary button matching HTML design (bg #282C31, border #32373D, text #EEEAE3).
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expanded = false,
    this.height = 50,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.surfaceRaisedDark : AppColors.surfaceRaisedLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final fg = color ?? (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight);

    final style = OutlinedButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: fg,
      elevation: 0,
      side: BorderSide(color: border),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      minimumSize: Size(0, height),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: fg),
    );

    final textWidget = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(label, maxLines: 1),
    );

    final button = icon != null
        ? OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 18, color: fg),
            label: textWidget,
            style: style,
          )
        : OutlinedButton(
            onPressed: onPressed,
            style: style,
            child: textWidget,
          );

    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}
