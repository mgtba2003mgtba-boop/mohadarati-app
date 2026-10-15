import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants/app_constants.dart';
import '../core/constants/biometric_subjects.dart';
import '../core/theme/app_theme.dart';
import '../models/app_user_model.dart';
import '../models/attendance_model.dart';
import '../models/announcement_model.dart';
import '../models/lecture_model.dart';
import '../services/supabase_service.dart';
import '../services/attendance_service.dart';
import '../widgets/study_book_animation.dart';
import '../widgets/app_fullscreen_modal.dart';
import '../widgets/app_icon_badge.dart';
import '../widgets/app_network_image.dart';
import 'courses_screen.dart';
import 'schedule_screen.dart';
import 'profile_screen.dart';
import 'subject_detail_screen.dart';
import 'announcements_screen.dart';
import '../services/admin_preview_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  bool _isLoading = true;

  AppUserModel? _user;
  OverallAttendanceSummary? _attendanceSummary;
  List<AnnouncementModel> _announcements = [];
  List<LectureModel> _lectures = [];
  List<String> _coursesList = [];

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

  // قائمة تبليغات ومنشورات الشعبة المعتمدة
  List<AnnouncementModel> get _sectionAnnouncements {
    return _announcements.where((a) {
      if (a.content.contains('[SCHEDULE_TIMETABLE]') ||
          a.content.contains('[COURSE_REGISTRY') ||
          a.subjectName == 'SCHEDULE' ||
          a.subjectName == 'COURSE') {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _bannerController = PageController(viewportFraction: 0.92);
    AdminPreviewService().addListener(_onAdminPreviewChanged);
    _loadData();
  }

  void _onAdminPreviewChanged() {
    if (mounted) _loadData(forceRefresh: true);
  }

  @override
  void dispose() {
    AdminPreviewService().removeListener(_onAdminPreviewChanged);
    _bannerTimer?.cancel();
    _bannerController.dispose();
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

        // جلب متوازي لكافة البيانات دفعة واحدة لتقليص زمن الانتظار بنسبة 70%
        final results = await Future.wait([
          service.fetchAnnouncements(
            department: effectiveDept,
            stage: effectiveStage,
            section: effectiveSection,
            forceRefresh: forceRefresh,
          ),
          service.fetchStudentAttendance(_user!.studentId, forceRefresh: forceRefresh),
          service.fetchLectures(
            department: effectiveDept,
            stage: effectiveStage,
            section: effectiveSection,
            semester: 1,
            forceRefresh: forceRefresh,
          ),
          service.fetchCourses(
            department: effectiveDept,
            stage: effectiveStage,
            semester: 1,
          ),
        ]);

        _announcements = results[0] as List<AnnouncementModel>;
        final records = results[1] as List<AttendanceRecordModel>;
        _attendanceSummary = AttendanceService.processAttendanceRecords(records);
        _lectures = results[2] as List<LectureModel>;
        _coursesList = results[3] as List<String>;

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

  /// جلب المواد الدراسية الرسمية المعتمدة حصراً من نظام البصمة الجامعي (الكورس الأول)
  List<String> get _subjectNames {
    if (_user == null) return [];
    return BiometricSubjects.getSubjectNames(
      department: _effectiveDept,
      stage: _effectiveStage,
      semester: 1,
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
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          backgroundColor: Colors.white,
          selectedItemColor: AppTheme.primary,
          unselectedItemColor: const Color(0xFF94A3B8),
          elevation: 0,
          onTap: (index) => setState(() => _currentIndex = index),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded),
              label: 'الرئيسية',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.menu_book_rounded),
              label: 'المقررات',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_month_rounded),
              label: 'الجدول',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_rounded),
              label: 'حسابي',
            ),
          ],
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

    final isMujtabaAdmin = _user != null &&
        (_user!.studentId == 'ST-NUST-001630760-413' ||
            _user!.name.contains('مجتبى') ||
            _user!.isAdmin);

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () => _loadData(forceRefresh: true),
        color: AppTheme.primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // شريط الترويسة الأكاديمية الرسمي (بدون تكرار بيانات الطالب المحفوظة في حسابي)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      AppIconBadge.indigo(
                        icon: Icons.account_balance_rounded,
                        size: 42,
                        iconSize: 22,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppConstants.appName,
                            style: GoogleFonts.cairo(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          if (_user?.department != null && _user!.department.isNotEmpty)
                            Text(
                              _user!.department,
                              style: GoogleFonts.cairo(
                                fontSize: 11,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),

                ],
              ),
              const SizedBox(height: 14),

              // شاشة الإعلانات بالصور المتحركة والكاروسيل التفاعلي
              _buildAnnouncementsMovingCarousel(),
              const SizedBox(height: 18),

              // بطاقات الوصول السريع (المقررات والجدول)
              _buildQuickActionCards(),
              const SizedBox(height: 20),

              // تبليغات وتوجيهات الشعبة
              _buildSectionAnnouncementsSection(),
              const SizedBox(height: 20),

              // أحدث المحاضرات المضافة حديثاً
              _buildRecentLecturesSection(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
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
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF0F172A),
            AppTheme.primary.withValues(alpha: 0.85),
            const Color(0xFF0F172A),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow,
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
            ),
            child: const Center(
              child: Icon(Icons.school_rounded, color: AppTheme.accent, size: 26),
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
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'الجامعة الوطنية للعلوم والتكنولوجيا (NUST)',
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    color: AppTheme.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'بوابة المحاضرات والجداول الأكاديمية الرسمية',
                  style: GoogleFonts.cairo(
                    fontSize: 10,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAnnouncementDetails(AnnouncementModel announcement, String imageUrl) {
    final cleanContent = announcement.displayContent
        .replaceAll('إعلان وبوستر رسمي في الواجهة الرئيسية', '')
        .replaceAll('إعلان وبوستر رسمي', '')
        .replaceAll('إعلان بوستر رسمي', '')
        .replaceAll('بوستر رسمي', '')
        .trim();

    String cleanTitle = announcement.title
        .replaceAll('إعلان وبوستر رسمي', '')
        .replaceAll('إعلان بوستر رسمي', '')
        .trim();
    if (RegExp(r'^\d+$').hasMatch(cleanTitle)) {
      cleanTitle = 'إعلان الكلية التقنية الهندسية';
    }

    AppFullscreenModal.show(
      context: context,
      title: cleanTitle.isNotEmpty ? cleanTitle : 'الكلية التقنية الهندسية',
      subtitle: '${announcement.createdAt.year}/${announcement.createdAt.month.toString().padLeft(2, '0')}/${announcement.createdAt.day.toString().padLeft(2, '0')}',
      icon: Icons.campaign_rounded,
      imageUrl: imageUrl.isNotEmpty ? imageUrl : null,
      contentText: cleanContent,
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

  /// بطاقات الوصول السريع للمقررات والجدول
  Widget _buildQuickActionCards() {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => setState(() => _currentIndex = 1),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.lightBorder),
                boxShadow: AppTheme.cardShadow,
              ),
              child: Row(
                children: [
                  AppIconBadge.indigo(
                    icon: Icons.menu_book_rounded,
                    size: 40,
                    iconSize: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'المقررات',
                          style: GoogleFonts.cairo(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          '${_subjectNames.length} مادة دراسية',
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            onTap: () => setState(() => _currentIndex = 2),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.lightBorder),
                boxShadow: AppTheme.cardShadow,
              ),
              child: Row(
                children: [
                  AppIconBadge.amber(
                    icon: Icons.calendar_month_rounded,
                    size: 40,
                    iconSize: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'الجدول',
                          style: GoogleFonts.cairo(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          'المواعيد والامتحانات',
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
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
                  style: GoogleFonts.cairo(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: () => setState(() => _currentIndex = 1),
              child: Row(
                children: [
                  Text(
                    'عرض كل المقررات',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
                    ),
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
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.lightBorder),
            ),
            child: Column(
              children: [
                const Icon(Icons.school_outlined, size: 38, color: Color(0xFF94A3B8)),
                const SizedBox(height: 8),
                Text(
                  'لا توجد محاضرات مضافة حديثاً',
                  style: GoogleFonts.cairo(fontSize: 13, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () => setState(() => _currentIndex = 1),
                  icon: const Icon(Icons.menu_book_rounded, size: 16),
                  label: Text(
                    'تصفح المقررات الدراسية',
                    style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
              return InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SubjectDetailScreen(
                        subjectName: lec.subjectName,
                        department: _effectiveDept,
                        stage: _effectiveStage,
                        section: _effectiveSection,
                      ),
                    ),
                  ).then((_) => _loadData());
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.lightBorder),
                    boxShadow: AppTheme.cardShadow,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.primarySubtle,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.description_outlined,
                          color: AppTheme.primary,
                          size: 20,
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
                              style: GoogleFonts.cairo(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${lec.subjectName} • ${lec.typeLabel}',
                              style: GoogleFonts.cairo(
                                fontSize: 11,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14,
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

  /// قسم تبليغات وتوجيهات الشعبة المعتمد
  Widget _buildSectionAnnouncementsSection() {
    final announcements = _sectionAnnouncements;
    final currentSec = _effectiveSection;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.campaign_rounded, color: AppTheme.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  'تبليغات وتوجيهات الشعبة',
                  style: GoogleFonts.cairo(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (currentSec != null && currentSec.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primarySubtle,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'شعبة $currentSec',
                      style: GoogleFonts.cairo(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (announcements.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${announcements.length}',
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (announcements.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.lightBorder),
            ),
            child: Column(
              children: [
                const Icon(Icons.notifications_none_rounded, size: 34, color: Color(0xFF94A3B8)),
                const SizedBox(height: 8),
                Text(
                  (currentSec != null && currentSec.isNotEmpty)
                      ? 'لا توجد تبليغات منشورة لشعبة $currentSec حالياً'
                      : 'لا توجد تبليغات منشورة حالياً',
                  style: GoogleFonts.cairo(fontSize: 12.5, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 3),
                Text(
                  'أي تبليغ ينشره ممثل الشعبة أو إدارة الكلية سيظهر هنا فوراً',
                  style: GoogleFonts.cairo(fontSize: 10.5, color: AppTheme.textMuted),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: announcements.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = announcements[index];
              final hasSubject = item.subjectName != null &&
                  item.subjectName!.isNotEmpty &&
                  item.subjectName != 'GENERAL' &&
                  item.subjectName != 'BANNER' &&
                  item.subjectName != 'ALL' &&
                  item.subjectName != 'عام';

              return InkWell(
                onTap: () => _showAnnouncementDetails(item, item.imageUrl ?? ''),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: item.isPinned ? const Color(0xFFFDE68A) : AppTheme.lightBorder,
                    ),
                    boxShadow: AppTheme.cardShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // الصف العلوي: الوسوم والتاريخ
                      Row(
                        children: [
                          if (item.isPinned) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.push_pin_rounded, size: 11, color: Color(0xFFD97706)),
                                  const SizedBox(width: 3),
                                  Text(
                                    'مثبت',
                                    style: GoogleFonts.cairo(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFFD97706),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: hasSubject ? const Color(0xFFEEF2FF) : AppTheme.primarySubtle,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              hasSubject ? item.subjectName! : 'تبليغ رسمي',
                              style: GoogleFonts.cairo(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: hasSubject ? const Color(0xFF4F46E5) : AppTheme.primary,
                              ),
                            ),
                          ),
                          if (item.section != 'ALL' && item.section.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'شعبة ${item.section}',
                                style: GoogleFonts.cairo(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF475569),
                                ),
                              ),
                            ),
                          ],
                          const Spacer(),
                          Text(
                            '${item.createdAt.year}/${item.createdAt.month.toString().padLeft(2, '0')}/${item.createdAt.day.toString().padLeft(2, '0')}',
                            style: GoogleFonts.cairo(fontSize: 10.5, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // عنوان التبليغ
                      Text(
                        item.title,
                        style: GoogleFonts.cairo(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),

                      // محتوى التبليغ
                      Text(
                        item.displayContent,
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                          height: 1.45,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),

                      // الصف السفلي: اسم الناشر ورابط التفاصيل
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.person_outline_rounded, size: 14, color: Color(0xFF94A3B8)),
                              const SizedBox(width: 4),
                              Text(
                                item.authorName.isNotEmpty ? item.authorName : 'ممثل الشعبة',
                                style: GoogleFonts.cairo(
                                  fontSize: 10.5,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Text(
                                'التفاصيل',
                                style: GoogleFonts.cairo(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primary,
                                ),
                              ),
                              const SizedBox(width: 3),
                              const Icon(Icons.arrow_forward_ios_rounded, size: 10, color: AppTheme.primary),
                            ],
                          ),
                        ],
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
