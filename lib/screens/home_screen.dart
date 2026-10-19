import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants/app_constants.dart';
import '../core/constants/biometric_subjects.dart';
import '../core/theme/app_theme.dart';
import '../models/app_user_model.dart';
import '../models/announcement_model.dart';
import '../models/lecture_model.dart';
import '../services/supabase_service.dart';
import '../widgets/app_fullscreen_modal.dart';
import '../widgets/app_icon_badge.dart';
import '../widgets/app_network_image.dart';
import '../widgets/app_tactile_bounce.dart';
import 'courses_screen.dart';
import 'schedule_screen.dart';
import 'profile_screen.dart';
import 'subject_detail_screen.dart';
import '../services/admin_preview_service.dart';
import '../services/app_notification_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  bool _isLoading = true;

  AppUserModel? _user;
  List<AnnouncementModel> _announcements = [];
  List<LectureModel> _lectures = [];

  final ScrollController _homeScrollController = ScrollController();

  // متحكمات كاروسيل الإعلانات بالصور المتحركة
  late final PageController _bannerController;
  Timer? _bannerTimer;
  int _currentBannerPage = 0;

  // قائمة البوسترات والإعلانات الرسمية المعتمدة فقط للواجهة الرئيسية (تستبعد تبليغات المواد والجداول)
  List<AnnouncementModel> get _carouselBanners {
    return _announcements.where((a) {
      if (a.content.contains('[SCHEDULE_TIMETABLE]') ||
          a.content.contains('[COURSE_REGISTRY') ||
          a.subjectName == 'SCHEDULE' ||
          a.subjectName == 'COURSE') {
        return false;
      }
      if (a.subjectName != null &&
          a.subjectName!.isNotEmpty &&
          a.subjectName != 'BANNER' &&
          a.subjectName != 'GENERAL' &&
          a.subjectName != 'ALL' &&
          a.subjectName != 'عام') {
        return false;
      }
      return a.imageUrl != null && a.imageUrl!.trim().isNotEmpty;
    }).toList();
  }

  bool get _isPrivileged =>
      _user?.isAdmin == true ||
      _user?.studentId == 'ST-NUST-001630760-413' ||
      (_user?.name.contains('مجتبى') ?? false);

  String get _effectiveDept {
    final preview = AdminPreviewService();
    return _isPrivileged ? preview.department : (_user?.department ?? AppConstants.departments.first);
  }

  String get _effectiveStage {
    final preview = AdminPreviewService();
    return _isPrivileged ? preview.stage : (_user?.stage ?? AppConstants.stages.first);
  }

  String? get _effectiveSection {
    final preview = AdminPreviewService();
    return _isPrivileged ? preview.section : _user?.section;
  }


  @override
  void initState() {
    super.initState();
    _bannerController = PageController(viewportFraction: 0.92);
    AdminPreviewService().addListener(_onAdminPreviewChanged);
    _loadData().then((_) {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Future.delayed(const Duration(milliseconds: 1400), () {
            if (mounted) {
              AppNotificationService.instance.promptPermissionIfNeeded(context);
            }
          });
        });
      }
    });
  }

  void _onAdminPreviewChanged() {
    if (mounted) _loadData(forceRefresh: true);
  }

  @override
  void dispose() {
    AdminPreviewService().removeListener(_onAdminPreviewChanged);
    _bannerTimer?.cancel();
    _bannerController.dispose();
    _homeScrollController.dispose();
    super.dispose();
  }

  void _startBannerTimer(int count) {
    _bannerTimer?.cancel();
    if (count <= 1) return;

    _bannerTimer = Timer.periodic(const Duration(milliseconds: 4200), (timer) {
      if (!mounted || !_bannerController.hasClients) return;
      final nextPage = (_currentBannerPage + 1) % count;
      _bannerController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 750),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    // إذا كانت البيانات محملة مسبقاً، لا نظهر شاشة بيضاء لضمان استمرارية العرض السريع
    if (_announcements.isEmpty && _lectures.isEmpty) {
      setState(() => _isLoading = true);
    }

    final service = SupabaseService();
    _user = service.currentUser;

    if (_user != null) {
      try {
        final previewService = AdminPreviewService();
        previewService.initialize(_user);
        final effectiveDept = _effectiveDept;
        final effectiveStage = _effectiveStage;
        final effectiveSection = _effectiveSection;

        // جلب متوازي لكافة البيانات دفعة واحدة لتقليص زمن الانتظار
        final results = await Future.wait([
          service.fetchAnnouncements(
            department: effectiveDept,
            stage: effectiveStage,
            section: effectiveSection,
            forceRefresh: forceRefresh,
          ),
          service.fetchLectures(
            department: effectiveDept,
            stage: effectiveStage,
            section: effectiveSection,
            semester: _user?.semester ?? 1,
            forceRefresh: forceRefresh,
          ),
        ]);

        _announcements = results[0] as List<AnnouncementModel>;
        _lectures = results[1] as List<LectureModel>;

        // بدء تحريك كاروسيل الإعلانات الرسمية فقط
        _startBannerTimer(_carouselBanners.length);
      } catch (e) {
        debugPrint('[-] Error loading home data in parallel: $e');
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  /// جلب المواد الدراسية الرسمية المعتمدة حصراً من نظام البصمة الجامعي حسب الفصل الدراسي الفعلي للطالب
  List<String> get _subjectNames {
    if (_user == null) return [];
    return BiometricSubjects.getSubjectNames(
      department: _effectiveDept,
      stage: _effectiveStage,
      semester: _user?.semester ?? 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    // الأقسام الأربعة: الرئيسية، المقررات، الجدول، حسابي
    final List<Widget> pages = [
      _buildHomeContent(),
      const CoursesScreen(),
      const ScheduleScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      backgroundColor: AppTheme.lightBg,
      body: _isLoading && _announcements.isEmpty && _lectures.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          : IndexedStack(
              index: _currentIndex,
              children: pages,
            ),
      bottomNavigationBar: _buildModernBottomNav(),
    );
  }

  Widget _buildModernBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(
            color: AppTheme.lightBorder,
            width: 1.0,
          ),
        ),
        boxShadow: AppShadows.subtle,
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              _buildNavItem(0, Icons.home_rounded, Icons.home_outlined, 'الرئيسية'),
              _buildNavItem(1, Icons.menu_book_rounded, Icons.menu_book_outlined, 'المقررات'),
              _buildNavItem(2, Icons.calendar_month_rounded, Icons.calendar_month_outlined, 'الجدول'),
              _buildNavItem(3, Icons.person_rounded, Icons.person_outline_rounded, 'حسابي'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData activeIcon, IconData inactiveIcon, String label) {
    final isSelected = _currentIndex == index;
    return Expanded(
      child: AppTactileBounce(
        lowerBound: 0.94,
        onTap: () {
          if (_currentIndex != index) {
            HapticFeedback.selectionClick();
            setState(() => _currentIndex = index);
          }
        },
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.primarySubtle : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isSelected ? activeIcon : inactiveIcon,
                  color: isSelected ? AppTheme.primary : const Color(0xFF64748B),
                  size: 21,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  style: GoogleFonts.cairo(
                    fontSize: 10.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    color: isSelected ? AppTheme.primary : const Color(0xFF64748B),
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHomeContent() {
    if (_user == null) {
      return Center(
        child: Text('يرجى تسجيل الدخول', style: GoogleFonts.cairo(color: AppTheme.textPrimary)),
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        controller: _homeScrollController,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // شعار التطبيق فوك يمين
            _buildBrandHeader(),
            const SizedBox(height: 12),

            // شاشة الإعلانات بالصور المتحركة والكاروسيل التفاعلي
            _buildAnnouncementsMovingCarousel(),
            const SizedBox(height: 18),

            // بطاقات الوصول السريع (المقررات والجدول)
            _buildQuickActionCards(),
            const SizedBox(height: 20),

            // أحدث المحاضرات المضافة حديثاً
            _buildRecentLecturesSection(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// ترويسة الهوية الأكاديمية: شعار المنصة، كلمة محاضراتي ورمز المنظومة NUST-ETC-ATT
  Widget _buildBrandHeader() {
    final previewActive = AdminPreviewService().isCustomActive;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AppTactileBounce(
          lowerBound: 0.94,
          onTap: () {
            HapticFeedback.lightImpact();
            if (_homeScrollController.hasClients) {
              _homeScrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
              );
            }
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 38,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: AppTheme.lightBorder,
                    width: 1,
                  ),
                  boxShadow: AppShadows.subtle,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Image.asset(
                    'assets/images/app_logo.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.school_rounded,
                      color: AppTheme.primary,
                      size: 22,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'محاضراتي',
                style: GoogleFonts.cairo(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(
                    color: const Color(0xFFE2E8F0),
                    width: 1,
                  ),
                ),
                child: Text(
                  'NUST-ETC-ATT',
                  style: GoogleFonts.cairo(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF334155),
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
        ),

        if (previewActive)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: const Color(0xFFFCD34D)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.visibility_rounded, size: 12, color: Color(0xFFB45309)),
                const SizedBox(width: 4),
                Text(
                  'وضع المعاينة',
                  style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF92400E)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// بانر الإعلانات والبوسترات الرسمية بصور حقيقية (ممنوع أي صور عشوائية)
  Widget _buildAnnouncementsMovingCarousel() {
    final banners = _carouselBanners;

    // إذا لم تتوفر بوسترات رسمية مرفوعة بصور حقيقية، نظهر بطاقة هوية الكلية التقنية الفخمة
    if (banners.isEmpty) {
      return _buildDefaultUniversityBanner();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // حاوية الكاروسيل المنظمة والمرتبة مباشرة
        SizedBox(
          height: 180,
          child: PageView.builder(
            controller: _bannerController,
            itemCount: banners.length,
            onPageChanged: (idx) => setState(() => _currentBannerPage = idx),
            itemBuilder: (context, index) {
              final announcement = banners[index];
              final imageSrc = announcement.imageUrl!;

              final rawTitle = announcement.title;
              final rawContent = announcement.displayContent;

              final isBoilerplate = rawContent.contains('إعلان وبوستر رسمي') ||
                  rawContent.contains('إعلان بوستر رسمي') ||
                  rawContent.contains('بوستر رسمي');
              final content = isBoilerplate
                  ? ''
                  : rawContent
                      .replaceAll('إعلان وبوستر رسمي في الواجهة الرئيسية', '')
                      .replaceAll('إعلان وبوستر رسمي', '')
                      .replaceAll('إعلان بوستر رسمي', '')
                      .trim();

              String title = rawTitle
                  .replaceAll('إعلان وبوستر رسمي', '')
                  .replaceAll('إعلان بوستر رسمي', '')
                  .trim();
              if (RegExp(r'^\d+$').hasMatch(title)) {
                title = 'الكلية التقنية الهندسية';
              }

              final isPureBanner = content.isEmpty || isBoilerplate;

              return GestureDetector(
                onTap: () {
                  _showAnnouncementDetails(announcement, imageSrc);
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: AppTheme.cardShadow,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // الصورة الرسمية المرفوعة
                        AppNetworkImage(
                          imageUrl: imageSrc,
                          fit: BoxFit.cover,
                          errorWidget: Container(
                            color: AppTheme.primary,
                            child: const Center(
                              child: Icon(Icons.image_outlined, color: Colors.white54, size: 40),
                            ),
                          ),
                        ),

                        // تدرج لوني لطيف وأنيق لجعل المحتوى مقروءاً بنقاء
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.black.withValues(alpha: 0.8),
                                Colors.black.withValues(alpha: 0.15),
                                Colors.transparent,
                              ],
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                            ),
                          ),
                        ),

                        // تفاصيل البوستر / الإعلان فقط
                        Positioned(
                          bottom: 12,
                          right: 14,
                          left: 14,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                style: GoogleFonts.cairo(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  shadows: const [Shadow(blurRadius: 4, color: Colors.black87)],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (!isPureBanner && content.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  content,
                                  style: GoogleFonts.cairo(
                                    fontSize: 11,
                                    color: const Color(0xFFE2E8F0),
                                    shadows: const [Shadow(blurRadius: 4, color: Colors.black87)],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (banners.length > 1) ...[
          const SizedBox(height: 10),
          // مؤشرات النقاط عند وجود أكثر من بوستر
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(banners.length, (i) {
              final isActive = i == _currentBannerPage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: isActive ? 20 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isActive ? AppTheme.primary : const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }

  /// بطاقة الهوية الجامعية الرسمية الافتراضية الأنيقة (بدون أي صور عشوائية)
  Widget _buildDefaultUniversityBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0F172A),
            Color(0xFF1E3A8A),
            Color(0xFF1E40AF),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.card,
        border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.25), width: 1.0),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: const Center(
              child: Icon(Icons.school_rounded, color: Colors.white, size: 24),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'الكلية التقنية الهندسية',
                  style: GoogleFonts.cairo(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.3,
                  ),
                ),
                Text(
                  'الجامعة الوطنية للعلوم والتكنولوجيا (NUST)',
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    color: const Color(0xFF93C5FD),
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Text(
              _user?.semester == 2 ? 'فصل 2' : 'فصل 1',
              style: GoogleFonts.cairo(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAnnouncementDetails(AnnouncementModel announcement, String imageUrl) {
    AppFullscreenModal.show(
      context: context,
      title: announcement.title,
      subtitle: '${announcement.createdAt.year}/${announcement.createdAt.month.toString().padLeft(2, '0')}/${announcement.createdAt.day.toString().padLeft(2, '0')}',
      icon: Icons.campaign_rounded,
      imageUrl: imageUrl.isNotEmpty ? imageUrl : null,
      contentText: announcement.displayContent,
      accentColor: AppTheme.primary,
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text('إغلاق', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  /// بطاقات الوصول السريع للمقررات والجدول بتصميم نخبوي
  Widget _buildQuickActionCards() {
    return Row(
      children: [
        Expanded(
          child: AppTactileBounce(
            onTap: () => setState(() => _currentIndex = 1),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.lightBorder),
                boxShadow: AppShadows.card,
              ),
              child: Row(
                children: [
                  AppIconBadge.indigo(
                    icon: Icons.menu_book_rounded,
                    size: 42,
                    iconSize: 21,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'المقررات',
                          style: AppTypography.h3(color: AppTheme.textPrimary),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '${_subjectNames.length} مادة معتمدة',
                          style: AppTypography.caption(color: AppTheme.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 12,
                    color: Color(0xFF94A3B8),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: AppTactileBounce(
            onTap: () => setState(() => _currentIndex = 2),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.lightBorder),
                boxShadow: AppShadows.card,
              ),
              child: Row(
                children: [
                  AppIconBadge.amber(
                    icon: Icons.calendar_month_rounded,
                    size: 42,
                    iconSize: 21,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'الجدول',
                          style: AppTypography.h3(color: AppTheme.textPrimary),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          'المواعيد الأسبوعية',
                          style: AppTypography.caption(color: AppTheme.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 12,
                    color: Color(0xFF94A3B8),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// أحدث المحاضرات المضافة حديثاً
  Widget _buildRecentLecturesSection() {
    final recentLectures = _lectures.take(4).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.history_edu_rounded, color: AppTheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'أحدث المحاضرات',
                  style: AppTypography.h3(color: AppTheme.textPrimary),
                ),
              ],
            ),
            TextButton(
              onPressed: () => setState(() => _currentIndex = 1),
              child: Row(
                children: [
                  Text(
                    'عرض الكل',
                    style: AppTypography.captionStrong(color: AppTheme.primary),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_back_ios_new_rounded, size: 11, color: AppTheme.primary),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (recentLectures.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppTheme.lightBorder),
            ),
            child: Column(
              children: [
                const Icon(Icons.school_outlined, size: 38, color: Color(0xFF94A3B8)),
                const SizedBox(height: 8),
                Text(
                  'لا توجد محاضرات مضافة حديثاً',
                  style: AppTypography.body(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () => setState(() => _currentIndex = 1),
                  icon: const Icon(Icons.menu_book_rounded, size: 16),
                  label: Text(
                    'تصفح المقررات الدراسية',
                    style: AppTypography.captionStrong(color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                  ),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: recentLectures.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final lec = recentLectures[index];
              return AppTactileBounce(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SubjectDetailScreen(
                        subjectName: lec.subjectName,
                        department: _effectiveDept,
                        stage: _effectiveStage,
                        section: _effectiveSection,
                        semester: lec.semester != 0 ? lec.semester : (_user?.semester ?? 1),
                      ),
                    ),
                  ).then((_) => _loadData());
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.lightBorder),
                    boxShadow: AppShadows.subtle,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: lec.isPractical ? const Color(0xFFECFDF5) : AppTheme.primarySubtle,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Icon(
                            lec.isPractical ? Icons.science_outlined : Icons.description_outlined,
                            color: lec.isPractical ? const Color(0xFF059669) : AppTheme.primary,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              lec.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.bodyStrong(color: AppTheme.textPrimary),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Text(
                                  lec.subjectName,
                                  style: AppTypography.caption(color: AppTheme.textSecondary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: lec.isPractical ? const Color(0xFFECFDF5) : AppTheme.primarySubtle,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    lec.typeLabel,
                                    style: GoogleFonts.cairo(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                      color: lec.isPractical ? const Color(0xFF059669) : AppTheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 13,
                        color: Color(0xFF94A3B8),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

}
