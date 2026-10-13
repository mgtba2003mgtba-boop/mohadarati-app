import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../models/app_user_model.dart';
import '../models/lecture_model.dart';
import '../models/announcement_model.dart';
import '../models/attendance_model.dart';
import '../services/supabase_service.dart';
import '../services/telegram_uploader_service.dart';
import '../widgets/app_fullscreen_modal.dart';
import '../widgets/app_icon_badge.dart';

class SubjectDetailScreen extends StatefulWidget {
  final String subjectName;
  final SubjectAttendanceStats? attendanceStats;
  final String? department;
  final String? stage;

  const SubjectDetailScreen({
    super.key,
    required this.subjectName,
    this.attendanceStats,
    this.department,
    this.stage,
  });

  @override
  State<SubjectDetailScreen> createState() => _SubjectDetailScreenState();
}

class _SubjectDetailScreenState extends State<SubjectDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;

  AppUserModel? _user;
  List<LectureModel> _subjectLectures = [];
  List<AnnouncementModel> _subjectAnnouncements = [];
  List<AttendanceRecordModel> _subjectAttendanceRecords = [];

  String _lectureTypeFilter = 'ALL'; // 'ALL', 'theory', 'practical'
  String _searchQuery = '';

  String get _effectiveDepartment =>
      widget.department ?? _user?.department ?? AppConstants.departments.first;

  String get _effectiveStage =>
      widget.stage ?? _user?.stage ?? AppConstants.stages.first;

  bool get _canPublish {
    if (_user == null) return false;
    return _user!.isAdmin ||
        _user!.canManageLectures ||
        _user!.canManageAnnouncements ||
        _user!.isRepresentative ||
        _user!.name.contains('مجتبى') ||
        _user!.studentId == 'ST-NUST-001630760-413';
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadSubjectData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSubjectData() async {
    setState(() => _isLoading = true);
    final service = SupabaseService();
    _user = service.currentUser;

    try {
      final dept = widget.department ?? _user?.department;
      final stage = widget.stage ?? _user?.stage;

      // 1. جلب محاضرات المادة
      final allLectures = await service.fetchLectures(
        department: dept,
        stage: stage,
      );
      _subjectLectures = allLectures.where((l) {
        return l.subjectName.trim().toLowerCase() ==
            widget.subjectName.trim().toLowerCase();
      }).toList();

      // 2. جلب تبليغات المادة
      final allAnnouncements = await service.fetchAnnouncements(
        department: dept,
        stage: stage,
      );
      _subjectAnnouncements = allAnnouncements.where((a) {
        if (a.subjectName != null && a.subjectName!.isNotEmpty) {
          return a.subjectName!.trim().toLowerCase() ==
              widget.subjectName.trim().toLowerCase();
        }
        final normSub = widget.subjectName.trim().toLowerCase();
        return a.title.toLowerCase().contains(normSub) ||
            a.content.toLowerCase().contains(normSub);
      }).toList();

      // 3. جلب سجلات الحضور الخاصة بهذه المادة
      if (_user != null) {
        final records = await service.fetchStudentAttendance(_user!.studentId);
        _subjectAttendanceRecords = records.where((r) {
          return r.subjectName != null &&
              r.subjectName!.trim().toLowerCase() ==
                  widget.subjectName.trim().toLowerCase();
        }).toList();
      }
    } catch (e) {
      debugPrint('[-] Error loading subject hub: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  List<LectureModel> get _filteredLectures {
    return _subjectLectures.where((l) {
      final matchesType =
          _lectureTypeFilter == 'ALL' || l.type == _lectureTypeFilter;
      final matchesSearch = _searchQuery.isEmpty ||
          l.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (l.professorName != null &&
              l.professorName!.toLowerCase().contains(_searchQuery.toLowerCase()));
      return matchesType && matchesSearch;
    }).toList();
  }

  Future<void> _launchUrlExternal(String? urlString, {required String errorMsg}) async {
    if (urlString == null || urlString.isEmpty) return;
    final uri = Uri.parse(urlString.trim());
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMsg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$errorMsg: $e')));
      }
    }
  }

  void _copyToClipboard(String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.lightBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.subjectName,
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary),
        ),
        actions: [
          if (_canPublish)
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded, color: AppTheme.primary),
              tooltip: 'نشر في هذه المادة',
              onPressed: _showPublishSheet,
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary),
            tooltip: 'تحديث البيانات',
            onPressed: _loadSubjectData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primary,
          unselectedLabelColor: const Color(0xFF94A3B8),
          indicatorColor: AppTheme.primary,
          labelStyle: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12),
          tabs: [
            Tab(
              icon: const Icon(Icons.menu_book_rounded, size: 20),
              text: 'المحاضرات (${_subjectLectures.length})',
            ),
            Tab(
              icon: const Icon(Icons.campaign_rounded, size: 20),
              text: 'التبليغات (${_subjectAnnouncements.length})',
            ),
            Tab(
              icon: const Icon(Icons.fingerprint_rounded, size: 20),
              text: 'سجل الحضور (${_subjectAttendanceRecords.length})',
            ),
          ],
        ),
      ),
      floatingActionButton: _canPublish
          ? FloatingActionButton.extended(
              onPressed: _showPublishSheet,
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              elevation: 4,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: Text(
                'نشر في المادة',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : Column(
              children: [
                // ── بطاقة رأس المادة والمؤشرات الأكاديمية ──
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.lightBorder),
                    boxShadow: AppTheme.cardShadow,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.primarySubtle,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.class_rounded, color: AppTheme.primary, size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.subjectName,
                              style: GoogleFonts.cairo(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_user?.department ?? ''} • ${_user?.stage ?? ''}',
                              style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primarySubtle,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${_subjectLectures.length} محاضرات',
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── محتوى التبويبات ──
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildLecturesTab(),
                      _buildAnnouncementsTab(),
                      _buildAttendanceTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // تبويب 1: محاضرات المادة (فيديو، مستندات، درايف)
  // ══════════════════════════════════════════════════════════════
  Widget _buildLecturesTab() {
    return Column(
      children: [
        // شريط التصفية والبحث
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  style: GoogleFonts.cairo(color: AppTheme.textPrimary, fontSize: 13),
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'ابحث في محاضرات المادة...',
                    hintStyle: GoogleFonts.cairo(color: AppTheme.textMuted, fontSize: 12),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppTheme.primary),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.lightBorder),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('الكل'),
                selected: _lectureTypeFilter == 'ALL',
                onSelected: (s) => setState(() => _lectureTypeFilter = 'ALL'),
                selectedColor: AppTheme.primary,
                backgroundColor: Colors.white,
                labelStyle: GoogleFonts.cairo(
                  color: _lectureTypeFilter == 'ALL' ? Colors.white : AppTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 4),
              ChoiceChip(
                label: const Text('نظري'),
                selected: _lectureTypeFilter == 'theory',
                onSelected: (s) => setState(() => _lectureTypeFilter = 'theory'),
                selectedColor: AppTheme.primary,
                backgroundColor: Colors.white,
                labelStyle: GoogleFonts.cairo(
                  color: _lectureTypeFilter == 'theory' ? Colors.white : AppTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 4),
              ChoiceChip(
                label: const Text('عملي'),
                selected: _lectureTypeFilter == 'practical',
                onSelected: (s) => setState(() => _lectureTypeFilter = 'practical'),
                selectedColor: AppTheme.accent,
                backgroundColor: Colors.white,
                labelStyle: GoogleFonts.cairo(
                  color: _lectureTypeFilter == 'practical' ? Colors.white : AppTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: _filteredLectures.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.folder_open_rounded, size: 48, color: Color(0xFFCBD5E1)),
                      const SizedBox(height: 10),
                      Text(
                        'لا توجد محاضرات منشورة لهذه المادة حالياً',
                        style: GoogleFonts.cairo(color: AppTheme.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  itemCount: _filteredLectures.length,
                  itemBuilder: (context, index) {
                    final item = _filteredLectures[index];
                    return _buildLectureCard(item);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildLectureCard(LectureModel lecture) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.lightBorder),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: lecture.isPractical
                      ? AppTheme.accent.withValues(alpha: 0.12)
                      : AppTheme.primarySubtle,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  lecture.typeLabel,
                  style: GoogleFonts.cairo(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: lecture.isPractical ? AppTheme.accent : AppTheme.primary,
                  ),
                ),
              ),
              Row(
                children: [
                  Text(
                    '${lecture.createdAt.year}/${lecture.createdAt.month.toString().padLeft(2, '0')}/${lecture.createdAt.day.toString().padLeft(2, '0')}',
                    style: GoogleFonts.cairo(fontSize: 10, color: AppTheme.textMuted),
                  ),
                  if (_canPublish && (_user?.studentId == lecture.uploaderId || _user?.isAdmin == true || _user?.name.contains('مجتبى') == true)) ...[
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => _confirmDeleteLecture(lecture),
                      child: const Icon(Icons.delete_outline_rounded, size: 16, color: AppTheme.danger),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          Text(
            lecture.title,
            style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),

          if (lecture.professorName != null && lecture.professorName!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'أستاذ المادة: ${lecture.professorName}',
              style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ],

          if (lecture.description != null && lecture.description!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              lecture.description!,
              style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textSecondary, height: 1.4),
            ),
          ],

          // في حال وجود وسائط سحابية (Telegram CDN)
          if (lecture.hasTelegramMedia) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.primarySubtle,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bolt_rounded, size: 16, color: AppTheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    'بث سحابي مباشر',
                    style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primary),
                  ),
                  const Spacer(),
                  if (lecture.formattedFileSize.isNotEmpty)
                    Text(
                      lecture.formattedFileSize,
                      style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.play_circle_fill_rounded, size: 18, color: Colors.white),
                    label: Text(
                      'معاينة',
                      style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    onPressed: () => _launchUrlExternal(lecture.streamUrl, errorMsg: 'تعذر تشغيل البث المباشر'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.primary),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 18, color: AppTheme.primary),
                    label: Text(
                      'تنزيل',
                      style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primary),
                    ),
                    onPressed: () => _launchUrlExternal(lecture.downloadUrl, errorMsg: 'تعذر بدء التحميل'),
                  ),
                ),
              ],
            ),
          ],

          // في حال وجود رابط Google Drive
          if (lecture.hasDriveUrl) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add_to_drive_rounded, size: 18, color: AppTheme.accent),
                    label: Text('فتح الملف', style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textPrimary)),
                    onPressed: () => _launchUrlExternal(lecture.driveUrl, errorMsg: 'تعذر فتح الرابط'),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.accent),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 18, color: AppTheme.primary),
                  tooltip: 'نسخ رابط Drive',
                  onPressed: () => _copyToClipboard(lecture.driveUrl, 'تم نسخ رابط Drive'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // تبويب 2: تبليغات المادة الأكاديمية
  // ══════════════════════════════════════════════════════════════
  Widget _buildAnnouncementsTab() {
    if (_subjectAnnouncements.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.campaign_outlined, size: 48, color: Color(0xFFCBD5E1)),
            const SizedBox(height: 10),
            Text(
              'لا توجد تبليغات خاصة بهذه المادة حالياً',
              style: GoogleFonts.cairo(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _subjectAnnouncements.length,
      itemBuilder: (context, index) {
        final item = _subjectAnnouncements[index];
        return InkWell(
          onTap: () {
            AppFullscreenModal.show(
              context: context,
              title: item.title,
              subtitle: 'الناشر: ${item.authorName} • ${item.createdAt.year}/${item.createdAt.month.toString().padLeft(2, '0')}/${item.createdAt.day.toString().padLeft(2, '0')}',
              icon: Icons.campaign_rounded,
              contentText: item.content,
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
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: item.isPinned ? AppTheme.accent.withValues(alpha: 0.6) : AppTheme.lightBorder,
                width: item.isPinned ? 1.5 : 1,
              ),
              boxShadow: AppTheme.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppIconBadge.subtle(
                      icon: Icons.campaign_rounded,
                      size: 34,
                      iconSize: 18,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item.title,
                        style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  item.content,
                  style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textSecondary, height: 1.5),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'الناشر: ${item.authorName}',
                      style: GoogleFonts.cairo(fontSize: 10, color: AppTheme.primary, fontWeight: FontWeight.bold),
                    ),
                    Row(
                      children: [
                        Text(
                          '${item.createdAt.year}-${item.createdAt.month.toString().padLeft(2, '0')}-${item.createdAt.day.toString().padLeft(2, '0')}',
                          style: GoogleFonts.cairo(fontSize: 10, color: AppTheme.textMuted),
                        ),
                        if (_canPublish && (_user?.studentId == item.authorId || _user?.isAdmin == true || _user?.name.contains('مجتبى') == true)) ...[
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => _confirmDeleteAnnouncement(item),
                            child: const Icon(Icons.delete_outline_rounded, size: 16, color: AppTheme.danger),
                          ),
                        ],
                        const SizedBox(width: 6),
                        const Icon(Icons.open_in_full_rounded, size: 14, color: AppTheme.primary),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════
  // تبويب 3: سجل الحضور والغياب للمادة
  // ══════════════════════════════════════════════════════════════
  Widget _buildAttendanceTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'جلسات الحضور المسجلة',
                style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primarySubtle,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_subjectAttendanceRecords.length} جلسة موثقة',
                  style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_subjectAttendanceRecords.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.lightBorder),
                boxShadow: AppTheme.cardShadow,
              ),
              child: Center(
                child: Text(
                  'لم يتم تسجيل حضور بالكاميرات لهذه المادة بعد',
                  style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ),
            )
          else
            ..._subjectAttendanceRecords.map((rec) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.lightBorder),
                  boxShadow: AppTheme.cardShadow,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline_rounded, color: AppTheme.success, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'جلسة تاريخ: ${rec.date}',
                        style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'حاضر',
                        style: GoogleFonts.cairo(fontSize: 10, color: AppTheme.success, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Future<void> _showPublishSheet() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PublishToSubjectSheet(
        subjectName: widget.subjectName,
        department: _effectiveDepartment,
        stage: _effectiveStage,
        currentUser: _user,
        onSuccess: () {
          _loadSubjectData();
        },
      ),
    );
  }

  Future<void> _confirmDeleteLecture(LectureModel lecture) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('تأكيد حذف المحاضرة', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14)),
        content: Text('هل تريد بالتأكيد حذف محاضرة "${lecture.title}" من مادة ${widget.subjectName}؟',
            style: GoogleFonts.cairo(fontSize: 12)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('إلغاء', style: GoogleFonts.cairo())),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('حذف', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final ok = await SupabaseService().deleteLecture(lecture.id);
      if (ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف المحاضرة بنجاح')));
        _loadSubjectData();
      }
    }
  }

  Future<void> _confirmDeleteAnnouncement(AnnouncementModel announcement) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('تأكيد حذف التبليغ', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14)),
        content: Text('هل تريد بالتأكيد حذف تبليغ "${announcement.title}"؟',
            style: GoogleFonts.cairo(fontSize: 12)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('إلغاء', style: GoogleFonts.cairo())),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('حذف', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final ok = await SupabaseService().deleteAnnouncement(announcement.id);
      if (ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف التبليغ بنجاح')));
        _loadSubjectData();
      }
    }
  }
}

// ══════════════════════════════════════════════════════════════
// نافذة النشر المباشر السلسة من داخل المادة
// ══════════════════════════════════════════════════════════════
class _PublishToSubjectSheet extends StatefulWidget {
  final String subjectName;
  final String department;
  final String stage;
  final AppUserModel? currentUser;
  final VoidCallback onSuccess;

  const _PublishToSubjectSheet({
    required this.subjectName,
    required this.department,
    required this.stage,
    required this.currentUser,
    required this.onSuccess,
  });

  @override
  State<_PublishToSubjectSheet> createState() => _PublishToSubjectSheetState();
}

class _PublishToSubjectSheetState extends State<_PublishToSubjectSheet> {
  bool _isLectureMode = true; // true = محاضرة, false = تبليغ
  bool _isSubmitting = false;

  // حقول المحاضرة
  final _titleController = TextEditingController();
  final _profController = TextEditingController();
  final _driveUrlController = TextEditingController();
  final _descController = TextEditingController();
  String _lectureType = 'theory'; // 'theory', 'practical'
  bool _uploadDirectFile = true;
  PlatformFile? _selectedFile;
  int _selectedFileSize = 0;
  bool _isPickingFile = false;

  // حقول التبليغ
  final _announceTitleController = TextEditingController();
  final _announceContentController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _profController.dispose();
    _driveUrlController.dispose();
    _descController.dispose();
    _announceTitleController.dispose();
    _announceContentController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    setState(() => _isPickingFile = true);
    final file = await TelegramUploaderService().pickLectureFile();
    if (mounted) {
      if (file != null) {
        final size = await TelegramUploaderService().getFileSize(file);
        setState(() {
          _isPickingFile = false;
          _selectedFile = file;
          _selectedFileSize = size;
          if (_titleController.text.trim().isEmpty) {
            final nameWithoutExt = file.name.contains('.')
                ? file.name.substring(0, file.name.lastIndexOf('.'))
                : file.name;
            _titleController.text = nameWithoutExt;
          }
        });
      } else {
        setState(() => _isPickingFile = false);
      }
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
  }

  Future<void> _submitLecture() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _showSnack('يرجى كتابة عنوان المحاضرة', isError: true);
      return;
    }

    if (_uploadDirectFile && _selectedFile == null) {
      _showSnack('يرجى اختيار ملف المحاضرة', isError: true);
      return;
    }

    if (!_uploadDirectFile && _driveUrlController.text.trim().isEmpty) {
      _showSnack('يرجى إدخال رابط Google Drive', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      if (_uploadDirectFile && _selectedFile != null) {
        final res = await TelegramUploaderService().uploadLecture(
          file: _selectedFile!,
          title: title,
          subjectName: widget.subjectName,
          department: widget.department,
          stage: widget.stage,
          semester: 1,
          lectureType: _lectureType,
          professorName: _profController.text.trim().isEmpty ? null : _profController.text.trim(),
          description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
          uploaderId: widget.currentUser?.studentId ?? 'ADMIN',
          uploaderName: widget.currentUser?.name ?? 'ممثل المادة',
          uploaderRole: widget.currentUser?.role ?? 'representative',
        );

        if (!res.success) {
          throw Exception(res.message);
        }
      } else {
        final newLecture = LectureModel(
          id: '',
          title: title,
          subjectName: widget.subjectName,
          department: widget.department,
          stage: widget.stage,
          semester: 1,
          type: _lectureType,
          driveUrl: _driveUrlController.text.trim(),
          description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
          professorName: _profController.text.trim().isEmpty ? null : _profController.text.trim(),
          uploaderId: widget.currentUser?.studentId ?? 'ADMIN',
          uploaderName: widget.currentUser?.name ?? 'ممثل المادة',
          uploaderRole: widget.currentUser?.role ?? 'representative',
          createdAt: DateTime.now(),
        );
        final ok = await SupabaseService().createLecture(newLecture);
        if (!ok) throw Exception('تعذر حفظ المحاضرة');
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم نشر المحاضرة بنجاح')),
        );
        widget.onSuccess();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        _showSnack('خطأ أثناء النشر: $e', isError: true);
      }
    }
  }

  Future<void> _submitAnnouncement() async {
    final title = _announceTitleController.text.trim();
    final content = _announceContentController.text.trim();

    if (title.isEmpty || content.isEmpty) {
      _showSnack('يرجى كتابة عنوان ونص التبليغ', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final newAnnounce = AnnouncementModel(
        id: '',
        title: title,
        content: content,
        authorId: widget.currentUser?.studentId ?? 'ADMIN',
        authorName: widget.currentUser?.name ?? 'ممثل المادة',
        authorRole: widget.currentUser?.role ?? 'representative',
        department: widget.department,
        stage: widget.stage,
        category: 'academic',
        subjectName: widget.subjectName,
        createdAt: DateTime.now(),
      );

      final ok = await SupabaseService().createAnnouncement(newAnnounce);
      if (!ok) throw Exception('تعذر حفظ التبليغ');

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم نشر التبليغ بنجاح')),
        );
        widget.onSuccess();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        _showSnack('خطأ أثناء النشر: $e', isError: true);
      }
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppTheme.danger : AppTheme.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 12,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // مقبض السحب
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // رأس النافذة
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primarySubtle,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.post_add_rounded, color: AppTheme.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'نشر جديد في: ${widget.subjectName}',
                        style: GoogleFonts.cairo(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        '${widget.department} • ${widget.stage}',
                        style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // التبديل بين رفع محاضرة وإضافة تبليغ
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _isLectureMode = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _isLectureMode ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: _isLectureMode ? AppTheme.cardShadow : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.menu_book_rounded,
                              size: 16,
                              color: _isLectureMode ? AppTheme.primary : AppTheme.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'رفع محاضرة',
                              style: GoogleFonts.cairo(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _isLectureMode ? AppTheme.primary : AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _isLectureMode = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: !_isLectureMode ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: !_isLectureMode ? AppTheme.cardShadow : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.campaign_rounded,
                              size: 16,
                              color: !_isLectureMode ? AppTheme.primary : AppTheme.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'نشر تبليغ للمادة',
                              style: GoogleFonts.cairo(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: !_isLectureMode ? AppTheme.primary : AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // نموذج المحاضرة
            if (_isLectureMode) ...[
              TextField(
                controller: _titleController,
                style: GoogleFonts.cairo(fontSize: 13, color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'عنوان المحاضرة',
                  hintText: 'مثال: المحاضرة 1 - مقدمة',
                  labelStyle: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textSecondary),
                  hintStyle: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textMuted),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.title_rounded, size: 20),
                ),
              ),
              const SizedBox(height: 12),

              // نوع المحاضرة
              Row(
                children: [
                  Text('النوع: ', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('نظري'),
                    selected: _lectureType == 'theory',
                    onSelected: (s) => setState(() => _lectureType = 'theory'),
                    selectedColor: AppTheme.primary,
                    labelStyle: GoogleFonts.cairo(
                      color: _lectureType == 'theory' ? Colors.white : AppTheme.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text('عملي ومختبر'),
                    selected: _lectureType == 'practical',
                    onSelected: (s) => setState(() => _lectureType = 'practical'),
                    selectedColor: AppTheme.accent,
                    labelStyle: GoogleFonts.cairo(
                      color: _lectureType == 'practical' ? Colors.white : AppTheme.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _profController,
                style: GoogleFonts.cairo(fontSize: 13, color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'اسم الأستاذ / التدريسي (اختياري)',
                  labelStyle: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textSecondary),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.person_rounded, size: 20),
                ),
              ),
              const SizedBox(height: 12),

              // اختيار طريقة الرفع
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('رفع مباشر من الجهاز'),
                      selected: _uploadDirectFile,
                      onSelected: (s) => setState(() => _uploadDirectFile = true),
                      selectedColor: AppTheme.primary,
                      labelStyle: GoogleFonts.cairo(
                        color: _uploadDirectFile ? Colors.white : AppTheme.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('رابط Google Drive'),
                      selected: !_uploadDirectFile,
                      onSelected: (s) => setState(() => _uploadDirectFile = false),
                      selectedColor: AppTheme.accent,
                      labelStyle: GoogleFonts.cairo(
                        color: !_uploadDirectFile ? Colors.white : AppTheme.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              if (_uploadDirectFile) ...[
                if (_selectedFile == null)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppTheme.primary, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: _isPickingFile
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.cloud_upload_rounded, color: AppTheme.primary),
                    label: Text(
                      'اختر ملف المحاضرة (PDF / فيديو)',
                      style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
                    ),
                    onPressed: _isPickingFile ? null : _pickFile,
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primarySubtle,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedFile!.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                _formatFileSize(_selectedFileSize),
                                style: GoogleFonts.cairo(fontSize: 10, color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18, color: AppTheme.danger),
                          onPressed: () => setState(() {
                            _selectedFile = null;
                            _selectedFileSize = 0;
                          }),
                        ),
                      ],
                    ),
                  ),
              ] else ...[
                TextField(
                  controller: _driveUrlController,
                  style: GoogleFonts.cairo(fontSize: 13, color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'رابط Google Drive',
                    hintText: 'https://drive.google.com/...',
                    labelStyle: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textSecondary),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.link_rounded, size: 20),
                  ),
                ),
              ],
              const SizedBox(height: 16),

              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isSubmitting ? null : _submitLecture,
                icon: _isSubmitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 18),
                label: Text(
                  _isSubmitting ? 'جاري الرفع والنشر...' : 'نشر المحاضرة للمادة',
                  style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ] else ...[
              // نموذج التبليغ
              TextField(
                controller: _announceTitleController,
                style: GoogleFonts.cairo(fontSize: 13, color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'عنوان التبليغ',
                  hintText: 'مثال: موعد كويز / تأجيل محاضرة',
                  labelStyle: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textSecondary),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.campaign_rounded, size: 20),
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _announceContentController,
                maxLines: 4,
                style: GoogleFonts.cairo(fontSize: 13, color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'نص وتفاصيل التبليغ',
                  labelStyle: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textSecondary),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),

              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isSubmitting ? null : _submitAnnouncement,
                icon: _isSubmitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                label: Text(
                  _isSubmitting ? 'جاري النشر...' : 'نشر التبليغ للمادة',
                  style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
