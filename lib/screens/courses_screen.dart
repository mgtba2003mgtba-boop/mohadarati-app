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
  int _selectedSemester = 0; // 0 = كافة الفصول, 1 = الكورس الأول, 2 = الكورس الثاني

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
          ),
          service.fetchCourses(
            department: _user!.department,
            stage: _user!.stage,
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

  /// جلب كافة المقررات الدراسية (الخطة الدراسية المعتمدة + الحضور + المحاضرات)
  List<String> get _subjectNames {
    final names = <String>{};

    // 1. الخطة الأكاديمية والمقررات المعدلة من قبل الممثلين/الإدارة
    names.addAll(_coursesList);

    // 2. المواد المسجلة في سجلات الحضور
    if (_attendanceSummary != null) {
      for (final s in _attendanceSummary!.subjectsStats) {
        if (s.subjectName.trim().isNotEmpty) {
          names.add(s.subjectName.trim());
        }
      }
    }

    // 3. المواد التي لها محاضرات مرفوعة في السحابة
    for (final l in _lectures) {
      if (l.subjectName.trim().isNotEmpty) {
        names.add(l.subjectName.trim());
      }
    }

    List<String> list = names.toList();

    // فلترة الكورس الدراسي (الفصل 1 أو الفصل 2) وفق تصنيف البصمة
    if (_selectedSemester != 0 && _user != null) {
      final semesterSubjects = BiometricSubjects.getSubjectNames(
        department: _user!.department,
        stage: _user!.stage,
        semester: _selectedSemester,
      );
      if (semesterSubjects.isNotEmpty) {
        list = list.where((name) {
          return semesterSubjects.any((sub) =>
              sub.contains(name) || name.contains(sub) || sub.toLowerCase() == name.toLowerCase());
        }).toList();
      }
    }

    if (_searchQuery.isEmpty) return list;
    return list
        .where((name) => name.toLowerCase().contains(_searchQuery.toLowerCase().trim()))
        .toList();
  }

  void _showAddSubjectDialog() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primarySubtle,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.add_box_rounded, color: AppTheme.primary, size: 22),
            ),
            const SizedBox(width: 10),
            Text(
              'إضافة مقرر دراسي',
              style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'أدخل اسم المقرر المراد إضافته:',
              style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              autofocus: true,
              style: GoogleFonts.cairo(color: AppTheme.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'مثال: الذكاء الاصطناعي، شبكات...',
                filled: true,
                fillColor: AppTheme.lightSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.lightBorder),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('إلغاء', style: GoogleFonts.cairo(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = textController.text.trim();
              if (newName.isNotEmpty && _user != null) {
                Navigator.pop(ctx);
                final success = await SupabaseService().addCourse(
                  courseName: newName,
                  department: _user!.department,
                  stage: _user!.stage,
                  user: _user!,
                );
                if (mounted) {
                  _loadCourses();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success ? 'تمت إضافة المقرر بنجاح' : 'تعذر إضافة المقرر', style: GoogleFonts.cairo()),
                      backgroundColor: success ? AppTheme.success : AppTheme.danger,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('إضافة', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showEditSubjectDialog(String currentName) {
    final textController = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primarySubtle,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.edit_note_rounded, color: AppTheme.primary, size: 22),
            ),
            const SizedBox(width: 10),
            Text(
              'تعديل اسم المقرر',
              style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'الاسم الجديد للمقرر ($currentName):',
              style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              autofocus: true,
              style: GoogleFonts.cairo(color: AppTheme.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'الاسم الجديد للمقرر...',
                filled: true,
                fillColor: AppTheme.lightSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.lightBorder),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('إلغاء', style: GoogleFonts.cairo(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = textController.text.trim();
              if (newName.isNotEmpty && newName != currentName && _user != null) {
                Navigator.pop(ctx);
                final success = await SupabaseService().editCourse(
                  oldName: currentName,
                  newName: newName,
                  department: _user!.department,
                  stage: _user!.stage,
                  user: _user!,
                );
                if (mounted) {
                  _loadCourses();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success ? 'تم تعديل المقرر بنجاح' : 'تعذر تعديل المقرر', style: GoogleFonts.cairo()),
                      backgroundColor: success ? AppTheme.success : AppTheme.danger,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('حفظ التعديل', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showDeleteSubjectDialog(String subjectName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.delete_forever_rounded, color: AppTheme.danger, size: 22),
            ),
            const SizedBox(width: 10),
            Text(
              'حذف المقرر',
              style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.danger),
            ),
          ],
        ),
        content: Text(
          'هل أنت متأكد من حذف مقرر "$subjectName"؟',
          style: GoogleFonts.cairo(fontSize: 13, color: AppTheme.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('إلغاء', style: GoogleFonts.cairo(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_user != null) {
                Navigator.pop(ctx);
                final success = await SupabaseService().deleteCourse(
                  courseName: subjectName,
                  department: _user!.department,
                  stage: _user!.stage,
                  user: _user!,
                );
                if (mounted) {
                  _loadCourses();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success ? 'تم حذف المقرر بنجاح' : 'تعذر حذف المقرر', style: GoogleFonts.cairo()),
                      backgroundColor: success ? AppTheme.success : AppTheme.danger,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('حذف', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
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
          if (canManage)
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded, color: AppTheme.primary),
              tooltip: 'إضافة مقرر دراسي',
              onPressed: _showAddSubjectDialog,
            ),
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
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              ChoiceChip(
                                label: const Text('كافة المقررات'),
                                selected: _selectedSemester == 0,
                                onSelected: (_) => setState(() => _selectedSemester = 0),
                                selectedColor: AppTheme.primary,
                                labelStyle: GoogleFonts.cairo(
                                  color: _selectedSemester == 0 ? Colors.white : AppTheme.textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: const Text('الكورس الأول 📘'),
                                selected: _selectedSemester == 1,
                                onSelected: (_) => setState(() => _selectedSemester = 1),
                                selectedColor: AppTheme.primary,
                                labelStyle: GoogleFonts.cairo(
                                  color: _selectedSemester == 1 ? Colors.white : AppTheme.textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: const Text('الكورس الثاني 📙'),
                                selected: _selectedSemester == 2,
                                onSelected: (_) => setState(() => _selectedSemester = 2),
                                selectedColor: AppTheme.primary,
                                labelStyle: GoogleFonts.cairo(
                                  color: _selectedSemester == 2 ? Colors.white : AppTheme.textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
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
                if (_user?.canManageCourses == true || _user?.isRepresentative == true || _user?.isAdmin == true)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded, size: 20, color: Color(0xFF94A3B8)),
                    tooltip: 'خيارات المقرر',
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onSelected: (val) {
                      if (val == 'edit') {
                        _showEditSubjectDialog(subjectName);
                      } else if (val == 'delete') {
                        _showDeleteSubjectDialog(subjectName);
                      }
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            const Icon(Icons.edit_outlined, size: 18, color: AppTheme.primary),
                            const SizedBox(width: 8),
                            Text('تعديل المقرر', style: GoogleFonts.cairo(fontSize: 13, color: AppTheme.textPrimary)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            const Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.danger),
                            const SizedBox(width: 8),
                            Text('حذف المقرر', style: GoogleFonts.cairo(fontSize: 13, color: AppTheme.danger)),
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  const Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: Color(0xFF94A3B8)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
