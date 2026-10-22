import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants/app_constants.dart';
import '../core/constants/biometric_subjects.dart';
import '../core/theme/app_theme.dart';
import '../models/app_user_model.dart';
import '../models/lecture_model.dart';
import '../models/announcement_model.dart';
import '../models/attendance_model.dart';
import '../models/grade_model.dart';
import '../services/app_notification_service.dart';
import '../services/supabase_service.dart';
import '../services/telegram_uploader_service.dart';
import '../services/admin_preview_service.dart';
import '../services/web_file_saver.dart';
import '../widgets/app_media_preview_modal.dart';
import '../widgets/telegram_announcement_card.dart';
import '../widgets/telegram_poll_card.dart';
import '../widgets/create_poll_sheet.dart';
import '../widgets/app_tactile_bounce.dart';
import '../widgets/publish_to_subject_sheet.dart';
import '../widgets/lecture_comments_sheet.dart';

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
    with TickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;

  AppUserModel? _user;
  List<LectureModel> _subjectLectures = [];
  List<AnnouncementModel> _subjectAnnouncements = [];
  List<AttendanceRecordModel> _subjectAttendanceRecords = [];
  SubjectGradeViewData? _subjectGradeData;

  bool get _showGradesTab =>
      _subjectGradeData != null && _subjectGradeData!.config.isPublished;

  void _updateTabControllerIfNeeded() {
    final targetLength = _showGradesTab ? 4 : 3;
    if (_tabController.length != targetLength) {
      final oldIndex = _tabController.index;
      _tabController.dispose();
      _tabController = TabController(
        length: targetLength,
        initialIndex: oldIndex < targetLength ? oldIndex : 0,
        vsync: this,
      );
      _tabController.addListener(() {
        if (mounted) setState(() {});
      });
    }
  }

  String _lectureTypeFilter = 'ALL'; // 'ALL', 'theory', 'practical'
  String _selectedSectionFilter = 'ALL'; // 'ALL', 'A', 'B', 'C', 'D', 'UNIFIED'
  final ValueNotifier<String> _searchQueryNotifier = ValueNotifier<String>('');

  // ── فهرسة مسبقة لعدد المحاضرات لكل شعبة O(1) Lookups ──
  Map<String, int> _lectureSectionCounts = {};

  void _rebuildSectionCounts() {
    final counts = <String, int>{
      'ALL': _subjectLectures.length,
      'A': 0, 'B': 0, 'C': 0, 'D': 0, 'E': 0, 'F': 0, 'UNIFIED': 0,
    };
    for (final l in _subjectLectures) {
      final sec = l.section.toUpperCase();
      if (sec == 'ALL' || sec.isEmpty) {
        counts['UNIFIED'] = (counts['UNIFIED'] ?? 0) + 1;
      } else {
        counts[sec] = (counts[sec] ?? 0) + 1;
      }
    }
    _lectureSectionCounts = counts;
  }

  bool get _isPrivileged =>
      _user?.isAdmin == true ||
      _user?.studentId == 'ST-NUST-001630760-413' ||
      _user?.studentId == 'ST-NUST-001630760-413';

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
        _user!.isRepresentative ||
        _user!.studentId == 'ST-NUST-001630760-413';
  }

  StreamSubscription<AnnouncementModel>? _announcementInsertSub;
  StreamSubscription<AnnouncementModel>? _announcementUpdateSub;

  @override
  void initState() {
    super.initState();
    _selectedSectionFilter = 'ALL';
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
    _searchQueryNotifier.dispose();
    _announcementInsertSub?.cancel();
    _announcementUpdateSub?.cancel();
    super.dispose();
  }

  bool _matchesSubject(String? name) {
    return AppConstants.matchesSubject(
      name,
      widget.subjectName,
      displayName: widget.displayName,
    );
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
      // توحيد جلب المحاضرات لكافة الشعب بنفس القسم والمرحلة
      final allLectures = await service.fetchLectures(
        department: dept,
        stage: stage,
        section: null,
        semester: activeSemester,
        forceRefresh: forceRefresh,
      );
      _subjectLectures = allLectures.where((l) => _matchesSubject(l.subjectName)).toList();
      _rebuildSectionCounts();

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

      // 4. جلب تقسيم الدرجات ودرجة الطالب (تظهر فقط إذا فعّلها الأستاذ من تطبيق الحضور)
      _subjectGradeData = await service.fetchSubjectGradeForStudent(
        studentId: _user?.studentId ?? '',
        subjectName: widget.subjectName,
        displayName: widget.displayName,
        department: dept,
        stage: stage,
        forceRefresh: forceRefresh,
      );
      if (mounted) {
        _updateTabControllerIfNeeded();
      }
    } catch (e) {
      debugPrint('[-] Error loading subject hub: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  List<LectureModel> _getFilteredLectures(String query) {
    final bool isAdmin = _user?.isAdmin == true;
    final cleanQuery = query.trim().toLowerCase();

    return _subjectLectures.where((l) {
      final matchesType =
          _lectureTypeFilter == 'ALL' || l.type == _lectureTypeFilter;

      final bool matchesSection;
      if (_selectedSectionFilter == 'ALL' || _selectedSectionFilter.isEmpty) {
        matchesSection = true;
      } else if (_selectedSectionFilter == 'UNIFIED') {
        matchesSection = (l.section == 'ALL' || l.section.isEmpty);
      } else {
        matchesSection = (l.section.toUpperCase() == _selectedSectionFilter.toUpperCase() || l.section == 'ALL' || l.section.isEmpty);
      }

      final matchesSearch = cleanQuery.isEmpty || l.searchToken.contains(cleanQuery);
      return matchesType && matchesSection && matchesSearch;
    }).toList();
  }

  List<AnnouncementModel> _getFilteredAnnouncements(String query) {
    final bool isAdmin = _user?.isAdmin == true;
    final cleanQuery = query.trim().toLowerCase();

    return _subjectAnnouncements.where((a) {
      final bool matchesSection;
      if (isAdmin) {
        matchesSection = _selectedSectionFilter == 'ALL' ||
            (_selectedSectionFilter == 'UNIFIED'
                ? (a.section == 'ALL' || a.section.isEmpty)
                : (a.section.toUpperCase() == _selectedSectionFilter.toUpperCase() || a.section == 'ALL'));
      } else {
        final bool isAuthor = _user != null && (_user!.studentId == a.authorId);
        matchesSection = isAuthor ||
            a.section == 'ALL' ||
            a.section.isEmpty ||
            (_user != null && _user!.hasSectionAccess(a.section));
      }

      final matchesSearch = cleanQuery.isEmpty || a.searchToken.contains(cleanQuery);
      return matchesSection && matchesSearch;
    }).toList();
  }


  int _countLecturesForSection(String sec) {
    if (_lectureSectionCounts.isEmpty) _rebuildSectionCounts();
    return _lectureSectionCounts[sec.toUpperCase()] ?? 0;
  }

  Future<void> _launchUrlExternal(String? urlString, {required String errorMsg}) async {
    if (urlString == null || urlString.trim().isEmpty) return;
    final clean = urlString.trim();
    try {
      final uri = Uri.parse(clean);
      if (uri.scheme != 'https' && uri.scheme != 'http' && uri.scheme != 'tg') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('بروتوكول الرابط غير آمن')));
        }
        return;
      }
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
    // التحقق أولاً إن كانت المحاضرة مقسمة إلى أجزاء سحابية (ملف كبير > 19MB تم رفعه بنجاح)
    final partsDesc = (lecture.telegramFileId != null && lecture.telegramFileId!.startsWith('telegram:parts:'))
        ? lecture.telegramFileId!
        : (lecture.driveUrl.startsWith('telegram:parts:') ? lecture.driveUrl : null);

    if (partsDesc != null) {
      await _downloadChunkedLecture(lecture, partsDesc, isPreview: !isDownload);
      return;
    }

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

  /// تنزيل أو معاينة المحاضرات الكبيرة المجزأة وتجميعها بسلاسة للطلبة في شاشة تفاصيل المادة
  Future<void> _downloadChunkedLecture(
    LectureModel lecture,
    String partsDescriptor, {
    bool isPreview = false,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final fileName = lecture.fileName ?? '${lecture.title}.pdf';

    double dlProgress = 0.05;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return PopScope(
            canPop: false,
            child: AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isPreview ? Icons.visibility_rounded : Icons.downloading_rounded,
                          color: AppTheme.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isPreview ? 'جاري الفتح...' : 'جاري التحميل...',
                          style: GoogleFonts.cairo(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Text(
                        '${(dlProgress * 100).toInt()}%',
                        style: GoogleFonts.cairo(color: AppTheme.primary, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: dlProgress.clamp(0.0, 1.0),
                      backgroundColor: AppTheme.lightBorder,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    try {
      final bytes = await TelegramUploaderService().downloadChunkedLectureParts(
        partsDescriptor: partsDescriptor,
        onProgress: (status, prog) {
          dlProgress = prog;
        },
      );

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (bytes != null && bytes.isNotEmpty) {
        if (isPreview) {
          if (kIsWeb) {
            final blobUrl = createBlobUrl(bytes, lecture.mimeType);
            if (blobUrl != null) {
              AppMediaPreviewModal.show(
                context: context,
                title: lecture.title,
                url: blobUrl,
                fileName: fileName,
                mimeType: lecture.mimeType,
              );
              return;
            }
          }
          saveFileInBrowser(bytes, fileName);
          messenger.showSnackBar(
            const SnackBar(
              content: Text('تم التحميل بنجاح'),
              backgroundColor: AppTheme.primary,
            ),
          );
        } else {
          if (kIsWeb) {
            saveFileInBrowser(bytes, fileName);
            messenger.showSnackBar(
              const SnackBar(
                content: Text('تم التحميل بنجاح'),
                backgroundColor: AppTheme.primary,
              ),
            );
          } else {
            if (lecture.telegramMessageId != null) {
              final tgUrl = 'https://t.me/c/3875986734/${lecture.telegramMessageId}';
              await launchUrl(Uri.parse(tgUrl), mode: LaunchMode.externalApplication);
            }
          }
        }
      } else {
        throw Exception('تعذر استخراج بيانات المحاضرة');
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text('تعذر تحميل المحاضرة: $e'),
            backgroundColor: AppTheme.danger,
          ),
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
          unselectedLabelColor: const Color(0xFF64748B),
          indicatorColor: AppTheme.primary,
          indicatorWeight: 2.5,
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: AppTheme.lightBorder,
          labelStyle: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12),
          unselectedLabelStyle: GoogleFonts.cairo(fontWeight: FontWeight.w600, fontSize: 12),
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.menu_book_rounded, size: 16),
                  const SizedBox(width: 6),
                  Text('المحاضرات (${_subjectLectures.length})'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.campaign_rounded, size: 16),
                  const SizedBox(width: 6),
                  Text('التبليغات (${_subjectAnnouncements.length})'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.fingerprint_rounded, size: 16),
                  const SizedBox(width: 6),
                  Text('الحضور (${_subjectAttendanceRecords.length})'),
                ],
              ),
            ),
            if (_showGradesTab)
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.workspace_premium_rounded, size: 16),
                    SizedBox(width: 6),
                    Text('الدرجات'),
                  ],
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: (_canPublish && (_tabController.index == 0 || _tabController.index == 1))
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
                if (_showGradesTab) _buildGradesTab(),
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
                  onChanged: (val) => _searchQueryNotifier.value = val,
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
          child: ValueListenableBuilder<String>(
            valueListenable: _searchQueryNotifier,
            builder: (context, query, _) {
              final lectures = _getFilteredLectures(query);
              if (lectures.isEmpty) {
                return Center(
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
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                itemCount: lectures.length,
                addAutomaticKeepAlives: true,
                addRepaintBoundaries: true,
                itemBuilder: (context, index) {
                  final item = lectures[index];
                  return _buildLectureCard(item);
                },
              );
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
    return RepaintBoundary(
      key: ValueKey('lec_b_${lecture.id}'),
      child: Container(
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
          // شريط النشر التفاؤلي اللحظي قيد المزامنة
          if (lecture.id.startsWith('temp_')) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFFFBBF24)),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'جاري رفع المحاضرة والمزامنة السحابية للطلبة... ⚡',
                    style: GoogleFonts.cairo(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFFB45309),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
          // في حال كانت المحاضرة مرفوعة عبر رابط Google Drive أو سحابي خارجي
          if (lecture.hasDriveUrl && !lecture.hasTelegramMedia) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F9D58),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.cloud_done_rounded, size: 18, color: Colors.white),
                    label: Text(
                      'فتح في Google Drive ↗',
                      style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    onPressed: () => _launchLectureMedia(lecture, isDownload: false),
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
    ),
  );
  }

  // ══════════════════════════════════════════════════════════════
  // تبويب 2: تبليغات المادة الأكاديمية
  // ══════════════════════════════════════════════════════════════
  Widget _buildAnnouncementsTab() {
    return ValueListenableBuilder<String>(
      valueListenable: _searchQueryNotifier,
      builder: (context, query, _) {
        final announcements = _getFilteredAnnouncements(query);
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
          addAutomaticKeepAlives: true,
          addRepaintBoundaries: true,
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

  // ══════════════════════════════════════════════════════════════
  // تبويب 4: الدرجات والسعي الفصلي (يظهر فقط عند تفعيله من الأستاذ)
  // ══════════════════════════════════════════════════════════════
  Widget _buildGradesTab() {
    final data = _subjectGradeData;
    if (data == null || !data.config.isPublished) {
      return const SizedBox.shrink();
    }

    final config = data.config;
    final grade = data.studentGrade;
    final columns = config.columns;
    final maxTotal = config.maxTotal;
    final earnedTotal = data.earnedTotal;
    final hasScores = data.hasAnyEnteredScore;
    final ratio = maxTotal > 0 ? (earnedTotal / maxTotal).clamp(0.0, 1.0) : 0.0;

    String formatNum(double v) {
      if (v == v.roundToDouble()) return v.toInt().toString();
      return v.toStringAsFixed(1);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. بطاقة مجموع السعي النهائي
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primary,
                  AppTheme.primary.withValues(alpha: 0.85),
                ],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: 0.22),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.workspace_premium_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'مجموع السعي والدرجات',
                            style: GoogleFonts.cairo(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            widget.displayName ?? widget.subjectName,
                            style: GoogleFonts.cairo(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        hasScores
                            ? '${formatNum(earnedTotal)} / ${formatNum(maxTotal)}'
                            : '- / ${formatNum(maxTotal)}',
                        style: GoogleFonts.cairo(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: hasScores ? ratio : 0.0,
                    minHeight: 8,
                    backgroundColor: Colors.white.withValues(alpha: 0.22),
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // 2. عنوان تفصيل الدرجات حسب تقسيم الأستاذ
          Row(
            children: [
              const Icon(Icons.fact_check_rounded, size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text(
                'تفصيل الدرجات حسب تقسيم أستاذ المادة',
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 3. بطاقات كل خانة من خانات التقسيم
          ...columns.map((col) {
            final scoreVal = grade?.scores[col.id];
            final hasColScore = scoreVal != null;
            final colRatio = (hasColScore && col.maxScore > 0)
                ? (scoreVal / col.maxScore).clamp(0.0, 1.0)
                : 0.0;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.lightBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          col.title,
                          style: GoogleFonts.cairo(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: hasColScore
                              ? AppTheme.primary.withValues(alpha: 0.1)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          hasColScore
                              ? '${formatNum(scoreVal)} / ${formatNum(col.maxScore)}'
                              : 'لم تُرصد (${formatNum(col.maxScore)})',
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: hasColScore ? AppTheme.primary : AppTheme.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: colRatio,
                      minHeight: 5,
                      backgroundColor: const Color(0xFFE2E8F0),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        colRatio >= 0.5 ? AppTheme.primary : AppTheme.warning,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),

          // 4. ملاحظة أستاذ المادة إن وجدت
          if (grade != null && grade.note.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.comment_rounded, color: AppTheme.primary, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ملاحظة أستاذ المادة:',
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          grade.note,
                          style: GoogleFonts.cairo(
                            fontSize: 12.5,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showPublishSheet({String initialMode = 'lecture'}) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PublishToSubjectSheet(
        subjectName: widget.subjectName,
        department: _effectiveDepartment,
        stage: _effectiveStage,
        section: _effectiveSection,
        semester: widget.semester ?? _user?.semester ?? 1,
        currentUser: _user,
        initialMode: initialMode,
        onOptimisticLecture: (optimisticLecture, file, driveUrl) async {
          // 1. إدراج فوري تفاؤلي في قائمة محاضرات المادة (استجابة فورية < 16ms)
          setState(() {
            _subjectLectures.insert(0, optimisticLecture);
            _rebuildSectionCounts();
          });
          HapticFeedback.lightImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم إدراج المحاضرة فورياً، وجاري المزامنة السحابية للطلبة... ⚡'),
              backgroundColor: AppTheme.primary,
              duration: Duration(seconds: 3),
            ),
          );

          // 2. المزامنة في الخلفية بأمان
          try {
            if (file != null) {
              final res = await TelegramUploaderService().uploadLecture(
                file: file,
                title: optimisticLecture.title,
                subjectName: optimisticLecture.subjectName,
                department: optimisticLecture.department,
                stage: optimisticLecture.stage,
                section: optimisticLecture.section,
                semester: optimisticLecture.semester,
                lectureType: optimisticLecture.type,
                description: optimisticLecture.description,
                uploaderId: optimisticLecture.uploaderId,
                uploaderName: optimisticLecture.uploaderName,
                uploaderRole: optimisticLecture.uploaderRole,
              );
              if (!res.success) {
                throw Exception(res.message);
              }
            } else if (driveUrl != null && driveUrl.isNotEmpty) {
              final finalLecture = LectureModel(
                id: '',
                title: optimisticLecture.title,
                subjectName: optimisticLecture.subjectName,
                department: optimisticLecture.department,
                stage: optimisticLecture.stage,
                section: optimisticLecture.section,
                semester: optimisticLecture.semester,
                type: optimisticLecture.type,
                driveUrl: driveUrl,
                description: optimisticLecture.description,
                uploaderId: optimisticLecture.uploaderId,
                uploaderName: optimisticLecture.uploaderName,
                uploaderRole: optimisticLecture.uploaderRole,
                createdAt: DateTime.now(),
              );
              final ok = await SupabaseService().createLecture(finalLecture);
              if (!ok) throw Exception('تعذر حفظ بيانات المحاضرة في السحابة');
            }

            // 3. تأكيد المزامنة وتحديث البيانات بسلاسة
            if (mounted) {
              _loadSubjectData(forceRefresh: true, showSpinner: false);
            }
          } catch (e) {
            debugPrint('[-] Background subject lecture upload error: $e');
            if (mounted) {
              setState(() {
                _subjectLectures.removeWhere((l) => l.id == optimisticLecture.id);
                _rebuildSectionCounts();
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('فشلت مزامنة المحاضرة: $e'), backgroundColor: AppTheme.danger),
              );
            }
          }
        },
        onOptimisticAnnouncement: (optimisticAnnounce, imageFile) async {
          // 1. إدراج فوري تفاؤلي في تبليغات المادة
          setState(() {
            _subjectAnnouncements.insert(0, optimisticAnnounce);
          });
          HapticFeedback.lightImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم النشر بنجاح'),
              backgroundColor: AppTheme.primary,
              duration: Duration(seconds: 2),
            ),
          );

          // 2. المزامنة في الخلفية بأمان
          try {
            String? uploadedImageUrl;
            if (imageFile != null) {
              final uploadRes = await TelegramUploaderService().uploadFileToTelegram(
                file: imageFile,
                caption: '${optimisticAnnounce.title} • ${widget.subjectName}',
                fileType: 'announcement',
              );
              if (uploadRes.success && uploadRes.fileUrl != null) {
                uploadedImageUrl = uploadRes.fileUrl;
              }
            }

            final finalAnnounce = AnnouncementModel(
              id: '',
              title: optimisticAnnounce.title,
              content: optimisticAnnounce.content,
              authorId: optimisticAnnounce.authorId,
              authorName: optimisticAnnounce.authorName,
              authorRole: optimisticAnnounce.authorRole,
              department: optimisticAnnounce.department,
              stage: optimisticAnnounce.stage,
              section: optimisticAnnounce.section,
              category: 'academic',
              imageUrl: uploadedImageUrl,
              subjectName: widget.subjectName,
              createdAt: DateTime.now(),
            );

            final ok = await SupabaseService().createAnnouncement(finalAnnounce);
            if (!ok) throw Exception('تعذر حفظ التبليغ في قاعدة البيانات');

            if (mounted) {
              _loadSubjectData(forceRefresh: true, showSpinner: false);
            }
          } catch (e) {
            debugPrint('[-] Background subject announcement upload error: $e');
            if (mounted) {
              setState(() {
                _subjectAnnouncements.removeWhere((a) => a.id == optimisticAnnounce.id);
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('تعذر إكمال النشر: $e'), backgroundColor: AppTheme.danger),
              );
            }
          }
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
    if (lecture.id.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('جاري مزامنة بيانات المحاضرة، يرجى المحاولة بعد ثوانٍ')),
      );
      _loadSubjectData(forceRefresh: true);
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => LectureCommentsSheet(
        lecture: lecture,
        department: _effectiveDepartment,
        stage: _effectiveStage,
        currentUser: _user ?? SupabaseService().currentUser,
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
