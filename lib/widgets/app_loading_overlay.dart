import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/app_theme.dart';
import 'study_book_animation.dart';

/// واجهة تحميل بملء الشاشة ذات ألوان متباينة وتصميم أكاديمي حديث وبسيط (High-Contrast Academic Loading Overlay)
class AppLoadingOverlay extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool showAnimation;

  const AppLoadingOverlay({
    super.key,
    this.title = 'جاري التحقق من القيد ومزامنة الحساب...',
    this.subtitle = 'يرجى الانتظار لحظات، يتم إعداد بوابتك الأكاديمية بنجاح',
    this.showAnimation = true,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          color: const Color(0xFF0F172A).withValues(alpha: 0.85), // كحلي ملكي عالي التباين
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 32),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B), // كحلي أردوازي متباين
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppTheme.primaryLight.withValues(alpha: 0.6),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.35),
                    blurRadius: 36,
                    spreadRadius: 2,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // أنيميشن دراسي متوهج
                  if (showAnimation) ...[
                    const StudyBookAnimation(
                      size: 64,
                      showGlow: true,
                    ),
                    const SizedBox(height: 22),
                  ],

                  // العنوان الرئيسي بلون أبيض ناصع عالي التباين
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.4,
                    ),
                  ),

                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      subtitle!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        color: const Color(0xFF94A3B8), // رمادي فاتح متباين
                        height: 1.5,
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // مؤشر شريطي متدرج ناعم وعالي التباين
                  Container(
                    width: double.infinity,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFF334155),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: const LinearProgressIndicator(
                        backgroundColor: Colors.transparent,
                        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accent),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
