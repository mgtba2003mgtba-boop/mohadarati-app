import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

/// ويدجت أيقونة عصرية ذات شكل هندسي أنيق وتدرجات وظلال خفيفة (Modern Squircle Icon Badge)
class AppIconBadge extends StatelessWidget {
  final IconData icon;
  final double size;
  final double iconSize;
  final Color? color;
  final Color? iconColor;
  final Gradient? gradient;
  final double borderRadius;
  final bool showBorder;
  final bool showShadow;

  const AppIconBadge({
    super.key,
    required this.icon,
    this.size = 44,
    this.iconSize = 22,
    this.color,
    this.iconColor,
    this.gradient,
    this.borderRadius = 14,
    this.showBorder = true,
    this.showShadow = true,
  });

  /// نمط مسبق: أزرق نيلي أكاديمي ملكي
  factory AppIconBadge.indigo({
    required IconData icon,
    double size = 44,
    double iconSize = 22,
  }) {
    return AppIconBadge(
      icon: icon,
      size: size,
      iconSize: iconSize,
      gradient: const LinearGradient(
        colors: [Color(0xFF4F46E5), Color(0xFF3730A3)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      iconColor: Colors.white,
      showBorder: false,
    );
  }

  /// نمط مسبق: أزرق سماوي حيوي
  factory AppIconBadge.sky({
    required IconData icon,
    double size = 44,
    double iconSize = 22,
  }) {
    return AppIconBadge(
      icon: icon,
      size: size,
      iconSize: iconSize,
      gradient: const LinearGradient(
        colors: [Color(0xFF0EA5E9), Color(0xFF0284C7)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      iconColor: Colors.white,
      showBorder: false,
    );
  }

  /// نمط مسبق: زمردي نجاح
  factory AppIconBadge.emerald({
    required IconData icon,
    double size = 44,
    double iconSize = 22,
  }) {
    return AppIconBadge(
      icon: icon,
      size: size,
      iconSize: iconSize,
      gradient: const LinearGradient(
        colors: [Color(0xFF10B981), Color(0xFF059669)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      iconColor: Colors.white,
      showBorder: false,
    );
  }

  /// نمط مسبق: كهرماني ذهبي للمواعيد والتقويم
  factory AppIconBadge.amber({
    required IconData icon,
    double size = 44,
    double iconSize = 22,
  }) {
    return AppIconBadge(
      icon: icon,
      size: size,
      iconSize: iconSize,
      gradient: const LinearGradient(
        colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      iconColor: Colors.white,
      showBorder: false,
    );
  }

  /// نمط مسبق: ناعم وهادئ مع تلوين طفيف
  factory AppIconBadge.subtle({
    required IconData icon,
    Color color = AppTheme.primary,
    double size = 42,
    double iconSize = 20,
  }) {
    return AppIconBadge(
      icon: icon,
      size: size,
      iconSize: iconSize,
      color: color.withValues(alpha: 0.12),
      iconColor: color,
      showBorder: true,
      showShadow: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppTheme.primarySubtle;
    final effectiveIconColor = iconColor ?? AppTheme.primary;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: gradient == null ? effectiveColor : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(borderRadius),
        border: showBorder
            ? Border.all(
                color: (iconColor ?? AppTheme.primary).withValues(alpha: 0.2),
                width: 1.2,
              )
            : null,
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: (iconColor ?? AppTheme.primary).withValues(alpha: 0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Center(
        child: Icon(
          icon,
          size: iconSize,
          color: effectiveIconColor,
        ),
      ),
    );
  }
}
