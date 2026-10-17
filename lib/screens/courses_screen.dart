import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants/app_constants.dart';
import '../core/constants/biometric_subjects.dart';
import '../core/theme/app_theme.dart';
import '../models/app_user_model.dart';
import '../models/attendance_model.dart';
import '../models/lecture_model.dart';
import '../services/supabase_service.dart';
import '../services/attendance_service.dart';
import '../widgets/study_book_animation.dart';
import '../widgets/app_icon_badge.dart';
import 'subject_detail_screen.dart';
import 'dashboard_screen.dart';
import '../services/admin_preview_service.dart';

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
  final int _selectedSemester = 1; // الكورس الأول حصراً

  bool get _isPrivileged =>
      _user?.isAdmin == true ||
      _user?.studentId == 'ST-NUST-001630760-413' ||
      (_user?.name.contains('مجتبى') ?? false);

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
    AdminPreviewService().addListener(_onAdminPreviewChanged);
    _loadCourses();
  }

  void _onAdminPreviewChanged() {
    if (mounted) _loadCourses(forceRefresh: true);
  }

  @override
  void dispose() {
    AdminPreviewService().removeListener(_onAdminPreviewChanged);
    super.dispose();
  }

  Future<void> _loadCourses({bool forceRefresh = false}) async {
    if (_coursesList.isEmpty && _lectures.isEmpty) {
      setState(() => _isLoading = true);
    }
    final service = SupabaseService();
    _user = service.currentUser;

    if (_user != null) {
      try {
        final results = await Future.wait([
          service.fetchStudentAttendance(_user!.studentId, forceRefresh: forceRefresh),
          service.fetchLectures(
            department: _effectiveDept,
            stage: _effectiveStage,
            section: _effectiveSection,
            semester: 1,
            forceRefresh: forceRefresh,
          ),
          service.fetchCourses(
            department: _effectiveDept,
            stage: _effectiveStage,
            semester: 1,
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

  /// جلب المواد الدراسية الرسمية المعتمدة حصراً من نظام البصمة الجامعي (الكورس الأول)
  List<String> get _subjectNames {
    if (_user == null) return [];

    final biometricList = BiometricSubjects.getSubjectNames(
      department: _effectiveDept,
      stage: _effectiveStage,
      semester: 1,
    );

    if (_searchQuery.isEmpty) return biometricList;
    return biometricList
        .where((name) => name.toLowerCase().contains(_searchQuery.toLowerCase().trim()))
        .toList();
  }



  @override
  Widget build(BuildContext context) {
    final canManage = _user?.canManageCourses == true || _user?.isRepresentative == true || _user?.isAdmin == true;
    final canPublish = _user?.canManageLectures == true || _user?.isAdmin == true;
    final subjects = _subjectNames;

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
                '${subjects.length}',
                style: GoogleFonts.cairo(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary),
            tooltip: 'تحديث',
            onPressed: _loadCourses,
          ),
        ],
      ),
      floatingActionButton: canPublish
          ? FloatingActionButton.extended(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              elevation: 4,
              icon: const Icon(Icons.upload_file_rounded),
              label: Text(
                'رفع محاضرة',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const DashboardScreen(initialTabIndex: 0),
                  ),
                ).then((_) => _loadCourses());
              },
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : RefreshIndicator(
              onRefresh: _loadCourses,
              color: AppTheme.primary,
              child: Column(
                children: [
                  // شريط البحث المقتضب
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(bottom: BorderSide(color: Color(0xFFE0E7FF), width: 1)),
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: TextField(
                      style: GoogleFonts.cairo(color: AppTheme.textPrimary, fontSize: 13),
                      onChanged: (val) => setState(() => _searchQuery = val),
                      decoration: InputDecoration(
                        hintText: 'بحث في المواد...',
                        hintStyle: GoogleFonts.cairo(color: AppTheme.textMuted, fontSize: 13),
                        prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.violet, size: 20),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, color: AppTheme.textMuted, size: 18),
                                onPressed: () => setState(() => _searchQuery = ''),
                              )
                            : null,
                        filled: true,
                        fillColor: AppTheme.lightSurface,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),

                  // قائمة المواد الدراسية الكاملة
                  Expanded(
                    child: subjects.isEmpty
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
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            itemCount: subjects.length,
                            itemBuilder: (context, index) {
                              final subName = subjects[index];
                              final statsList = _attendanceSummary?.subjectsStats
                                  .where((s) => s.subjectName.trim().toLowerCase() == subName.toLowerCase())
                                  .toList();
                              final hasAttendance = statsList != null && statsList.isNotEmpty;
                              final stats = hasAttendance ? statsList.first : null;
                              final lecCount = _lectures
                                  .where((l) => l.subjectName.trim().toLowerCase() == subName.toLowerCase())
                                  .length;

                              return _buildSubjectCard(
                                subjectName: subName,
                                lectureCount: lecCount,
                                stats: stats,
                                index: index,
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSubjectCard({
    required String subjectName,
    required int lectureCount,
    required SubjectAttendanceStats? stats,
    required int index,
  }) {
    final subModel = BiometricSubjects.findSubject(
      subjectName,
      department: _effectiveDept,
      stage: _effectiveStage,
    );

    final isViolet = index % 2 == 0;
    final accentColor = isViolet ? const Color(0xFF8B5CF6) : const Color(0xFF0EA5E9);
    final borderColor = isViolet ? const Color(0xFFDDD6FE) : const Color(0xFFBAE6FD);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SubjectDetailScreen(
                  subjectName: subjectName,
                  attendanceStats: stats,
                  department: _effectiveDept,
                  stage: _effectiveStage,
                  section: _effectiveSection,
                ),
              ),
            ).then((_) => _loadCourses());
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                isViolet
                    ? AppIconBadge.violet(
                        icon: Icons.menu_book_rounded,
                        size: 48,
                        iconSize: 24,
                      )
                    : AppIconBadge.sky(
                        icon: Icons.menu_book_rounded,
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
                              subjectName,
                              style: GoogleFonts.cairo(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (subModel?.code != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: isViolet ? const Color(0xFFF5F3FF) : const Color(0xFFF0F9FF),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: borderColor, width: 0.8),
                              ),
                              child: Text(
                                subModel!.code!,
                                style: GoogleFonts.cairo(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isViolet ? const Color(0xFF7C3AED) : const Color(0xFF0284C7),
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (subModel?.units != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFFCD34D)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.stars_rounded, size: 12, color: Color(0xFFD97706)),
                                  const SizedBox(width: 3),
                                  Text(
                                    '${subModel!.units} وحدات',
                                    style: GoogleFonts.cairo(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFFB45309),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Icon(
                            Icons.video_library_rounded,
                            size: 14,
                            color: lectureCount > 0 ? accentColor : AppTheme.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            lectureCount > 0 ? '$lectureCount محاضرات' : 'المقرر متاح',
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              color: lectureCount > 0 ? accentColor : AppTheme.textMuted,
                              fontWeight: lectureCount > 0 ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: accentColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
