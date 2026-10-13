import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

/// ويدجت أنيميشن دراسي يمثل كتاباً أكاديمياً يفتح وصفحات تقلب بنعومة وهدوء
class StudyBookAnimation extends StatefulWidget {
  final double size;
  final Color? primaryColor;
  final Color? accentColor;
  final bool showGlow;

  const StudyBookAnimation({
    super.key,
    this.size = 54.0,
    this.primaryColor,
    this.accentColor,
    this.showGlow = true,
  });

  @override
  State<StudyBookAnimation> createState() => _StudyBookAnimationState();
}

class _StudyBookAnimationState extends State<StudyBookAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _flipAnimation;
  late Animation<double> _floatAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);

    _flipAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );

    _floatAnimation = Tween<double>(begin: -2.5, end: 2.5).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOutSine,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = widget.primaryColor ?? AppTheme.primary;
    final accent = widget.accentColor ?? AppTheme.primaryLight;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _floatAnimation.value),
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: widget.showGlow
                  ? [
                      BoxShadow(
                        color: primary.withValues(alpha: 0.18),
                        blurRadius: 14,
                        spreadRadius: 2,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
              border: Border.all(
                color: primary.withValues(alpha: 0.15),
                width: 1.5,
              ),
            ),
            padding: EdgeInsets.all(widget.size * 0.18),
            child: CustomPaint(
              painter: _BookPainter(
                progress: _flipAnimation.value,
                primaryColor: primary,
                accentColor: accent,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BookPainter extends CustomPainter {
  final double progress;
  final Color primaryColor;
  final Color accentColor;

  _BookPainter({
    required this.progress,
    required this.primaryColor,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final centerX = w / 2;
    final spineY = h * 0.85;

    // رسم غلاف الكتاب الأيسر والأيمن
    final coverPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;

    // الغلاف الأيسر
    final leftCover = Path()
      ..moveTo(centerX, spineY)
      ..lineTo(w * 0.08, spineY * 0.82)
      ..lineTo(w * 0.08, h * 0.18)
      ..lineTo(centerX, h * 0.25)
      ..close();
    canvas.drawPath(leftCover, coverPaint);

    // الغلاف الأيمن
    final rightCover = Path()
      ..moveTo(centerX, spineY)
      ..lineTo(w * 0.92, spineY * 0.82)
      ..lineTo(w * 0.92, h * 0.18)
      ..lineTo(centerX, h * 0.25)
      ..close();
    canvas.drawPath(rightCover, coverPaint);

    // صفحات الكتاب البيضاء الثابتة
    final pagePaint = Paint()
      ..color = const Color(0xFFF8FAFC)
      ..style = PaintingStyle.fill;

    final leftPage = Path()
      ..moveTo(centerX, spineY - 2)
      ..lineTo(w * 0.12, spineY * 0.80)
      ..lineTo(w * 0.12, h * 0.21)
      ..lineTo(centerX, h * 0.27)
      ..close();
    canvas.drawPath(leftPage, pagePaint);

    final rightPage = Path()
      ..moveTo(centerX, spineY - 2)
      ..lineTo(w * 0.88, spineY * 0.80)
      ..lineTo(w * 0.88, h * 0.21)
      ..lineTo(centerX, h * 0.27)
      ..close();
    canvas.drawPath(rightPage, pagePaint);

    // خطوط الأسطر المعرفية بالصفحة الثابتة
    final linePaint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    // أسطر اليسار
    canvas.drawLine(
      Offset(w * 0.18, h * 0.38),
      Offset(centerX - w * 0.08, h * 0.42),
      linePaint,
    );
    canvas.drawLine(
      Offset(w * 0.18, h * 0.52),
      Offset(centerX - w * 0.08, h * 0.56),
      linePaint,
    );

    // أسطر اليمين
    canvas.drawLine(
      Offset(centerX + w * 0.08, h * 0.42),
      Offset(w * 0.82, h * 0.38),
      linePaint,
    );
    canvas.drawLine(
      Offset(centerX + w * 0.08, h * 0.56),
      Offset(w * 0.82, h * 0.52),
      linePaint,
    );

    // الصفحة المتحركة (تقليب الصفحة بنعومة بين اليمين واليسار)
    final animatedFlipAngle = math.pi * progress; // من 0 إلى pi
    final flipFactor = math.cos(animatedFlipAngle); // من 1 إلى -1

    final dynamicPagePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final flippingPage = Path();
    flippingPage.moveTo(centerX, spineY - 2);
    final targetX = centerX + (w * 0.38 * flipFactor);
    final peakYOffset = -math.sin(animatedFlipAngle) * (h * 0.12);

    flippingPage.lineTo(targetX, spineY * 0.80 + peakYOffset);
    flippingPage.lineTo(targetX, h * 0.21 + peakYOffset);
    flippingPage.lineTo(centerX, h * 0.27);
    flippingPage.close();

    // ظل خفيف تحت الصفحة المتحركة
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.12 * math.sin(animatedFlipAngle))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawPath(flippingPage, shadowPaint);

    canvas.drawPath(flippingPage, dynamicPagePaint);

    // حد الصفحة المتحركة
    final flipBorderPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.6)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    canvas.drawPath(flippingPage, flipBorderPaint);

    // شريط المرجعية الأكاديمي (Bookmark Ribbon)
    final ribbonPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;
    final ribbon = Path()
      ..moveTo(centerX - 1.5, h * 0.25)
      ..lineTo(centerX + 1.5, h * 0.25)
      ..lineTo(centerX + 1.5, h * 0.72)
      ..lineTo(centerX, h * 0.65)
      ..lineTo(centerX - 1.5, h * 0.72)
      ..close();
    canvas.drawPath(ribbon, ribbonPaint);
  }

  @override
  bool shouldRepaint(covariant _BookPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.accentColor != accentColor;
  }
}
