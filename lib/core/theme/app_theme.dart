import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';

/// ══════════════════════════════════════════════════════════════════════════════
/// نظام التصميم الأكاديمي النخبوي (Mohadarati Academic Design System)
/// يعتمد على شبكة 8-Point Spatial Grid، تباين WCAG AAA، وطباعة عربية متوازنة
/// ══════════════════════════════════════════════════════════════════════════════

/// مقاييس المسافات الصارمة (8-Point Grid System)
abstract class AppSpacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 40.0;
  static const double xxxl = 48.0;
}

/// أنصاف أقطار الحواف الدائرية (Border Radius Hierarchy)
abstract class AppRadius {
  static const double xs = 6.0;
  static const double sm = 10.0;
  static const double md = 14.0;
  static const double lg = 18.0;
  static const double xl = 24.0;
  static const double pill = 999.0;

  static BorderRadius get roundedXs => BorderRadius.circular(xs);
  static BorderRadius get roundedSm => BorderRadius.circular(sm);
  static BorderRadius get roundedMd => BorderRadius.circular(md);
  static BorderRadius get roundedLg => BorderRadius.circular(lg);
  static BorderRadius get roundedXl => BorderRadius.circular(xl);
  static BorderRadius get roundedPill => BorderRadius.circular(pill);
}

/// مقاييس التفاعل الفيزيائي ومساحات اللمس القياسية
abstract class AppTouchTarget {
  static const double minSize = 48.0; // الحد الأدنى العالمي لمساحة النقر (WCAG & HIG)
}

/// فيزياء الحركة وتوقيتات الانتقال الناعمة لشاشات 120Hz
abstract class AppMotion {
  static const Duration fast = Duration(milliseconds: 140);
  static const Duration normal = Duration(milliseconds: 240);
  static const Duration smooth = Duration(milliseconds: 360);
  static const Duration slow = Duration(milliseconds: 500);

  static const Curve spring = Curves.easeInOutCubic;
  static const Curve overshoot = Curves.easeOutBack;
  static const Curve decelerate = Curves.easeOutCubic;
}

/// الظلال الاتجاهية والعمق المحيطي (Directional Ambient Occlusion Shadows)
abstract class AppShadows {
  /// ظل ناعم خفيف جداً
  static List<BoxShadow> get subtle => [
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: 0.025),
          blurRadius: 6,
          spreadRadius: 0,
          offset: const Offset(0, 2),
        ),
      ];

  /// ظل البطاقات الافتراضي متعدد الطبقات لإضفاء عمق واقعي
  static List<BoxShadow> get card => [
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: 0.04),
          blurRadius: 14,
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

  /// ظل العناصر العائمة والمرتفعة
  static List<BoxShadow> get elevated => [
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: 0.07),
          blurRadius: 22,
          spreadRadius: 0,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: 0.03),
          blurRadius: 6,
          spreadRadius: 0,
          offset: const Offset(0, 2),
        ),
      ];

  /// توهج أزرق ملكي أنيق للعناصر المميزة
  static List<BoxShadow> get primaryGlow => [
        BoxShadow(
          color: const Color(0xFF1B3FB6).withValues(alpha: 0.22),
          blurRadius: 16,
          spreadRadius: 0,
          offset: const Offset(0, 6),
        ),
      ];
}

/// موازين الطبوغرافيا العربية الاحترافية (Arabic Typographic Scale)
/// تضمن ارتفاع السطر (Line-Height) المناسب لمنع قص الحروف العربية العلوية والسفلية
abstract class AppTypography {
  static TextStyle display({Color color = const Color(0xFF0F172A)}) => GoogleFonts.cairo(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        height: 1.35,
        color: color,
      );

  static TextStyle h1({Color color = const Color(0xFF0F172A)}) => GoogleFonts.cairo(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        height: 1.4,
        color: color,
      );

  static TextStyle h2({Color color = const Color(0xFF0F172A)}) => GoogleFonts.cairo(
        fontSize: 17,
        fontWeight: FontWeight.bold,
        height: 1.4,
        color: color,
      );

  static TextStyle h3({Color color = const Color(0xFF0F172A)}) => GoogleFonts.cairo(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        height: 1.45,
        color: color,
      );

  static TextStyle bodyLarge({Color color = const Color(0xFF0F172A)}) => GoogleFonts.cairo(
        fontSize: 15,
        fontWeight: FontWeight.normal,
        height: 1.55,
        color: color,
      );

  static TextStyle body({Color color = const Color(0xFF334155)}) => GoogleFonts.cairo(
        fontSize: 13.5,
        fontWeight: FontWeight.normal,
        height: 1.55,
        color: color,
      );

  static TextStyle bodyStrong({Color color = const Color(0xFF0F172A)}) => GoogleFonts.cairo(
        fontSize: 13.5,
        fontWeight: FontWeight.bold,
        height: 1.55,
        color: color,
      );

  static TextStyle caption({Color color = const Color(0xFF64748B)}) => GoogleFonts.cairo(
        fontSize: 11.5,
        fontWeight: FontWeight.normal,
        height: 1.5,
        color: color,
      );

  static TextStyle captionStrong({Color color = const Color(0xFF475569)}) => GoogleFonts.cairo(
        fontSize: 11.5,
        fontWeight: FontWeight.bold,
        height: 1.5,
        color: color,
      );

  static TextStyle tiny({Color color = const Color(0xFF64748B)}) => GoogleFonts.cairo(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        height: 1.4,
        color: color,
      );
}

/// ثيم وهوية التطبيق الأكاديمية - نمط عصري أنيق ومضيء (Light Modern Academic)
class AppTheme {
  // الألوان الرئيسية الفاتحة والفاخرة
  static const Color primary = Color(0xFF1B3FB6); // أزرق ملكي أكاديمي فاخر (Royal Blue #1B3FB6)
  static const Color primaryDark = Color(0xFF122C82); // أزرق ملكي داكن للظلال والتدرجات
  static const Color primaryLight = Color(0xFF2C55D4); // أزرق ملكي زاهي
  static const Color primarySubtle = Color(0xFFEEF3FF); // خلفية ناصعة بمسحة زرقاء ملكية ناعمة
  static const Color accent = Color(0xFF1B3FB6); // اللون الملكي البارز (#1B3FB6)
  static const Color accentSubtle = Color(0xFFE8EEFF);

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
  static List<BoxShadow> get cardShadow => AppShadows.card;
  static List<BoxShadow> get primaryGlow => AppShadows.primaryGlow;
  static List<BoxShadow> get subtleShadow => AppShadows.subtle;
  static List<BoxShadow> get elevatedShadow => AppShadows.elevated;

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
        scrolledUnderElevation: 1.0,
        shadowColor: const Color(0xFF0F172A).withValues(alpha: 0.05),
        titleTextStyle: AppTypography.h2(color: textPrimary),
        iconTheme: const IconThemeData(color: textPrimary, size: 22),
      ),
      cardTheme: CardThemeData(
        color: lightCard,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: lightBorder, width: 1.0),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightSurface,
        hintStyle: AppTypography.body(color: textMuted),
        labelStyle: AppTypography.body(color: textSecondary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: danger, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(AppTouchTarget.minSize, AppTouchTarget.minSize),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          textStyle: GoogleFonts.cairo(
            fontSize: 14.5,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primary, width: 1.2),
          minimumSize: const Size(AppTouchTarget.minSize, AppTouchTarget.minSize),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
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
        elevation: 0,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  // دعم الاستدعاء الافتراضي
  static ThemeData get darkTheme => lightTheme;
}
