import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme/app_theme.dart';

/// نافذة إرشادية وتفاعلية مخصصة لتثبيت التطبيق على أجهزة الآيفون (iOS)
/// بملء الشاشة Standalone بدون أشرطة متصفح وبشكل دائم
class IosInstallDialog extends StatefulWidget {
  const IosInstallDialog({super.key});

  /// دالة عرض النافذة
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (_) => const IosInstallDialog(),
    );
  }

  @override
  State<IosInstallDialog> createState() => _IosInstallDialogState();
}

class _IosInstallDialogState extends State<IosInstallDialog> {
  int _activeTab = 0; // 0: ملف التعريف (الأفضل), 1: إضافة للشاشة (سفاري)
  bool _isDownloading = false;

  Future<void> _downloadMobileConfig({bool useFallback = false}) async {
    setState(() => _isDownloading = true);
    try {
      final url = useFallback ? '/mohadarati.mobileconfig' : '/api/mobileconfig';
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تعذر فتح الرابط تلقائياً، يرجى الفتح عبر متصفح Safari',
              style: GoogleFonts.cairo(color: Colors.white, fontSize: 12),
            ),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          height: screenHeight * 0.88,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              // مقبض السحب العلوي
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 44,
                height: 4.5,
                decoration: BoxDecoration(
                  color: AppTheme.lightBorder,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),

              // شريط العنوان
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.apple, color: Colors.black, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'تثبيت التطبيق على الآيفون',
                            style: GoogleFonts.cairo(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          Text(
                            'تطبيق رسمي متكامل بدون أشرطة المتصفح',
                            style: GoogleFonts.cairo(
                              fontSize: 11.5,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: AppTheme.textSecondary),
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'إغلاق',
                    ),
                  ],
                ),
              ),
              const Divider(color: AppTheme.lightBorder, height: 1),

              // أزرار التبديل بين الطريقتين
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppTheme.lightSurface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildTabButton(
                          index: 0,
                          title: 'تثبيت سريع (بدون إعدادات)',
                          icon: Icons.bolt_rounded,
                        ),
                      ),
                      Expanded(
                        child: _buildTabButton(
                          index: 1,
                          title: 'ملف التعريف (.mobileconfig)',
                          icon: Icons.verified_rounded,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // المحتوى القابل للتمرير
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: _activeTab == 0 ? _buildSafariPwaSection() : _buildMobileConfigSection(),
                ),
              ),

              // شريط الميزات والضمانات السفلي
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.lightSurface,
                  border: const Border(top: BorderSide(color: AppTheme.lightBorder)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildFeaturePill(Icons.check_circle_outline, 'دائم مدى الحياة'),
                    _buildFeaturePill(Icons.fullscreen_rounded, 'شاشة كاملة 100%'),
                    _buildFeaturePill(Icons.bolt_rounded, 'تحديثات تلقائية'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabButton({
    required int index,
    required String title,
    required IconData icon,
  }) {
    final isSelected = _activeTab == index;
    return InkWell(
      onTap: () => setState(() => _activeTab = index),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? AppTheme.primary : AppTheme.textMuted,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// الخيار الأول: التثبيت عبر Apple MobileConfig Profile
  Widget _buildMobileConfigSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // بانر ترحيبي بمميزات الطريقة
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.primarySubtle,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.stars_rounded, color: AppTheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'يقوم هذا الملف بتثبيت "محاضراتي" كأيقونة نظام مستقلة داخل الآيفون تعمل بدون أي شريط لمتصفح سفاري إطلاقاً.',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    height: 1.4,
                    color: AppTheme.primaryDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // زر التحميل الرئيسي
        ElevatedButton(
          onPressed: _isDownloading ? null : () => _downloadMobileConfig(),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 2,
          ),
          child: _isDownloading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.download_rounded, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'تحميل ملف التثبيت المباشر للآيفون',
                      style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 8),

        // زر احتياطي للرابط الثابت
        Center(
          child: TextButton.icon(
            onPressed: _isDownloading ? null : () => _downloadMobileConfig(useFallback: true),
            icon: const Icon(Icons.link_rounded, size: 16, color: AppTheme.textSecondary),
            label: Text(
              'إذا لم يبدأ التحميل، اضغط هنا لتنزيل الملف البديل',
              style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // خطوات التثبيت الثلاثية
        Text(
          'خطوات التفعيل في دقيقة واحدة:',
          style: GoogleFonts.cairo(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 10),

        _buildStepCard(
          stepNumber: '1',
          title: 'السماح بتنزيل ملف التعريف',
          description: 'بعد الضغط على زر التحميل أعلاه، ستظهر رسالة من Safari يطلب الإذن؛ اضغط على "سماح" (Allow).',
          icon: Icons.touch_app_rounded,
        ),
        const SizedBox(height: 10),

        _buildStepCard(
          stepNumber: '2',
          title: 'فتح إعدادات الآيفون (Settings)',
          description: 'افتح إعدادات جهازك، ستجد في الأعلى خياراً جديداً باسم: "تم تنزيل ملف التعريف" (Profile Downloaded).',
          icon: Icons.settings_outlined,
        ),
        const SizedBox(height: 10),

        _buildStepCard(
          stepNumber: '3',
          title: 'الضغط على تثبيت (Install)',
          description: 'اضغط على تثبيت في الزاوية العلوية وأدخل رمز قفل الشاشة، وسيظهر تطبيق "محاضراتي" فوراً على شاشتك الرئيسية!',
          icon: Icons.check_circle_rounded,
          isFinal: true,
        ),
      ],
    );
  }

  /// الخيار الرئيسي: إضافة إلى الصفحة الرئيسية عبر سفاري (تثبيت فوري بدون إعدادات)
  Widget _buildSafariPwaSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.primarySubtle,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.bolt_rounded, color: AppTheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'أبسط طريقة رسمية لتثبيت التطبيق على الآيفون بنقرتين وبدون الدخول إلى الإعدادات أو طلب رمز القفل.',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    height: 1.4,
                    color: AppTheme.primaryDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        _buildStepCard(
          stepNumber: '1',
          title: 'الضغط على زر المشاركة (Share ⎋)',
          description: 'اضغط على زر المشاركة (مربع بسهم للأعلى ⎋) في الشريط السفلي لمتصفح سفاري.',
          icon: Icons.ios_share_rounded,
        ),
        const SizedBox(height: 10),

        _buildStepCard(
          stepNumber: '2',
          title: 'اختيار "إضافة إلى الصفحة الرئيسية" ➕',
          description: 'مرر القائمة لأسفل واختر "إضافة إلى الصفحة الرئيسية" (Add to Home Screen) ثم اضغط "إضافة" (Add).',
          icon: Icons.add_box_rounded,
          isFinal: true,
        ),
        const SizedBox(height: 16),

        // مؤشر توجيهي للشريط السفلي
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.lightBorder),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.arrow_downward_rounded, color: AppTheme.primary, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'زر المشاركة ⎋ موجود في شريط سفاري أسفل الشاشة',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStepCard({
    required String stepNumber,
    required String title,
    required String description,
    required IconData icon,
    bool isFinal = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isFinal ? AppTheme.primary.withValues(alpha: 0.3) : AppTheme.lightBorder),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isFinal ? AppTheme.primary : AppTheme.primarySubtle,
              shape: BoxShape.circle,
            ),
            child: Text(
              stepNumber,
              style: GoogleFonts.cairo(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isFinal ? Colors.white : AppTheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 16, color: isFinal ? AppTheme.primary : AppTheme.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      title,
                      style: GoogleFonts.cairo(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: GoogleFonts.cairo(
                    fontSize: 11.5,
                    height: 1.45,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturePill(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.primary),
        const SizedBox(width: 5),
        Text(
          text,
          style: GoogleFonts.cairo(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}
