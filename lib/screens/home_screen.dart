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
import 'dashboard_screen.dart';
import 'profile_screen.dart';
import 'subject_detail_screen.dart';
import 'announcements_screen.dart';

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

  // صور وبوسترات افتراضية عالية الجودة للإعلانات الجامعية في حال عدم إرفاق صورة
  final List<String> _defaultBannerImages = [
    'https://images.unsplash.com/photo-1523240795612-9a054b0db644?auto=format&fit=crop&w=800&q=80',
    'https://images.unsplash.com/photo-1541339907198-e08756dedf3f?auto=format&fit=crop&w=800&q=80',
    'https://images.unsplash.com/photo-1497633762265-9d179a990aa6?auto=format&fit=crop&w=800&q=80',
    'https://images.unsplash.com/photo-1517245386807-bb43f82c33c4?auto=format&fit=crop&w=800&q=80',
  ];

  @override
  void initState() {
    super.initState();
    _bannerController = PageController(viewportFraction: 0.92);
    _loadData();
  }

  @override
  void dispose() {
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
        // جلب متوازي لكافة البيانات دفعة واحدة لتقليص زمن الانتظار بنسبة 70%
        final userSection = _user!.isAdmin ? null : _user!.section;
        final results = await Future.wait([
          service.fetchAnnouncements(
            department: _user!.department,
            stage: _user!.stage,
            section: userSection,
            forceRefresh: forceRefresh,
          ),
          service.fetchStudentAttendance(_user!.studentId, forceRefresh: forceRefresh),
          service.fetchLectures(
            department: _user!.department,
            stage: _user!.stage,
            section: userSection,
            semester: 1,
            forceRefresh: forceRefresh,
          ),
          service.fetchCourses(
            department: _user!.department,
            stage: _user!.stage,
            semester: 1,
          ),
        ]);

        _announcements = results[0] as List<AnnouncementModel>;
        final records = results[1] as List<AttendanceRecordModel>;
        _attendanceSummary = AttendanceService.processAttendanceRecords(records);
        _lectures = results[2] as List<LectureModel>;
        _coursesList = results[3] as List<String>;

        // بدء تحريك كاروسيل الإعلانات
        final totalBanners = _announcements.isNotEmpty ? _announcements.length : _defaultBannerImages.length;
        _startBannerTimer(totalBanners);
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
      department: _user!.department,
      stage: _user!.stage,
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

    final hasAdminOrRepPrivileges =
        _user!.canManageLectures || _user!.canManageAnnouncements || _user!.isAdmin;

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

                  Row(
                    children: [
                      IconButton(
                        tooltip: 'لوحة الإعلانات والتبليغات',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const AnnouncementsScreen()),
                          ).then((_) => _loadData());
                        },
                        icon: AppIconBadge.indigo(
                          icon: Icons.campaign_rounded,
                          size: 40,
                          iconSize: 20,
                        ),
                      ),
                      if (hasAdminOrRepPrivileges) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'لوحة التحكم والإدارة',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const DashboardScreen()),
                            ).then((_) => _loadData());
                          },
                          icon: AppIconBadge.sky(
                            icon: Icons.dashboard_customize_rounded,
                            size: 40,
                            iconSize: 20,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

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
      ),
    );
  }

  /// بانر الإعلانات والبوسترات بصور متحركة وسلسة ومنسقة (بدون نصوص إضافية فوقها وبدون إعلانات وهمية)
  Widget _buildAnnouncementsMovingCarousel() {
    final hasRealAnnouncements = _announcements.isNotEmpty;
    final count = hasRealAnnouncements ? _announcements.length : 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // حاوية الكاروسيل المنظمة والمرتبة مباشرة
        SizedBox(
          height: 180,
          child: PageView.builder(
            controller: _bannerController,
            itemCount: count,
            onPageChanged: (idx) => setState(() => _currentBannerPage = idx),
            itemBuilder: (context, index) {
              final announcement = hasRealAnnouncements ? _announcements[index] : null;
              final imageSrc = (announcement?.imageUrl != null && announcement!.imageUrl!.isNotEmpty)
                  ? announcement.imageUrl!
                  : _defaultBannerImages[0];

              final title = announcement?.title ?? 'الكلية التقنية الهندسية';
              final content = (announcement?.displayContent.isNotEmpty == true)
                  ? announcement!.displayContent
                  : 'الجامعة الوطنية للعلوم والتكنولوجيا (NUST)';
              final isPureBanner = announcement != null &&
                  (announcement.displayContent.isEmpty ||
                      announcement.displayContent == 'إعلان وبوستر رسمي في الواجهة الرئيسية');

              return GestureDetector(
                onTap: () {
                  if (announcement != null) {
                    _showAnnouncementDetails(announcement, imageSrc);
                  }
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
                        // الصورة الرسمية
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
        if (count > 1) ...[
          const SizedBox(height: 10),
          // مؤشرات النقاط عند وجود أكثر من بوستر
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(count, (i) {
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
}
