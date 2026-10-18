import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants/app_constants.dart';
import '../core/constants/biometric_subjects.dart';
import '../core/theme/app_theme.dart';
import '../models/app_user_model.dart';
import '../models/attendance_model.dart';
import '../models/lecture_model.dart';
import '../models/course_override_model.dart';
import '../services/supabase_service.dart';
import '../services/attendance_service.dart';
import '../services/admin_preview_service.dart';
import '../services/course_customization_service.dart';
import '../widgets/study_book_animation.dart';
import '../widgets/app_icon_badge.dart';
import '../widgets/app_tactile_bounce.dart';
import '../widgets/course_customization_sheet.dart';
import 'subject_detail_screen.dart';
import 'dashboard_screen.dart';

class CourseItemDisplay {
  final String originalName;
  final String displayName;
  final String? code;
  final bool isHidden;
  final CourseOverrideModel? override;

  CourseItemDisplay({
    required this.originalName,
    required this.displayName,
    this.code,
    required this.isHidden,
    this.override,
  });
}

class CoursesScreen extends StatefulWidget {
  const CoursesScreen({super.key});

  @override
  State<CoursesScreen> createState() => _CoursesScreenState();
}

class _CoursesScreenState extends State<CoursesScreen> {
  bool _isLoading = true;
  AppUserModel? _user;
  List<LectureModel> _lectures = [];
  List<String> _coursesList = [];
  OverallAttendanceSummary? _attendanceSummary;
  String _searchQuery = '';
  int _selectedSemester = 1;

  bool get _isPrivileged =>
      _user?.isAdmin == true ||
      _user?.studentId == 'ST-NUST-001630760-413' ||
      (_user?.name.contains('مجتبى') ?? false);

  bool get _canManageCourses =>
      _isPrivileged ||
      _user?.isRepresentative == true ||
      _user?.canManageLectures == true;

  String get _effectiveDept {
    if (_isPrivileged) {
      return AdminPreviewService().department;
    }
    return _user?.department ?? AppConstants.departments.first;
  }

  String get _effectiveStage {
    if (_isPrivileged) {
      return AdminPreviewService().stage;
    }
    return _user?.stage ?? AppConstants.stages.first;
  }

  String? get _effectiveSection {
    if (_isPrivileged) {
      return AdminPreviewService().section;
    }
    return _user?.section;
  }

  @override
  void initState() {
    super.initState();
    _user = SupabaseService().currentUser;
    _selectedSemester = _user?.semester ?? 1;
    AdminPreviewService().addListener(_onAdminPreviewChanged);
    CourseCustomizationService().addListener(_onCustomizationChanged);
    _loadCourses();
  }

  void _onAdminPreviewChanged() {
    if (mounted) _loadCourses(forceRefresh: true);
  }

  void _onCustomizationChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AdminPreviewService().removeListener(_onAdminPreviewChanged);
    CourseCustomizationService().removeListener(_onCustomizationChanged);
    super.dispose();
  }

  Future<void> _loadCourses({bool forceRefresh = false}) async {
    if (_coursesList.isEmpty && _lectures.isEmpty) {
      setState(() => _isLoading = true);
    }
    final service = SupabaseService();
    _user = service.currentUser;

    // للطلاب العاديين: يُعرض فصل دراسي واحد فقط مطابق للفصل المحول له من الداشبورد
    if (!_canManageCourses && _user != null) {
      _selectedSemester = _user!.semester;
    }

    if (_user != null) {
      try {
        final results = await Future.wait([
          service.fetchStudentAttendance(_user!.studentId, forceRefresh: forceRefresh),
          service.fetchLectures(
            department: _effectiveDept,
            stage: _effectiveStage,
            section: _effectiveSection,
            semester: _selectedSemester,
            forceRefresh: forceRefresh,
          ),
          service.fetchCourses(
            department: _effectiveDept,
            stage: _effectiveStage,
            semester: _selectedSemester,
          ),
          CourseCustomizationService().getOverrides(
            department: _effectiveDept,
            stage: _effectiveStage,
            semester: _selectedSemester,
            forceRefresh: forceRefresh,
          ),
        ]);

        final records = results[0] as List<AttendanceRecordModel>;
        _attendanceSummary = AttendanceService.processAttendanceRecords(records);
        _lectures = results[1] as List<LectureModel>;
        _coursesList = results[2] as List<String>;
      } catch (e) {
        debugPrint('[-] Error loading courses in parallel: $e');
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  /// جلب المقررات مع دمج التخصيصات وإخفاء المواد المحجوبة عن الطلبة العاديين
  List<CourseItemDisplay> get _displayCourses {
    if (_user == null) return [];

    final biometricList = BiometricSubjects.getSubjectNames(
      department: _effectiveDept,
      stage: _effectiveStage,
      semester: _selectedSemester,
    );

    final customService = CourseCustomizationService();
    final List<CourseItemDisplay> items = [];

    for (final origName in biometricList) {
      final override = customService.getOverrideFor(
        origName,
        department: _effectiveDept,
        stage: _effectiveStage,
        semester: _selectedSemester,
      );

      final isHidden = override?.isHidden ?? false;

      // المقررات المخفية تُحجب تماماً عن الطلبة العاديين وتظهر فقط للمشرف والممثلين
      if (isHidden && !_canManageCourses) {
        continue;
      }

      final subModel = BiometricSubjects.findSubject(
        origName,
        department: _effectiveDept,
        stage: _effectiveStage,
        semester: _selectedSemester,
      );

      final displayName = override?.displayName ?? origName;
      final code = override?.customCode ?? subModel?.code;

      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase().trim();
        final matches = displayName.toLowerCase().contains(query) ||
            origName.toLowerCase().contains(query) ||
            (code != null && code.toLowerCase().contains(query));
        if (!matches) continue;
      }

      items.add(CourseItemDisplay(
        originalName: origName,
        displayName: displayName,
        code: code,
        isHidden: isHidden,
        override: override,
      ));
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final canPublish = _user?.canManageLectures == true || _user?.isAdmin == true;
    final courses = _displayCourses;

    return Scaffold(
      backgroundColor: AppTheme.lightBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: Row(
          children: [
            const StudyBookAnimation(size: 34, showGlow: false),
            const SizedBox(width: 10),
            Text(
              'المقررات',
              style: GoogleFonts.cairo(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.primarySubtle,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${courses.length}',
                style: GoogleFonts.cairo(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
              ),
            ),
            if (!_canManageCourses) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _selectedSemester == 2 ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _selectedSemester == 2 ? const Color(0xFFBFDBFE) : const Color(0xFFE2E8F0),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  _selectedSemester == 2 ? 'الفصل الثاني' : 'الفصل الأول',
                  style: GoogleFonts.cairo(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: _selectedSemester == 2 ? const Color(0xFF2563EB) : const Color(0xFF475569),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary),
            tooltip: 'تحديث',
            onPressed: () => _loadCourses(forceRefresh: true),
          ),
        ],
      ),
      floatingActionButton: canPublish
          ? AppTactileBounce(
              lowerBound: 0.94,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  boxShadow: AppShadows.primaryGlow,
                ),
                child: FloatingActionButton.extended(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: Text(
                    'رفع محاضرة',
                    style: AppTypography.captionStrong(color: Colors.white),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DashboardScreen(initialTabIndex: 0),
                      ),
                    ).then((_) => _loadCourses(forceRefresh: true));
                  },
                ),
              ),
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : Column(
              children: [
                // مبدل الفصل الدراسي الأول / الفصل الدراسي الثاني (حصري للإدارة والممثلين - مخفي تماماً عن الطلاب)
                if (_canManageCourses)
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppTheme.lightSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.lightBorder),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: AppTactileBounce(
                            lowerBound: 0.94,
                            onTap: () {
                              if (_selectedSemester != 1) {
                                HapticFeedback.selectionClick();
                                setState(() => _selectedSemester = 1);
                                _loadCourses(forceRefresh: true);
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: _selectedSemester == 1 ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(9),
                                boxShadow: _selectedSemester == 1
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.06),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Center(
                                child: Text(
                                  'الفصل الدراسي الأول',
                                  style: GoogleFonts.cairo(
                                    fontSize: 12,
                                    fontWeight: _selectedSemester == 1 ? FontWeight.bold : FontWeight.w600,
                                    color: _selectedSemester == 1 ? AppTheme.primary : AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: AppTactileBounce(
                            lowerBound: 0.94,
                            onTap: () {
                              if (_selectedSemester != 2) {
                                HapticFeedback.selectionClick();
                                setState(() => _selectedSemester = 2);
                                _loadCourses(forceRefresh: true);
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: _selectedSemester == 2 ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(9),
                                boxShadow: _selectedSemester == 2
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.06),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Center(
                                child: Text(
                                  'الفصل الدراسي الثاني',
                                  style: GoogleFonts.cairo(
                                    fontSize: 12,
                                    fontWeight: _selectedSemester == 2 ? FontWeight.bold : FontWeight.w600,
                                    color: _selectedSemester == 2 ? AppTheme.primary : AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // قائمة المواد الدراسية الكاملة
                Expanded(
                  child: courses.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.menu_book_outlined, size: 54, color: Color(0xFFCBD5E1)),
                              const SizedBox(height: 12),
                              Text(
                                'لا توجد مواد مطابقة للبحث',
                                style: GoogleFonts.cairo(color: AppTheme.textSecondary, fontSize: 13),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          cacheExtent: 600,
                          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          itemCount: courses.length,
                          itemBuilder: (context, index) {
                            final item = courses[index];
                            final statsList = _attendanceSummary?.subjectsStats
                                .where((s) =>
                                    s.subjectName.trim().toLowerCase() == item.originalName.toLowerCase() ||
                                    s.subjectName.trim().toLowerCase() == item.displayName.toLowerCase())
                                .toList();
                            final hasAttendance = statsList != null && statsList.isNotEmpty;
                            final stats = hasAttendance ? statsList.first : null;
                            return RepaintBoundary(
                              key: ValueKey('subj_card_${item.originalName}'),
                              child: _buildSubjectCard(
                                item: item,
                                stats: stats,
                                index: index,
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildSubjectCard({
    required CourseItemDisplay item,
    required SubjectAttendanceStats? stats,
    required int index,
  }) {
    final subModel = BiometricSubjects.findSubject(
      item.originalName,
      department: _effectiveDept,
      stage: _effectiveStage,
      semester: _selectedSemester,
    );

    final hasOverride = item.override != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: item.isHidden ? const Color(0xFFF8FAFC) : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: item.isHidden ? const Color(0xFFCBD5E1) : AppTheme.lightBorder,
          width: item.isHidden ? 1.2 : 1.0,
        ),
        boxShadow: item.isHidden ? [] : AppShadows.card,
      ),
      child: AppTactileBounce(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SubjectDetailScreen(
                subjectName: item.originalName,
                displayName: item.displayName,
                customCode: item.code,
                attendanceStats: stats,
                department: _effectiveDept,
                stage: _effectiveStage,
                section: _effectiveSection,
                semester: _selectedSemester,
              ),
            ),
          ).then((_) => _loadCourses(forceRefresh: true));
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              AppIconBadge.indigo(
                icon: BiometricSubjects.getIconForSubject(item.originalName),
                size: 48,
                iconSize: 24,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.displayName,
                            style: AppTypography.h3(
                              color: item.isHidden ? const Color(0xFF64748B) : AppTheme.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (item.isHidden) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFFCA5A5)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.visibility_off_rounded, size: 11, color: AppTheme.danger),
                                const SizedBox(width: 3),
                                Text(
                                  'مخفي للطلاب',
                                  style: GoogleFonts.cairo(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.danger,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (item.code != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Text(
                              item.code!,
                              style: GoogleFonts.cairo(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (item.displayName != item.originalName) ...[
                      const SizedBox(height: 2),
                      Text(
                        'الاسم الرسمي: ${item.originalName}',
                        style: AppTypography.tiny(color: AppTheme.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (subModel?.units != null) ...[
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.schedule_rounded, size: 12, color: Color(0xFF64748B)),
                                const SizedBox(width: 4),
                                Text(
                                  '${subModel!.units} وحدات',
                                  style: AppTypography.tiny(color: const Color(0xFF475569)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (_canManageCourses) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(
                    Icons.tune_rounded,
                    color: hasOverride ? AppTheme.primary : const Color(0xFF94A3B8),
                    size: 20,
                  ),
                  tooltip: 'تخصيص المقرر',
                  onPressed: () {
                    CourseCustomizationSheet.show(
                      context: context,
                      originalName: item.originalName,
                      defaultCode: subModel?.code,
                      department: _effectiveDept,
                      stage: _effectiveStage,
                      semester: _selectedSemester,
                      user: _user!,
                      currentOverride: item.override,
                      onSaved: () => _loadCourses(forceRefresh: true),
                    );
                  },
                ),
              ] else ...[
                const SizedBox(width: 8),
                const Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: Color(0xFF94A3B8)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
