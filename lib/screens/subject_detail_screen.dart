import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import '../core/constants/app_constants.dart';
import '../core/constants/biometric_subjects.dart';
import '../core/theme/app_theme.dart';
import '../models/app_user_model.dart';
import '../models/lecture_model.dart';
import '../models/announcement_model.dart';
import '../models/attendance_model.dart';
import '../services/app_notification_service.dart';
import '../services/supabase_service.dart';
import '../services/telegram_uploader_service.dart';
import '../widgets/app_fullscreen_modal.dart';
import '../widgets/app_icon_badge.dart';
import '../widgets/app_media_preview_modal.dart';
import '../widgets/telegram_announcement_card.dart';
import '../widgets/telegram_poll_card.dart';
import '../widgets/create_poll_sheet.dart';
import '../services/admin_preview_service.dart';
import '../models/lecture_comment_model.dart';
import '../widgets/app_tactile_bounce.dart';

class SubjectDetailScreen extends StatefulWidget {
  final String subjectName;
  final String? displayName;
  final String? customCode;
  final SubjectAttendanceStats? attendanceStats;
  final String? department;
  final String? stage;
  final String? section;
  final int? semester;

  const SubjectDetailScreen({
    super.key,
    required this.subjectName,
    this.displayName,
    this.customCode,
    this.attendanceStats,
    this.department,
    this.stage,
    this.section,
    this.semester,
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
  String _selectedSectionFilter = 'ALL'; // 'ALL', 'A', 'B', 'C', 'D', 'UNIFIED'
  String _searchQuery = '';

  bool get _isPrivileged =>
      _user?.isAdmin == true ||
      _user?.studentId == 'ST-NUST-001630760-413' ||
      (_user?.name.contains('مجتبى') ?? false);

  String get _effectiveDepartment {
    final preview = AdminPreviewService();
    return widget.department ?? (_isPrivileged ? preview.department : _user?.department) ?? AppConstants.departments.first;
  }

  String get _effectiveStage {
    final preview = AdminPreviewService();
    return widget.stage ?? (_isPrivileged ? preview.stage : _user?.stage) ?? AppConstants.stages.first;
  }

  String? get _effectiveSection {
    final preview = AdminPreviewService();
    return widget.section ?? (_isPrivileged ? preview.section : _user?.section);
  }

  bool get _canPublish {
    if (_user == null) return false;
    return _user!.isAdmin ||
        _user!.canManageLectures ||
        _user!.canManageAnnouncements ||
        _user!.isRepresentative ||
        _user!.name.contains('مجتبى') ||
        _user!.studentId == 'ST-NUST-001630760-413';
  }

  StreamSubscription<AnnouncementModel>? _announcementInsertSub;
  StreamSubscription<AnnouncementModel>? _announcementUpdateSub;

  @override
  void initState() {
    super.initState();
    final sec = widget.section ?? (AdminPreviewService().isCustomActive ? AdminPreviewService().section : null);
    if (sec != null && sec.isNotEmpty) {
      _selectedSectionFilter = sec;
    }
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadSubjectData(showSpinner: true);

    // ── الاستماع اللحظي لتحديث التفاعلات السحابية للتبليغات ──
    _announcementUpdateSub = AppNotificationService().announcementUpdateStream.listen((updated) {
      if (!mounted) return;
      setState(() {
        final idx = _subjectAnnouncements.indexWhere((a) => a.id == updated.id);
        if (idx != -1) {
          _subjectAnnouncements[idx] = updated;
        }
      });
    });

    // ── الاستماع اللحظي لإضافة تبليغات جديدة للمادة دون وميض الشاشة ──
    _announcementInsertSub = AppNotificationService().announcementInsertStream.listen((inserted) {
      if (!mounted) return;
      final matchSub = inserted.subjectName != null &&
          (AppConstants.arabicEquals(inserted.subjectName!, widget.subjectName) ||
              AppConstants.arabicContains(inserted.subjectName!, widget.subjectName) ||
              AppConstants.arabicContains(widget.subjectName, inserted.subjectName!));
      if (matchSub && !_subjectAnnouncements.any((a) => a.id == inserted.id)) {
        setState(() {
          _subjectAnnouncements.insert(0, inserted);
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _announcementInsertSub?.cancel();
    _announcementUpdateSub?.cancel();
    super.dispose();
  }

  bool _matchesSubject(String? name) {
    if (name == null || name.trim().isEmpty) return false;
    final clean = name.trim();
    final normClean = AppConstants.normalizeArabic(clean);
    final normSubject = AppConstants.normalizeArabic(widget.subjectName);
    if (normClean.isEmpty || normSubject.isEmpty) return false;

    if (normClean == normSubject ||
        normClean.contains(normSubject) ||
        (normClean.length >= 4 && normSubject.contains(normClean))) {
      return true;
    }
    if (widget.displayName != null && widget.displayName!.trim().isNotEmpty) {
      final normDisp = AppConstants.normalizeArabic(widget.displayName!.trim());
      if (normDisp.isNotEmpty) {
        if (normClean == normDisp ||
            normClean.contains(normDisp) ||
            (normClean.length >= 4 && normDisp.contains(normClean))) {
          return true;
        }
      }
    }
    return false;
  }

  Future<void> _loadSubjectData({bool forceRefresh = false, bool showSpinner = false}) async {
    if (showSpinner || (_subjectLectures.isEmpty && _subjectAnnouncements.isEmpty)) {
      setState(() => _isLoading = true);
    }
    final service = SupabaseService();
    _user = service.currentUser;

    try {
      final dept = _effectiveDepartment;
      final stage = _effectiveStage;
      final userSection = _effectiveSection;
      final activeSemester = widget.semester ?? _user?.semester ?? 1;

      // 1. جلب محاضرات المادة (مع حصر الشعبة للطلبة والممثلين ودعم التطبيع العربي المزدوج)
      final allLectures = await service.fetchLectures(
        department: dept,
        stage: stage,
        section: userSection,
        semester: activeSemester,
        forceRefresh: forceRefresh,
      );
      _subjectLectures = allLectures.where((l) => _matchesSubject(l.subjectName)).toList();

      // 2. جلب تبليغات المادة (مع حصر الشعبة للطلبة والممثلين ودعم التطبيع العربي المزدوج)
      final allAnnouncements = await service.fetchAnnouncements(
        department: dept,
        stage: stage,
        section: userSection,
        forceRefresh: forceRefresh,
      );
      _subjectAnnouncements = allAnnouncements.where((a) {
        if (a.subjectName == 'LECTURE_NOTE' ||
            a.subjectName == 'COURSE_OVERRIDE' ||
            a.content.contains('[LECTURE_NOTE_V1]') ||
            a.content.contains('[COURSE_OVERRIDE')) {
          return false;
        }
        final hasBody = a.displayContent.trim().isNotEmpty ||
            (a.imageUrl != null && a.imageUrl!.trim().isNotEmpty && a.imageUrl != 'null' && a.imageUrl != 'undefined') ||
            a.isPoll;
        if (!hasBody) return false;

        // تبليغات المادة حصراً: التبليغات العامة لا تنتمي إلى تبويب المادة
        if (a.subjectName != null && a.subjectName!.trim().isNotEmpty && a.subjectName != 'عام') {
          return _matchesSubject(a.subjectName);
        }
        return false;
      }).toList();

      // 3. جلب سجلات الحضور الخاصة بهذه المادة
      if (_user != null) {
        final records = await service.fetchStudentAttendance(_user!.studentId, forceRefresh: forceRefresh);
        _subjectAttendanceRecords = records.where((r) => _matchesSubject(r.subjectName)).toList();
      }
    } catch (e) {
      debugPrint('[-] Error loading subject hub: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  List<LectureModel> get _filteredLectures {
    final bool isAdmin = _user?.isAdmin == true;
    final String userSec = _user?.section ?? '';

    return _subjectLectures.where((l) {
      final matchesType =
          _lectureTypeFilter == 'ALL' || l.type == _lectureTypeFilter;

      final bool matchesSection;
      if (isAdmin) {
        matchesSection = _selectedSectionFilter == 'ALL' ||
            (_selectedSectionFilter == 'UNIFIED'
                ? (l.section == 'ALL' || l.section.isEmpty)
                : (l.section.toUpperCase() == _selectedSectionFilter.toUpperCase() || l.section == 'ALL'));
      } else {
        // للطالب أو الممثل: تظهر فقط محاضرات شعبته والمحاضرات الموحدة، وأي محاضرة قام هو برفعها
        final bool isAuthor = _user != null && (_user!.studentId == l.uploaderId);
        matchesSection = isAuthor ||
            l.section == 'ALL' ||
            l.section.isEmpty ||
            (userSec.isNotEmpty && l.section.toUpperCase() == userSec.toUpperCase());
      }

      final matchesSearch = _searchQuery.isEmpty ||
          l.title.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesType && matchesSection && matchesSearch;
    }).toList();
  }

  List<AnnouncementModel> get _filteredAnnouncements {
    final bool isAdmin = _user?.isAdmin == true;
    final String userSec = _user?.section ?? '';

    return _subjectAnnouncements.where((a) {
      final bool matchesSection;
      if (isAdmin) {
        matchesSection = _selectedSectionFilter == 'ALL' ||
            (_selectedSectionFilter == 'UNIFIED'
                ? (a.section == 'ALL' || a.section.isEmpty)
                : (a.section.toUpperCase() == _selectedSectionFilter.toUpperCase() || a.section == 'ALL'));
      } else {
        // للطالب أو الممثل: تظهر فقط تبليغات شعبته والتبليغات العامة الموحدة، وأي تبليغ نشره هو بنفسه
        final bool isAuthor = _user != null && (_user!.studentId == a.authorId);
        matchesSection = isAuthor ||
            a.section == 'ALL' ||
            a.section.isEmpty ||
            (userSec.isNotEmpty && a.section.toUpperCase() == userSec.toUpperCase());
      }

      final matchesSearch = _searchQuery.isEmpty ||
          a.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          a.content.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesSection && matchesSearch;
    }).toList();
  }

  int _countLecturesForSection(String sec) {
    if (sec == 'ALL') return _subjectLectures.length;
    if (sec == 'UNIFIED') {
      return _subjectLectures.where((l) => l.section == 'ALL' || l.section.isEmpty).length;
    }
    return _subjectLectures.where((l) => l.section.toUpperCase() == sec.toUpperCase()).length;
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

  Future<void> _launchLectureMedia(LectureModel lecture, {required bool isDownload}) async {
    String? targetUrl;

    if (lecture.telegramFileId != null && lecture.telegramFileId!.isNotEmpty) {
      final fresh = await TelegramUploaderService().resolveFileUrl(lecture.telegramFileId!);
      if (fresh != null && fresh.isNotEmpty) {
        targetUrl = fresh;
      }
    }

    if (targetUrl == null || targetUrl.isEmpty) {
      if (lecture.driveUrl.startsWith('http')) {
        targetUrl = lecture.driveUrl;
      } else {
        targetUrl = isDownload ? lecture.downloadUrl : lecture.streamUrl;
      }
    }

    if (targetUrl != null && targetUrl.isNotEmpty) {
      if (isDownload) {
        await _launchUrlExternal(
          targetUrl,
          errorMsg: 'تعذر بدء تحميل المحاضرة',
        );
      } else {
        if (!mounted) return;
        AppMediaPreviewModal.show(
          context: context,
          title: lecture.title,
          subtitle: '${lecture.subjectName} • ${lecture.typeLabel}${lecture.formattedFileSize.isNotEmpty ? " • ${lecture.formattedFileSize}" : ""}',
          url: targetUrl,
          downloadUrl: lecture.downloadUrl ?? targetUrl,
          fileName: lecture.fileName ?? lecture.title,
          mimeType: lecture.mimeType,
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('رابط المحاضرة غير متوفر')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final subModel = BiometricSubjects.findSubject(
      widget.subjectName,
      department: _effectiveDepartment,
      stage: _effectiveStage,
    );

    final effectiveDisplayName = widget.displayName ?? widget.subjectName;
    final effectiveCode = widget.customCode ?? subModel?.code;

    return Scaffold(
      backgroundColor: AppTheme.lightBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              effectiveDisplayName,
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              children: [
                if (effectiveCode != null)
                  Text(
                    'كود: $effectiveCode  ',
                    style: GoogleFonts.cairo(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.primary),
                  ),
                if (effectiveDisplayName != widget.subjectName)
                  Text(
                    '• رسمياً: ${widget.subjectName}  ',
                    style: GoogleFonts.cairo(fontSize: 10, color: AppTheme.textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (subModel?.units != null)
                  Text(
                    '•  ${subModel!.units} وحدات',
                    style: GoogleFonts.cairo(fontSize: 10.5, fontWeight: FontWeight.w500, color: AppTheme.textSecondary),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          if (_canPublish) ...[
            if (_tabController.index == 0)
              IconButton(
                icon: const Icon(Icons.upload_file_rounded, color: AppTheme.primary),
                tooltip: 'نشر محاضرة جديدة',
                onPressed: () => _showPublishSheet(initialMode: 'lecture'),
              )
            else if (_tabController.index == 1) ...[
              IconButton(
                icon: const Icon(Icons.poll_rounded, color: AppTheme.primary),
                tooltip: 'إنشاء تصويت للمادة',
                onPressed: () {
                  if (_user != null) {
                    CreatePollSheet.show(
                      context: context,
                      currentUser: _user!,
                      department: _effectiveDepartment,
                      stage: _effectiveStage,
                      subjectName: widget.subjectName,
                      onSuccess: (_) => _loadSubjectData(forceRefresh: true),
                    );
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.campaign_rounded, color: AppTheme.primary),
                tooltip: 'نشر تبليغ للمادة',
                onPressed: () => _showPublishSheet(initialMode: 'announcement'),
              ),
            ],
          ],
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary),
            tooltip: 'تحديث البيانات',
            onPressed: () => _loadSubjectData(forceRefresh: true, showSpinner: false),
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
      floatingActionButton: (_canPublish && _tabController.index != 2)
          ? (_tabController.index == 0
              ? FloatingActionButton.extended(
                  onPressed: () => _showPublishSheet(initialMode: 'lecture'),
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 4,
                  icon: const Icon(Icons.upload_file_rounded, size: 20),
                  label: Text(
                    'نشر محاضرة جديدة',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                )
              : FloatingActionButton.extended(
                  onPressed: () => _showPublishSheet(initialMode: 'announcement'),
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.black,
                  elevation: 4,
                  icon: const Icon(Icons.campaign_rounded, size: 20),
                  label: Text(
                    'نشر تبليغ للمادة',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ))
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildLecturesTab(),
                _buildAnnouncementsTab(),
                _buildAttendanceTab(),
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

        // شريط فلاتر الشُعب / الكروبات (خاص بالمشرف العام فقط لتبديل واستعراض الكروبات)
        if (_user?.isAdmin == true)
          Container(
            height: 38,
            margin: const EdgeInsets.fromLTRB(0, 0, 0, 8),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildSectionFilterChip('ALL', 'الكل 🌐', _subjectLectures.length),
                const SizedBox(width: 6),
                _buildSectionFilterChip('A', 'شعبة A', _countLecturesForSection('A')),
                const SizedBox(width: 6),
                _buildSectionFilterChip('B', 'شعبة B', _countLecturesForSection('B')),
                const SizedBox(width: 6),
                _buildSectionFilterChip('C', 'شعبة C', _countLecturesForSection('C')),
                const SizedBox(width: 6),
                _buildSectionFilterChip('D', 'شعبة D', _countLecturesForSection('D')),
                const SizedBox(width: 6),
                _buildSectionFilterChip('UNIFIED', 'موحد 📋', _countLecturesForSection('UNIFIED')),
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
                        'لا توجد محاضرات منشورة لهذه الشعبة حالياً',
                        style: GoogleFonts.cairo(color: AppTheme.textSecondary, fontSize: 13),
                      ),
                      if (_canPublish) ...[
                        const SizedBox(height: 14),
                        ElevatedButton.icon(
                          onPressed: () => _showPublishSheet(initialMode: 'lecture'),
                          icon: const Icon(Icons.upload_file_rounded, size: 18, color: Colors.white),
                          label: Text('نشر أول محاضرة الآن', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
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

  Widget _buildSectionFilterChip(String sectionKey, String label, int count) {
    final isSelected = _selectedSectionFilter == sectionKey;
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (count > 0) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withValues(alpha: 0.25) : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: GoogleFonts.cairo(
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : const Color(0xFF475569),
                ),
              ),
            ),
          ],
        ],
      ),
      selected: isSelected,
      onSelected: (s) => setState(() => _selectedSectionFilter = sectionKey),
      selectedColor: const Color(0xFF0F172A),
      backgroundColor: Colors.white,
      labelStyle: GoogleFonts.cairo(
        color: isSelected ? const Color(0xFF38BDF8) : AppTheme.textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.bold,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(
          color: isSelected ? const Color(0xFF0F172A) : AppTheme.lightBorder,
        ),
      ),
    );
  }

  Widget _buildSectionBadge(String section) {
    Color bg;
    Color border;
    Color text;
    String label;

    switch (section.toUpperCase()) {
      case 'A':
        bg = const Color(0xFFEFF6FF);
        border = const Color(0xFFBFDBFE);
        text = const Color(0xFF1D4ED8);
        label = 'شعبة A';
        break;
      case 'B':
        bg = const Color(0xFFFAF5FF);
        border = const Color(0xFFE9D5FF);
        text = const Color(0xFF7E22CE);
        label = 'شعبة B';
        break;
      case 'C':
        bg = const Color(0xFFFFFBEB);
        border = const Color(0xFFFDE68A);
        text = const Color(0xFFB45309);
        label = 'شعبة C';
        break;
      case 'D':
        bg = const Color(0xFFF0FDFA);
        border = const Color(0xFF99F6E4);
        text = const Color(0xFF0F766E);
        label = 'شعبة D';
        break;
      case 'ALL':
      default:
        bg = const Color(0xFFECFDF5);
        border = const Color(0xFFA7F3D0);
        text = const Color(0xFF047857);
        label = 'موحد للجميع';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: GoogleFonts.cairo(
          fontSize: 9.5,
          fontWeight: FontWeight.bold,
          color: text,
        ),
      ),
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
              Row(
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
                  if (_user?.isAdmin == true) ...[
                    const SizedBox(width: 6),
                    _buildSectionBadge(lecture.section),
                  ],
                ],
              ),
              Row(
                children: [
                  Text(
                    '${lecture.createdAt.year}/${lecture.createdAt.month.toString().padLeft(2, '0')}/${lecture.createdAt.day.toString().padLeft(2, '0')}',
                    style: GoogleFonts.cairo(fontSize: 10, color: AppTheme.textMuted),
                  ),
                  if (_canPublish) ...[
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

          if (_user?.isAdmin == true && (lecture.uploaderName.isNotEmpty || lecture.uploaderRole.isNotEmpty)) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.person_outline_rounded, size: 13, color: AppTheme.textMuted),
                const SizedBox(width: 4),
                Text(
                  lecture.uploaderRole == "admin"
                      ? 'الناشر: إدارة الكلية (إشراف عام 🛡️)'
                      : 'الناشر: ممثل شعبة ${lecture.section} ⭐ (${lecture.uploaderName})',
                  style: GoogleFonts.cairo(fontSize: 10.5, color: AppTheme.textMuted),
                ),
              ],
            ),
          ],

          const SizedBox(height: 2),

          if (lecture.displayDescription.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              lecture.displayDescription,
              style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textSecondary, height: 1.4),
            ),
          ],

          // في حال وجود وسائط
          if (lecture.hasTelegramMedia) ...[
            if (lecture.formattedFileSize.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.description_outlined, size: 14, color: AppTheme.textMuted),
                  const SizedBox(width: 4),
                  Text(
                    'حجم الملف: ${lecture.formattedFileSize}',
                    style: GoogleFonts.cairo(fontSize: 10.5, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ],
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
                    icon: const Icon(Icons.visibility_rounded, size: 18, color: Colors.white),
                    label: Text(
                      'معاينة',
                      style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    onPressed: () => _launchLectureMedia(lecture, isDownload: false),
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
                    onPressed: () => _launchLectureMedia(lecture, isDownload: true),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          // زر استفسارات وملاحظات المحاضرة الأكاديمية
          AppTactileBounce(
            onTap: () => _openLectureCommentsSheet(lecture),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.forum_outlined, size: 16, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'استفسارات المحاضرة',
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 11, color: AppTheme.textMuted),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // تبويب 2: تبليغات المادة الأكاديمية
  // ══════════════════════════════════════════════════════════════
  Widget _buildAnnouncementsTab() {
    final announcements = _filteredAnnouncements;
    if (announcements.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.campaign_outlined, size: 48, color: Color(0xFFCBD5E1)),
            const SizedBox(height: 10),
            Text(
              'لا توجد تبليغات خاصة بهذه الشعبة حالياً',
              style: GoogleFonts.cairo(color: AppTheme.textSecondary, fontSize: 13),
            ),
            if (_canPublish) ...[
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: () => _showPublishSheet(initialMode: 'announcement'),
                icon: const Icon(Icons.campaign_rounded, size: 18, color: Colors.black),
                label: Text('نشر أول تبليغ الآن', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return ListView.builder(
      cacheExtent: 800,
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: announcements.length,
      itemBuilder: (context, index) {
        final item = announcements[index];
        if (item.isPoll) {
          return RepaintBoundary(
            key: ValueKey('subj_poll_b_${item.id}'),
            child: TelegramPollCard(
              key: ValueKey('subj_poll_${item.id}'),
              announcement: item,
              currentUser: _user,
              onVoteChanged: () => _loadSubjectData(forceRefresh: false, showSpinner: false),
              onDelete: () => _confirmDeleteAnnouncement(item),
            ),
          );
        }
        return RepaintBoundary(
          key: ValueKey('subj_ann_b_${item.id}'),
          child: TelegramAnnouncementCard(
            key: ValueKey('subj_ann_${item.id}'),
            announcement: item,
            currentUser: _user,
            onReactionToggled: (emoji) => _toggleReaction(item, emoji),
            onDelete: () => _confirmDeleteAnnouncement(item),
          ),
        );
      },
    );
  }

  Future<void> _toggleReaction(AnnouncementModel item, String emoji) async {
    if (_user == null) return;

    final currentKey = _user!.studentId.isNotEmpty ? _user!.studentId : _user!.id;
    final reactionsMap = Map<String, AnnouncementReaction>.from(item.reactions);

    if (reactionsMap.containsKey(currentKey) && reactionsMap[currentKey]!.reaction == emoji) {
      reactionsMap.remove(currentKey);
    } else {
      reactionsMap[currentKey] = AnnouncementReaction(
        studentId: currentKey,
        studentName: _user!.name,
        department: _user!.department,
        stage: _user!.stage,
        section: _user!.section ?? '',
        reaction: emoji,
        createdAt: DateTime.now(),
      );
    }

    final updated = item.copyWithReactions(reactionsMap);
    setState(() {
      final idx = _subjectAnnouncements.indexWhere((a) => a.id == item.id);
      if (idx != -1) {
        _subjectAnnouncements[idx] = updated;
      }
    });

    final synced = await SupabaseService().toggleAnnouncementReaction(
      announcementId: item.id,
      emoji: emoji,
      user: _user!,
    );
    if (synced != null && mounted) {
      setState(() {
        final idx = _subjectAnnouncements.indexWhere((a) => a.id == item.id);
        if (idx != -1) {
          _subjectAnnouncements[idx] = synced;
        }
      });
    }
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

  Future<void> _showPublishSheet({String initialMode = 'lecture'}) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PublishToSubjectSheet(
        subjectName: widget.subjectName,
        department: _effectiveDepartment,
        stage: _effectiveStage,
        section: _effectiveSection,
        semester: widget.semester ?? _user?.semester ?? 1,
        currentUser: _user,
        initialMode: initialMode,
        onSuccess: (newAnnounce) {
          if (newAnnounce != null) {
            setState(() {
              if (!_subjectAnnouncements.any((a) => a.id == newAnnounce.id)) {
                _subjectAnnouncements.insert(0, newAnnounce);
              }
            });
          }
          _loadSubjectData(forceRefresh: true, showSpinner: false);
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

  void _openLectureCommentsSheet(LectureModel lecture) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _LectureCommentsSheet(
        lecture: lecture,
        department: _effectiveDepartment,
        stage: _effectiveStage,
        currentUser: _user,
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// نافذة النشر المباشر السلسة من داخل المادة
// ══════════════════════════════════════════════════════════════
class _PublishToSubjectSheet extends StatefulWidget {
  final String subjectName;
  final String department;
  final String stage;
  final String? section;
  final int semester;
  final AppUserModel? currentUser;
  final String initialMode;
  final Function(AnnouncementModel? newAnnounce)? onSuccess;

  const _PublishToSubjectSheet({
    required this.subjectName,
    required this.department,
    required this.stage,
    this.section,
    this.semester = 1,
    required this.currentUser,
    this.initialMode = 'lecture',
    this.onSuccess,
  });

  @override
  State<_PublishToSubjectSheet> createState() => _PublishToSubjectSheetState();
}

class _PublishToSubjectSheetState extends State<_PublishToSubjectSheet> {
  late bool _isLectureMode;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _isLectureMode = widget.initialMode != 'announcement';
    if (widget.section != null && widget.section!.isNotEmpty && widget.section != 'ALL') {
      _targetSection = widget.section!;
    } else if (widget.currentUser?.isAdmin == true) {
      _targetSection = 'ALL';
    } else {
      _targetSection = widget.currentUser?.section ?? 'ALL';
    }
  }

  // حقول المحاضرة
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  String _lectureType = 'theory'; // 'theory', 'practical'
  String _targetSection = 'ALL';
  PlatformFile? _selectedFile;
  int _selectedFileSize = 0;
  bool _isPickingFile = false;

  // حقول التبليغ
  final _announceContentController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
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

    if (_selectedFile == null) {
      _showSnack('يرجى اختيار ملف المحاضرة (PDF / مستند / صورة)', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final res = await TelegramUploaderService().uploadLecture(
        file: _selectedFile!,
        title: title,
        subjectName: widget.subjectName,
        department: widget.department,
        stage: widget.stage,
        section: 'ALL',
        semester: widget.semester,
        lectureType: _lectureType,
        description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
        uploaderId: widget.currentUser?.studentId ?? 'ADMIN',
        uploaderName: widget.currentUser?.name ?? 'ممثل الشعبة',
        uploaderRole: widget.currentUser?.role ?? 'representative',
      );

      if (!res.success) {
        throw Exception(res.message);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم نشر المحاضرة بنجاح')),
        );
        widget.onSuccess?.call(null);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        _showSnack('خطأ أثناء النشر: $e', isError: true);
      }
    }
  }

  Future<void> _submitAnnouncement() async {
    final content = _announceContentController.text.trim();

    if (content.isEmpty) {
      _showSnack('يرجى كتابة نص التبليغ', isError: true);
      return;
    }

    // استخراج عنوان تلقائي لقاعدة البيانات دون الحاجة لإدخاله يدوياً
    final firstLine = content.split('\n').first.trim();
    final autoTitle = firstLine.length > 50
        ? '${firstLine.substring(0, 47)}...'
        : (firstLine.isNotEmpty ? firstLine : (widget.subjectName ?? 'تبليغ أكاديمي'));

    setState(() => _isSubmitting = true);

    try {
      final announceSection = widget.currentUser?.isAdmin == true
          ? _targetSection
          : (widget.currentUser?.section ?? 'ALL');

      final newAnnounce = AnnouncementModel(
        id: '',
        title: autoTitle,
        content: content,
        authorId: widget.currentUser?.studentId ?? 'ADMIN',
        authorName: widget.currentUser?.name ?? 'ممثل الشعبة',
        authorRole: widget.currentUser?.role ?? 'representative',
        department: widget.department,
        stage: widget.stage,
        section: announceSection,
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
        widget.onSuccess?.call(newAnnounce);
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

              // مساحة اختيار ملف المحاضرة (مستند PDF أو صورة أو عرض تقديمي)
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
                    'اختر ملف المحاضرة (PDF / مستند / صورة)',
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
              // نموذج التبليغ المباشر (نمط تيليجرام: نص التبليغ فقط)
              TextField(
                controller: _announceContentController,
                maxLines: 5,
                style: GoogleFonts.cairo(fontSize: 13, color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'نص التبليغ الأكاديمي',
                  hintText: 'اكتب نص التبليغ هنا ليظهر مباشرة للطلاب...',
                  labelStyle: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textSecondary),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  alignLabelWithHint: true,
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(bottom: 70),
                    child: Icon(Icons.campaign_rounded, size: 22, color: AppTheme.primary),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // الشعبة المستهدفة بالتبليغ
              if (widget.currentUser?.isAdmin == true) ...[
                DropdownButtonFormField<String>(
                  value: _targetSection,
                  dropdownColor: Colors.white,
                  style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'الشعبة المستهدفة بالتبليغ',
                    labelStyle: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textSecondary),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.groups_rounded, size: 20, color: AppTheme.accent),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'ALL', child: Text('🌐 جميع الشعب (عام لكافة الطلاب)')),
                    DropdownMenuItem(value: 'A', child: Text('🏷️ شعبة A')),
                    DropdownMenuItem(value: 'B', child: Text('🏷️ شعبة B')),
                    DropdownMenuItem(value: 'C', child: Text('🏷️ شعبة C')),
                    DropdownMenuItem(value: 'D', child: Text('🏷️ شعبة D')),
                    DropdownMenuItem(value: 'E', child: Text('🏷️ شعبة E')),
                    DropdownMenuItem(value: 'F', child: Text('🏷️ شعبة F')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _targetSection = val);
                  },
                ),
                const SizedBox(height: 12),
              ],

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

// ══════════════════════════════════════════════════════════════
// نافذة الاستفسارات والملاحظات الأكاديمية للمحاضرة
// ══════════════════════════════════════════════════════════════
class _LectureCommentsSheet extends StatefulWidget {
  final LectureModel lecture;
  final String department;
  final String stage;
  final AppUserModel? currentUser;

  const _LectureCommentsSheet({
    required this.lecture,
    required this.department,
    required this.stage,
    required this.currentUser,
  });

  @override
  State<_LectureCommentsSheet> createState() => _LectureCommentsSheetState();
}

class _LectureCommentsSheetState extends State<_LectureCommentsSheet> {
  final _commentController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isLoading = true;
  List<LectureCommentModel> _comments = [];
  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    _loadComments();
    _subscribeToRealtime();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    _unsubscribeFromRealtime();
    super.dispose();
  }

  /// ── الاشتراك اللحظي السحابي عبر قناة Supabase Realtime ────────────────
  void _subscribeToRealtime() {
    try {
      final client = Supabase.instance.client;
      final channelName = 'lecture_comments_${widget.lecture.id}_${DateTime.now().microsecondsSinceEpoch}';
      _realtimeChannel = client.channel(channelName);

      _realtimeChannel!.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'announcements',
        callback: (payload) {
          _handleRealtimePayload(payload);
        },
      );

      _realtimeChannel!.subscribe();
      debugPrint('[+] LectureCommentsSheet: Subscribed to live comments channel');
    } catch (e) {
      debugPrint('[-] LectureCommentsSheet realtime subscription error: $e');
    }
  }

  void _unsubscribeFromRealtime() {
    if (_realtimeChannel != null) {
      try {
        Supabase.instance.client.removeChannel(_realtimeChannel!);
        _realtimeChannel = null;
      } catch (e) {
        debugPrint('[-] Error removing realtime comments channel: $e');
      }
    }
  }

  /// ── معالجة أحداث التزامن الحي الواردة من السيرفر لحظياً ────────────────
  void _handleRealtimePayload(PostgresChangePayload payload) {
    if (!mounted) return;

    try {
      if (payload.eventType == PostgresChangeEvent.insert) {
        final record = payload.newRecord;
        final subjectName = record['subject_name']?.toString() ?? '';
        final title = record['title']?.toString() ?? '';
        final content = record['content']?.toString() ?? '';

        final isThisLectureComment = (subjectName == 'LECTURE_NOTE' || content.contains(LectureCommentModel.tag)) &&
            title == widget.lecture.id;

        if (!isThisLectureComment) return;

        final ann = AnnouncementModel.fromJson(record);
        final incoming = LectureCommentModel.fromAnnouncement(ann);
        if (incoming == null) return;

        setState(() {
          // إن كان التعليق موجوداً بالفعل بنفس المعرف السحابي
          final existingIndex = _comments.indexWhere((c) => c.id == incoming.id);
          if (existingIndex != -1) {
            _comments[existingIndex] = incoming;
            return;
          }

          // مطابقة التعليق التفاؤلي المؤقت لنفس الكاتب واستبداله بالمعرف الرسمي
          final optIndex = _comments.indexWhere((c) =>
              c.id.startsWith('temp_') &&
              c.authorId == incoming.authorId &&
              c.content.trim() == incoming.content.trim());

          if (optIndex != -1) {
            _comments[optIndex] = incoming;
          } else {
            // تعليق جديد تماماً قادم من طالب آخر في نفس اللحظة
            _comments.add(incoming);
          }

          _sortComments();
        });

        _scrollToBottom(animated: true);
      } else if (payload.eventType == PostgresChangeEvent.update) {
        final record = payload.newRecord;
        final subjectName = record['subject_name']?.toString() ?? '';
        final title = record['title']?.toString() ?? '';
        final content = record['content']?.toString() ?? '';

        final isThisLectureComment = (subjectName == 'LECTURE_NOTE' || content.contains(LectureCommentModel.tag)) &&
            title == widget.lecture.id;

        if (!isThisLectureComment) return;

        final ann = AnnouncementModel.fromJson(record);
        final updated = LectureCommentModel.fromAnnouncement(ann);
        if (updated == null) return;

        setState(() {
          final idx = _comments.indexWhere((c) => c.id == updated.id);
          if (idx != -1) {
            _comments[idx] = updated;
            _sortComments();
          }
        });
      } else if (payload.eventType == PostgresChangeEvent.delete) {
        final record = payload.oldRecord;
        final deletedId = record['id']?.toString();
        if (deletedId != null && deletedId.isNotEmpty) {
          setState(() {
            _comments.removeWhere((c) => c.id == deletedId);
          });
        }
      }
    } catch (e) {
      debugPrint('[-] Error handling realtime comment change: $e');
    }
  }

  void _sortComments() {
    _comments.sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      return a.createdAt.compareTo(b.createdAt);
    });
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (animated) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutQuad,
        );
      } else {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _loadComments({bool forceRefresh = false}) async {
    final list = await SupabaseService().fetchLectureComments(
      lectureId: widget.lecture.id,
      forceRefresh: forceRefresh,
    );
    if (mounted) {
      setState(() {
        _comments = list;
        _isLoading = false;
      });
      _scrollToBottom(animated: false);
    }
  }

  /// ── إرسال تفاؤلي فوري في 0ms مع حماية كاملة للنص ومزامنة سحابية ─────────
  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || widget.currentUser == null) return;

    final currentStudentId = widget.currentUser!.studentId.isNotEmpty
        ? widget.currentUser!.studentId
        : widget.currentUser!.id;

    // 1. مسح حقل الكتابة فوراً في 0ms لمرونة فائقة
    _commentController.clear();

    // 2. إنشاء نموذج تفاؤلي مؤقت يظهر فوراً في الشاشة
    final tempId = 'temp_${DateTime.now().microsecondsSinceEpoch}';
    final optimisticComment = LectureCommentModel(
      id: tempId,
      lectureId: widget.lecture.id,
      authorId: currentStudentId,
      authorName: widget.currentUser!.name,
      authorRole: widget.currentUser!.role,
      content: text,
      isPinned: false,
      helpfulUserIds: const [],
      createdAt: DateTime.now(),
      section: widget.lecture.section,
    );

    // 3. إدراج فوري في القائمة مع تمرير ناعم
    setState(() {
      _comments.add(optimisticComment);
      _sortComments();
    });
    _scrollToBottom(animated: true);

    // 4. المزامنة في الخلفية دون تجميد واجهة المستخدم
    try {
      final syncedComment = await SupabaseService().addLectureComment(
        lectureId: widget.lecture.id,
        text: text,
        user: widget.currentUser!,
        department: widget.department,
        stage: widget.stage,
        section: widget.lecture.section,
      );

      if (!mounted) return;

      if (syncedComment != null) {
        setState(() {
          final idx = _comments.indexWhere((c) => c.id == tempId);
          if (idx != -1) {
            _comments[idx] = syncedComment;
          }
        });
      } else {
        // في حال فشل الاتصال، التراجع واستعادة النص للكاتب
        setState(() {
          _comments.removeWhere((c) => c.id == tempId);
        });
        _commentController.text = text;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر إرسال التعليق، تم حفظ النص في حقل الكتابة'),
            backgroundColor: AppTheme.danger,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _comments.removeWhere((c) => c.id == tempId);
      });
      _commentController.text = text;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('حدث خطأ في الاتصال، يرجى إعادة المحاولة'),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  /// ── تفاعل لحظي فوري (In-Place 1ms Mutation) بدون وميض أو إعادة تحميل ───
  Future<void> _toggleHelpful(LectureCommentModel comment) async {
    if (widget.currentUser == null) return;
    final studentId = widget.currentUser!.studentId.isNotEmpty
        ? widget.currentUser!.studentId
        : widget.currentUser!.id;

    final currentUsers = List<String>.from(comment.helpfulUserIds);
    final wasHelpful = currentUsers.contains(studentId);
    if (wasHelpful) {
      currentUsers.remove(studentId);
    } else {
      currentUsers.add(studentId);
    }

    // 1. تحديث لحظي محلي في 1ms دون جلب من الشبكة
    final updated = comment.copyWith(helpfulUserIds: currentUsers);
    final idx = _comments.indexWhere((c) => c.id == comment.id);
    if (idx != -1) {
      setState(() {
        _comments[idx] = updated;
      });
    }

    // 2. مزامنة في الخلفية والتراجع في حال الخطأ فقط
    final ok = await SupabaseService().toggleLectureCommentHelpful(
      commentId: comment.id,
      lectureId: widget.lecture.id,
      studentId: studentId,
    );

    if (!ok && mounted) {
      setState(() {
        final revertIdx = _comments.indexWhere((c) => c.id == comment.id);
        if (revertIdx != -1) {
          _comments[revertIdx] = comment;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تسجيل التفاعل')),
      );
    }
  }

  /// ── تثبيت/إلغاء تثبيت لحظي فوري (In-Place 1ms Mutation) ────────────────
  Future<void> _togglePin(LectureCommentModel comment) async {
    if (widget.currentUser == null) return;
    final newPinned = !comment.isPinned;
    final updated = comment.copyWith(isPinned: newPinned);

    // 1. تحديث فوري محلي وإعادة ترتيب
    final idx = _comments.indexWhere((c) => c.id == comment.id);
    if (idx != -1) {
      setState(() {
        _comments[idx] = updated;
        _sortComments();
      });
    }

    // 2. مزامنة في الخلفية
    final ok = await SupabaseService().toggleLectureCommentPin(
      commentId: comment.id,
      lectureId: widget.lecture.id,
      isPinned: newPinned,
      user: widget.currentUser!,
    );

    if (!ok && mounted) {
      setState(() {
        final revertIdx = _comments.indexWhere((c) => c.id == comment.id);
        if (revertIdx != -1) {
          _comments[revertIdx] = comment;
          _sortComments();
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحديث تثبيت الملاحظة')),
      );
    }
  }

  /// ── حذف استفسار مع إزالة فورية من الواجهة ────────────────────────────
  Future<void> _deleteComment(LectureCommentModel comment) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('حذف الاستفسار', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14)),
        content: Text('هل تريد بالتأكيد حذف هذا الاستفسار؟', style: GoogleFonts.cairo(fontSize: 12)),
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
      final originalList = List<LectureCommentModel>.from(_comments);
      setState(() {
        _comments.removeWhere((c) => c.id == comment.id);
      });

      final ok = await SupabaseService().deleteLectureComment(
        commentId: comment.id,
        lectureId: widget.lecture.id,
      );

      if (!ok && mounted) {
        setState(() {
          _comments = originalList;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر حذف الاستفسار')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final currentStudentId = widget.currentUser?.studentId ?? widget.currentUser?.id ?? '';
    final canModerate = widget.currentUser?.isAdmin == true ||
        widget.currentUser?.role == AppConstants.roleRepresentative ||
        widget.currentUser?.studentId == 'ST-NUST-001630760-413';

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primarySubtle,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.forum_rounded, color: AppTheme.primary, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'استفسارات المحاضرة',
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        widget.lecture.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.lightBorder),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : _comments.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: const BoxDecoration(
                                  color: AppTheme.primarySubtle,
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(
                                  child: Icon(Icons.mark_chat_unread_outlined, color: AppTheme.primary, size: 28),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'لا توجد استفسارات بعد',
                                style: GoogleFonts.cairo(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'كن أول من يطرح سؤالاً',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.cairo(
                                  fontSize: 11,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _comments.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (ctx, index) {
                          final comment = _comments[index];
                          final isMe = comment.authorId == currentStudentId;
                          final canDelete = isMe || canModerate;
                          final isHelpful = comment.isHelpfulBy(currentStudentId);
                          final isOptimistic = comment.id.startsWith('temp_');

                          return RepaintBoundary(
                            key: ValueKey(comment.id),
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 200),
                              opacity: isOptimistic ? 0.75 : 1.0,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: comment.isPinned
                                      ? const Color(0xFFFEFCE8)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: comment.isPinned
                                        ? const Color(0xFFFACC15)
                                        : AppTheme.lightBorder,
                                    width: comment.isPinned ? 1.4 : 1.0,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.03),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (comment.isPinned) ...[
                                      Row(
                                        children: [
                                          const Icon(Icons.push_pin_rounded, size: 14, color: Color(0xFFCA8A04)),
                                          const SizedBox(width: 4),
                                          Text(
                                            'ملاحظة مثبتة 📌',
                                            style: GoogleFonts.cairo(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.bold,
                                              color: const Color(0xFFCA8A04),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                    ],
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 14,
                                          backgroundColor: comment.isRepresentative
                                              ? AppTheme.accent.withValues(alpha: 0.15)
                                              : AppTheme.primarySubtle,
                                          child: Text(
                                            comment.authorName.isNotEmpty
                                                ? comment.authorName.characters.first
                                                : 'ط',
                                            style: GoogleFonts.cairo(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: comment.isRepresentative
                                                  ? AppTheme.accent
                                                  : AppTheme.primary,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      comment.authorName,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: GoogleFonts.cairo(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.bold,
                                                        color: AppTheme.textPrimary,
                                                      ),
                                                    ),
                                                  ),
                                                  if (comment.isRepresentative) ...[
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                                      decoration: BoxDecoration(
                                                        color: AppTheme.accent.withValues(alpha: 0.15),
                                                        borderRadius: BorderRadius.circular(6),
                                                        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
                                                      ),
                                                      child: Text(
                                                        'الممثل ⭐',
                                                        style: GoogleFonts.cairo(
                                                          fontSize: 9.5,
                                                          fontWeight: FontWeight.bold,
                                                          color: AppTheme.accent,
                                                        ),
                                                      ),
                                                    ),
                                                  ] else if (comment.isAdmin) ...[
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                                      decoration: BoxDecoration(
                                                        color: AppTheme.primarySubtle,
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: Text(
                                                        'إشراف 🛡️',
                                                        style: GoogleFonts.cairo(
                                                          fontSize: 9.5,
                                                          fontWeight: FontWeight.bold,
                                                          color: AppTheme.primary,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              Row(
                                                children: [
                                                  Text(
                                                    '${comment.createdAt.hour}:${comment.createdAt.minute.toString().padLeft(2, '0')}',
                                                    style: GoogleFonts.cairo(
                                                      fontSize: 9.5,
                                                      color: AppTheme.textMuted,
                                                    ),
                                                  ),
                                                  if (isOptimistic) ...[
                                                    const SizedBox(width: 4),
                                                    const Icon(Icons.access_time_rounded, size: 10, color: AppTheme.textMuted),
                                                  ],
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (canModerate)
                                          IconButton(
                                            icon: Icon(
                                              comment.isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                                              size: 16,
                                              color: comment.isPinned ? const Color(0xFFCA8A04) : AppTheme.textMuted,
                                            ),
                                            tooltip: comment.isPinned ? 'إلغاء التثبيت' : 'تثبيت الملاحظة',
                                            onPressed: isOptimistic ? null : () => _togglePin(comment),
                                          ),
                                        if (canDelete)
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppTheme.danger),
                                            tooltip: 'حذف',
                                            onPressed: isOptimistic ? null : () => _deleteComment(comment),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    SelectableText(
                                      comment.displayContent,
                                      style: GoogleFonts.cairo(
                                        fontSize: 12,
                                        color: AppTheme.textPrimary,
                                        height: 1.45,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: AppTactileBounce(
                                        onTap: isOptimistic ? null : () => _toggleHelpful(comment),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: isHelpful
                                                ? AppTheme.primarySubtle
                                                : const Color(0xFFF1F5F9),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: isHelpful
                                                  ? AppTheme.primary.withValues(alpha: 0.3)
                                                  : Colors.transparent,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.thumb_up_alt_rounded,
                                                size: 13,
                                                color: isHelpful ? AppTheme.primary : AppTheme.textMuted,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                comment.helpfulCount > 0
                                                    ? 'مفيد (${comment.helpfulCount})'
                                                    : 'مفيد',
                                                style: GoogleFonts.cairo(
                                                  fontSize: 10,
                                                  fontWeight: isHelpful ? FontWeight.bold : FontWeight.w600,
                                                  color: isHelpful ? AppTheme.primary : AppTheme.textSecondary,
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
                            ),
                          );
                        },
                      ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppTheme.lightBorder)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    minLines: 1,
                    maxLines: 3,
                    style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'اكتب استفسارك...',
                      hintStyle: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textMuted),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(color: AppTheme.lightBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(color: AppTheme.lightBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(color: AppTheme.primary),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AppTactileBounce(
                  onTap: _sendComment,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(
                      color: AppTheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(Icons.send_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
