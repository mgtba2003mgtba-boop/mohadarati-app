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

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  Future<void> _loadCourses() async {
    if (_coursesList.isEmpty && _lectures.isEmpty) {
      setState(() => _isLoading = true);
    }
    final service = SupabaseService();
    _user = service.currentUser;

    if (_user != null) {
      try {
        final results = await Future.wait([
          service.fetchStudentAttendance(_user!.studentId),
          service.fetchLectures(
            department: _user!.department,
            stage: _user!.stage,
            section: _user!.isAdmin ? null : _user!.section,
            semester: 1,
          ),
          service.fetchCourses(
            department: _user!.department,
            stage: _user!.stage,
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
      department: _user!.department,
      stage: _user!.stage,
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
            const StudyBookAnimation(size: 38, showGlow: false),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'المقررات والمواد الدراسية',
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  '${_user?.department ?? ''} • ${_user?.stage ?? ''}',
                  style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textMuted),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary),
            tooltip: 'تحديث المقررات',
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
                  // شريط البحث الأنيق
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Column(
                      children: [
                        TextField(
                          style: GoogleFonts.cairo(color: AppTheme.textPrimary, fontSize: 13),
                          onChanged: (val) => setState(() => _searchQuery = val),
                          decoration: InputDecoration(
                            hintText: 'ابحث باسم المادة أو المقرر الدراسي...',
                            hintStyle: GoogleFonts.cairo(color: AppTheme.textMuted, fontSize: 13),
                            prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.primary),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded, color: AppTheme.textMuted),
                                    onPressed: () => setState(() => _searchQuery = ''),
                                  )
                                : null,
                            filled: true,
                            fillColor: AppTheme.lightSurface,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(
                            color: AppTheme.primarySubtle,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.bookmark_added_rounded, color: AppTheme.primary, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'الفصل الدراسي الأول (الكورس 1) 📘 • نظام البصمة المعتمد',
                                style: GoogleFonts.cairo(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'الخطة الدراسية',
                              style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.primarySubtle,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${subjects.length} مواد متاحة',
                                style: GoogleFonts.cairo(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.lightBorder),
        boxShadow: AppTheme.cardShadow,
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
                  department: _user?.department,
                  stage: _user?.stage,
                ),
              ),
            ).then((_) => _loadCourses());
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                AppIconBadge.indigo(
                  icon: Icons.menu_book_rounded,
                  size: 48,
                  iconSize: 24,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subjectName,
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.video_library_rounded,
                            size: 14,
                            color: lectureCount > 0 ? AppTheme.accent : AppTheme.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            lectureCount > 0 ? '$lectureCount محاضرات' : 'المقرر متاح',
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              color: lectureCount > 0 ? AppTheme.accent : AppTheme.textMuted,
                              fontWeight: lectureCount > 0 ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: Color(0xFF94A3B8)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
