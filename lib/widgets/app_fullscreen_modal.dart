import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/app_theme.dart';
import 'app_icon_badge.dart';

/// نافذة منبثقة احترافية بملء الشاشة مع خلفية ضبابية وتصميم بطاقة عصري (Full-Screen Modal Sheet)
class AppFullscreenModal extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final String? imageUrl;
  final Widget? contentWidget;
  final String? contentText;
  final List<Widget>? actions;
  final Widget? customHeader;
  final Color? accentColor;

  const AppFullscreenModal({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.imageUrl,
    this.contentWidget,
    this.contentText,
    this.actions,
    this.customHeader,
    this.accentColor,
  });

  /// دالة إظهار النافذة المنبثقة كاملة الشاشة
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    String? subtitle,
    IconData? icon,
    String? imageUrl,
    Widget? contentWidget,
    String? contentText,
    List<Widget>? actions,
    Widget? customHeader,
    Color? accentColor,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (ctx) => AppFullscreenModal(
        title: title,
        subtitle: subtitle,
        icon: icon,
        imageUrl: imageUrl,
        contentWidget: contentWidget,
        contentText: contentText,
        actions: actions,
        customHeader: customHeader,
        accentColor: accentColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveAccent = accentColor ?? AppTheme.primary;
    final screenHeight = MediaQuery.of(context).size.height;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        height: screenHeight * 0.92,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 30,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: Column(
          children: [
            // مقبض السحب العلوي (Drag Handle)
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // شريط العنوان العلوي الأنيق وزر الإغلاق
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  if (icon != null) ...[
                    AppIconBadge.subtle(
                      icon: icon!,
                      color: effectiveAccent,
                      size: 44,
                      iconSize: 22,
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.cairo(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty)
                          Text(
                            subtitle!,
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),

                  // زر الإغلاق الدائري العصري
                  Material(
                    color: AppTheme.lightSurface,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.pop(context),
                      child: const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Icon(Icons.close_rounded, size: 20, color: AppTheme.textSecondary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: AppTheme.lightBorder, height: 1),

            // المحتوى الداخلي القابل للتمرير بملء الشاشة
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (customHeader != null) ...[
                      customHeader!,
                      const SizedBox(height: 16),
                    ],

                    // عرض الصورة التفاعلي بدقة عالية مع التكبير
                    if (imageUrl != null && imageUrl!.isNotEmpty) ...[
                      Container(
                        constraints: BoxConstraints(
                          maxHeight: screenHeight * 0.45,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: AppTheme.cardShadow,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InteractiveViewer(
                          panEnabled: true,
                          scaleEnabled: true,
                          minScale: 0.8,
                          maxScale: 4.5,
                          child: Center(
                            child: Image.network(
                              imageUrl!,
                              fit: BoxFit.contain,
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return Center(
                                  child: CircularProgressIndicator(
                                    value: progress.expectedTotalBytes != null
                                        ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                                        : null,
                                    color: AppTheme.accent,
                                  ),
                                );
                              },
                              errorBuilder: (context, error, stack) => const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(32),
                                  child: Icon(Icons.broken_image_rounded, size: 54, color: Colors.white54),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // نص المحتوى بتنسيق احترافي ومقروء
                    if (contentText != null && contentText!.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.lightSurface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.lightBorder),
                        ),
                        child: SelectableText(
                          contentText!,
                          style: GoogleFonts.cairo(
                            fontSize: 14,
                            color: AppTheme.textPrimary,
                            height: 1.7,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    if (contentWidget != null) contentWidget!,
                  ],
                ),
              ),
            ),

            // شريط الأزرار التفاعلية أسفل الشاشة
            if (actions != null && actions!.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: AppTheme.lightBorder)),
                ),
                child: Row(
                  children: actions!.map((act) => Expanded(child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: act,
                  ))).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
