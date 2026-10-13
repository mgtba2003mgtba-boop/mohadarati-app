import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ثيم وهوية التطبيق الأكاديمية - نمط عصري أنيق ومضيء (Light Modern Academic)
class AppTheme {
  // الألوان الرئيسية الفاتحة والفاخرة
  static const Color primary = Color(0xFF4F46E5); // نيلي أكاديمي ملكي زاهي (Royal Indigo)
  static const Color primaryDark = Color(0xFF3730A3);
  static const Color primaryLight = Color(0xFF6366F1); // إنديجو ناعم
  static const Color primarySubtle = Color(0xFFEEF2FF); // خلفية إنديجو فائقة النعومة
  static const Color accent = Color(0xFF0EA5E9); // سيان / أزرق سماوي حيوي (Vibrant Sky)
  static const Color accentSubtle = Color(0xFFE0F2FE);

  // ألوان الخلفيات للوضع الفاتح الأنيق (Light Mode)
  static const Color lightBg = Color(0xFFF8FAFC); // رمادي رخامي ناعم مريح للعين (Slate-50)
  static const Color lightCard = Color(0xFFFFFFFF); // أبيض ناصع للبطاقات (Pure White)
  static const Color lightSurface = Color(0xFFF1F5F9); // سطح رمادي خفيف للتحديد (Slate-100)
  static const Color lightBorder = Color(0xFFE2E8F0); // حدود ناعمة وأنيقة (Slate-200)

  // توافق مع الأسماء السابقة لضمان عدم حدوث كسر بالواجهات
  static const Color darkBg = lightBg;
  static const Color darkCard = lightCard;
  static const Color darkSurface = lightSurface;
  static const Color darkBorder = lightBorder;

  // ألوان النصوص الفاتحة (عالية التباين والوضوح)
  static const Color textPrimary = Color(0xFF0F172A); // كحلي فحمي داكن ناصع (Slate-900)
  static const Color textSecondary = Color(0xFF475569); // رمادي وسطي واضح (Slate-600)
  static const Color textMuted = Color(0xFF94A3B8); // رمادي فرعي هادئ (Slate-400)

  // ألوان الحالات (Success, Warning, Danger, Info)
  static const Color success = Color(0xFF10B981); // زمردي حيوي
  static const Color successSubtle = Color(0xFFECFDF5);
  static const Color warning = Color(0xFFF59E0B); // كهرماني ذهبي
  static const Color warningSubtle = Color(0xFFFFFBEB);
  static const Color danger = Color(0xFFEF4444); // أحمر ياقوتي
  static const Color dangerSubtle = Color(0xFFFEF2F2);
  static const Color info = Color(0xFF0284C7); // أزرق معلوماتي ناصع
  static const Color infoSubtle = Color(0xFFF0F9FF);

  // ظلال ناعمة راقية للبطاقات
  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: 0.04),
          blurRadius: 12,
          spreadRadius: 0,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: 0.02),
          blurRadius: 4,
          spreadRadius: 0,
          offset: const Offset(0, 1),
        ),
      ];

  static List<BoxShadow> get primaryGlow => [
        BoxShadow(
          color: primary.withValues(alpha: 0.25),
          blurRadius: 16,
          spreadRadius: 0,
          offset: const Offset(0, 6),
        ),
      ];

  static ThemeData get lightTheme {
    final baseFont = GoogleFonts.cairoTextTheme(ThemeData.light().textTheme);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: primary,
      scaffoldBackgroundColor: lightBg,
      cardColor: lightCard,
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: accent,
        surface: lightCard,
        error: danger,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
      ),
      textTheme: baseFont.apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 1.5,
        shadowColor: Colors.black.withValues(alpha: 0.05),
        titleTextStyle: GoogleFonts.cairo(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
        iconTheme: const IconThemeData(color: textPrimary),
      ),
      cardTheme: CardThemeData(
        color: lightCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: lightBorder, width: 1.0),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightSurface,
        hintStyle: GoogleFonts.cairo(color: textMuted, fontSize: 13),
        labelStyle: GoogleFonts.cairo(color: textSecondary, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: danger, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.cairo(
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primary, width: 1.2),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.cairo(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: primary,
        unselectedItemColor: Color(0xFF94A3B8),
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        unselectedLabelStyle: TextStyle(fontSize: 11),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
    );
  }

  // دعم الاستدعاء الافتراضي
  static ThemeData get darkTheme => lightTheme;
}
