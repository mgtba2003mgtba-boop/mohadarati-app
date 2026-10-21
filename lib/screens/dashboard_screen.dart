import '../models/representative_activity_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants/app_constants.dart';
import '../core/constants/biometric_subjects.dart';
import '../core/theme/app_theme.dart';
import '../models/app_user_model.dart';
import '../models/lecture_model.dart';
import '../models/announcement_model.dart';
import '../models/student_model.dart';
import '../services/supabase_service.dart';
import '../services/telegram_uploader_service.dart';
import '../widgets/app_network_image.dart';
import '../widgets/app_fullscreen_modal.dart';
import '../widgets/app_media_preview_modal.dart';
import '../widgets/create_poll_sheet.dart';
import 'package:file_picker/file_picker.dart';
import '../services/course_customization_service.dart';
import '../widgets/course_customization_sheet.dart';
import '../widgets/app_icon_badge.dart';
import '../widgets/app_tactile_bounce.dart';
import '../widgets/dashboard_banners_panel.dart';
import '../widgets/dashboard_course_management_tab.dart';
import '../widgets/dashboard_reps_directory_tab.dart';



class DashboardScreen extends StatefulWidget {
  final int initialTabIndex;
  const DashboardScreen({super.key, this.initialTabIndex = 0});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  AppUserModel? _currentUser;
  bool _isLoading = false;
  String _uploadStatusMessage = '';
  double? _uploadProgress;

  // ── متحكمات استمارة نشر المحاضرة ──────────────────────────────
  final _lectureTitleController = TextEditingController();
  final _subjectNameController = TextEditingController();
  final _driveUrlController = TextEditingController();
  final _lectureDescController = TextEditingController();
  String _selectedLectureDept = AppConstants.departments.first;
  String _selectedLectureStage = AppConstants.stages.first;
  String _selectedLectureSection = 'ALL';
  int _selectedLectureSemester = 1;
  String _selectedLectureType = 'theory'; // 'theory' | 'practical'

  // ── متحكمات رفع الملف السحابي المباشر ─────────────────────────
  bool _uploadDirectFile = true; // افتراضياً: رفع مباشر من الجهاز
  PlatformFile? _selectedFile;
  int _selectedFileSize = 0;
  bool _isPickingFile = false;

  // ── متحكمات استمارة نشر الإعلان ───────────────────────────────
  final _announcementTitleController = TextEditingController();
  final _announcementContentController = TextEditingController();
  final _announcementSubjectController = TextEditingController();
  String _selectedAnnounceDept = 'ALL';
  String _selectedAnnounceStage = 'ALL';
  String _selectedAnnounceSection = 'ALL';
  String _selectedAnnounceCategory = 'academic';
  bool _isAnnouncePinned = false;
  PlatformFile? _selectedAnnouncementImage;
  int _selectedAnnouncementImageSize = 0;
  bool _isPickingAnnouncementImage = false;

  // ── بوسترات الواجهة المعتمدة للرادار ──
  List<AnnouncementModel> _existingBanners = [];
  bool _isLoadingBanners = false;

  bool get _isMujtaba {
    if (_currentUser == null) return false;
    return _currentUser!.studentId == 'ST-NUST-001630760-413' ||
        _currentUser!.name.contains('مجتبى') ||
        _currentUser!.isAdmin;
  }

  // ── قائمة المستخدمين والترقيات ونشاط الممثلين ────────────────
  List<AppUserModel> _allUsers = [];

  bool _isLoadingDashboard = false;
  List<LectureModel> _allLectures = [];
  List<AnnouncementModel> _allAnnouncements = [];
  List<RepresentativeActivityItem> _activities = [];

  String _activityDeptFilter = 'ALL';
  String _activityStageFilter = 'ALL';
  String _activityTypeFilter = 'ALL';
  String _activitySearchQuery = '';


  int _activityDisplayLimit = 50;
  int _contentDisplayLimit = 50;

  // ── فلاتر مركز إدارة وحذف المحتوى ──
  String _contentFilterType = 'ALL'; // 'ALL', 'lecture', 'announcement', 'banner', 'schedule'
  String _contentDeptFilter = 'ALL';
  String _contentStageFilter = 'ALL';
  String _contentSearchQuery = '';

  int _publishModeIndex = 0; // 0 = محاضرة, 1 = إعلان, 2 = بوستر
  int _moderationSegmentIndex = 0; // 0 = المحتوى والمنشورات, 1 = الطلاب والممثلين

  int _courseAndUserSegmentIndex = 0; // 0 = المقررات, 1 = الطلاب والترقيات
  int _radarAndModerationSegmentIndex = 0; // 0 = رادار النشاط والنبض, 1 = إدارة وحذف المحتوى


  // ── مواد البصمة لقسم ومرحلة وكورس المحاضرة ──
  String? _selectedBiometricSubject;
  bool _isCustomLectureSubject = false;

  // ── مواد البصمة للإعلان ──
  String? _selectedAnnouncementSubject;

  List<String> get _availableLectureSubjects {
    return BiometricSubjects.getSubjectNames(
      department: _selectedLectureDept,
      stage: _selectedLectureStage,
      semester: _selectedLectureSemester,
    );
  }

  List<String> get _availableAnnouncementSubjects {
    if (_selectedAnnounceDept == 'ALL' || _selectedAnnounceStage == 'ALL') {
      return [];
    }
    return BiometricSubjects.getSubjectNames(
      department: _selectedAnnounceDept,
      stage: _selectedAnnounceStage,
    );
  }

  void _syncLectureSubjectSelection() {
    final available = _availableLectureSubjects;
    if (available.isNotEmpty) {
      if (_selectedBiometricSubject == null || !available.contains(_selectedBiometricSubject)) {
        _selectedBiometricSubject = available.first;
        _subjectNameController.text = available.first;
        _isCustomLectureSubject = false;
      }
    } else {
      _selectedBiometricSubject = null;
      _isCustomLectureSubject = true;
    }
  }

  List<AppUserModel> get _representatives => _allUsers
      .where((u) => u.isRepresentative || u.canPublishLectures || u.canPublishAnnouncements)
      .toList();

  @override
  void initState() {
    super.initState();
    _currentUser = SupabaseService().currentUser;
    if (_currentUser != null && !_currentUser!.isAdmin) {
      _selectedLectureDept = _currentUser!.department;
      _selectedLectureStage = _currentUser!.stage;
      _selectedAnnounceDept = _currentUser!.department;
      _selectedAnnounceStage = _currentUser!.stage;
    }

    int initialTab = 0;
    if (widget.initialTabIndex == 1) {
      initialTab = 0;
      _publishModeIndex = 1; // نشر إعلان
    } else if (widget.initialTabIndex == 2) {
      initialTab = 1; // إدارة المقررات والطلاب
      _courseAndUserSegmentIndex = 0;
    } else if (widget.initialTabIndex >= 3) {
      initialTab = 2; // رادار العمليات والمحتوى
    } else {
      initialTab = 0; // استوديو النشر
      _publishModeIndex = 0;
    }

    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: initialTab.clamp(0, 2),
    );

    _syncLectureSubjectSelection();

    _loadDashboardData(forceRefresh: true);
    if (_isMujtaba) {
      _loadBanners();
    }
  }


  @override
  void dispose() {
    _tabController.dispose();
    _lectureTitleController.dispose();
    _subjectNameController.dispose();
    _driveUrlController.dispose();
    _lectureDescController.dispose();
    _announcementTitleController.dispose();
    _announcementContentController.dispose();
    _announcementSubjectController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboardData({bool forceRefresh = false, bool showSpinner = false}) async {
    if (showSpinner || (_allLectures.isEmpty && _allAnnouncements.isEmpty)) {
      setState(() => _isLoadingDashboard = true);
    }
    final service = SupabaseService();
    try {
      final results = await Future.wait([
        service.fetchLectures(forceRefresh: forceRefresh),
        service.fetchAnnouncements(forceRefresh: forceRefresh),
        service.fetchAllUsers(),
      ]);

      _allLectures = results[0] as List<LectureModel>;
      _allAnnouncements = results[1] as List<AnnouncementModel>;
      _allUsers = results[2] as List<AppUserModel>;

      final Map<String, String> userSections = {};
      for (final u in _allUsers) {
        if (u.section != null && u.section!.isNotEmpty) {
          userSections[u.studentId] = u.section!;
        }
      }
      if (_currentUser?.section != null && _currentUser!.section!.isNotEmpty) {
        userSections[_currentUser!.studentId] = _currentUser!.section!;
      }

      final List<RepresentativeActivityItem> items = [];

      for (final l in _allLectures) {
        items.add(RepresentativeActivityItem(
          id: l.id,
          type: 'lecture',
          title: l.title,
          subjectName: l.subjectName,
          department: l.department,
          stage: l.stage,
          section: userSections[l.uploaderId],
          actorName: l.uploaderName,
          actorId: l.uploaderId,
          actorRole: l.uploaderRole,
          createdAt: l.createdAt,
          driveUrl: l.driveUrl,
          streamUrl: l.streamUrl,
        ));
      }

      for (final a in _allAnnouncements) {
        if (a.subjectName == 'BANNER' || a.subjectName == 'SCHEDULE' || a.subjectName == 'COURSE') continue;
        items.add(RepresentativeActivityItem(
          id: a.id,
          type: 'announcement',
          title: a.title,
          subjectName: a.subjectName ?? 'عام',
          department: a.department,
          stage: a.stage,
          section: userSections[a.authorId],
          actorName: a.authorName,
          actorId: a.authorId,
          actorRole: a.authorRole,
          createdAt: a.createdAt,
          content: a.displayContent,
        ));
      }

      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      final banners = _allAnnouncements
          .where((a) => a.imageUrl != null && a.imageUrl!.isNotEmpty && a.subjectName != 'SCHEDULE' && a.subjectName != 'COURSE')
          .toList();

      if (mounted) {
        setState(() {
          _activities = items;
          _existingBanners = banners;
          _isLoadingDashboard = false;
        });
      }
    } catch (e) {
      debugPrint('[-] Error loading dashboard data: $e');
      if (mounted) setState(() => _isLoadingDashboard = false);
    }
  }

  Future<void> _pickLectureFile() async {
    setState(() => _isPickingFile = true);
    final file = await TelegramUploaderService().pickLectureFile();
    if (mounted) {
      if (file != null) {
        final size = await TelegramUploaderService().getFileSize(file);

        setState(() {
          _isPickingFile = false;
          _selectedFile = file;
          _selectedFileSize = size;
          if (_lectureTitleController.text.trim().isEmpty) {
            final nameWithoutExt = file.name.contains('.')
                ? file.name.substring(0, file.name.lastIndexOf('.'))
                : file.name;
            _lectureTitleController.text = nameWithoutExt;
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

  // ── نشر محاضرة (عبر رفع مباشر إلى سحابة الكلية أو رابط درايف) ──
  Future<void> _submitLecture() async {
    final title = _lectureTitleController.text.trim();
    final subject = _subjectNameController.text.trim();

    if (title.isEmpty) {
      _showSnackbar('يرجى كتابة عنوان المحاضرة', isError: true);
      return;
    }
    if (subject.isEmpty) {
      _showSnackbar('يرجى تحديد اسم المادة الدراسية', isError: true);
      return;
    }

    final targetDept = _currentUser?.isAdmin == true ? _selectedLectureDept : (_currentUser?.department ?? _selectedLectureDept);
    final targetStage = _currentUser?.isAdmin == true ? _selectedLectureStage : (_currentUser?.stage ?? _selectedLectureStage);
    final targetSection = _currentUser?.isAdmin == true
        ? _selectedLectureSection
        : (_currentUser?.assignedSections.isNotEmpty == true && _currentUser!.assignedSections.contains(_selectedLectureSection)
            ? _selectedLectureSection
            : (_currentUser?.section ?? 'ALL'));

    if (!_uploadDirectFile) {
      // ── وضع رابط Google Drive / السحابة الخارجية ──
      final driveUrl = _driveUrlController.text.trim();
      if (driveUrl.isEmpty) {
        _showSnackbar('يرجى إدخال رابط Google Drive أو الرابط السحابي للمحاضرة', isError: true);
        return;
      }
      final parsedUri = Uri.tryParse(driveUrl);
      if (parsedUri == null || !parsedUri.hasScheme || (!driveUrl.startsWith('https://') && !driveUrl.startsWith('http://'))) {
        _showSnackbar('يرجى إدخال رابط ويب صالح يبدأ بـ https://', isError: true);
        return;
      }

      setState(() => _isLoading = true);
      try {
        final newLecture = LectureModel(
          id: '',
          title: title,
          subjectName: subject,
          department: targetDept,
          stage: targetStage,
          section: targetSection,
          semester: _selectedLectureSemester,
          type: _selectedLectureType,
          driveUrl: driveUrl,
          description: _lectureDescController.text.trim().isNotEmpty ? _lectureDescController.text.trim() : null,
          uploaderId: _currentUser?.studentId ?? 'NUST_ADMIN',
          uploaderName: _currentUser?.name ?? 'ممثل الشعبة',
          uploaderRole: _currentUser?.role ?? 'representative',
          createdAt: DateTime.now(),
        );

        final ok = await SupabaseService().createLecture(newLecture);
        if (!ok) throw Exception('تعذر حفظ بيانات المحاضرة في السحابة');

        if (mounted) {
          _lectureTitleController.clear();
          _subjectNameController.clear();
          _driveUrlController.clear();
          _lectureDescController.clear();
          setState(() {
            _allLectures.insert(0, newLecture);
          });
          _showSnackbar('تم حفظ ونشر رابط المحاضرة بنجاح');
          _loadDashboardData(forceRefresh: true, showSpinner: false);
        }
      } catch (e) {
        if (mounted) {
          _showSnackbar('خطأ أثناء النشر: $e', isError: true);
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
      return;
    }

    // ── وضع رفع الملف المباشر عبر تيليجرام ──
    if (_selectedFile == null) {
      _showSnackbar('يرجى اختيار ملف المحاضرة أولاً (PDF / مستند / صورة)', isError: true);
      return;
    }



    setState(() {
      _isLoading = true;
      _uploadStatusMessage = 'جاري الرفع...';
      _uploadProgress = 0.1;
    });

    final result = await TelegramUploaderService().uploadLecture(
      file: _selectedFile!,
      title: title,
      subjectName: subject,
      department: targetDept,
      stage: targetStage,
      section: targetSection,
      semester: _selectedLectureSemester,
      lectureType: _selectedLectureType,
      description: _lectureDescController.text.trim().isNotEmpty ? _lectureDescController.text.trim() : null,
      uploaderId: _currentUser?.studentId ?? 'NUST_ADMIN',
      uploaderName: _currentUser?.name ?? 'ممثل الشعبة',
      uploaderRole: _currentUser?.role ?? 'representative',
      onProgress: (status, progress) {
        if (mounted) {
          setState(() {
            _uploadStatusMessage = status;
            _uploadProgress = progress;
          });
        }
      },
    );

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _uploadStatusMessage = '';
      _uploadProgress = null;
    });

    if (result.success) {
      final newLec = LectureModel(
        id: result.fileId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        subjectName: subject,
        department: targetDept,
        stage: targetStage,
        section: targetSection,
        semester: _selectedLectureSemester,
        type: _selectedLectureType,
        driveUrl: '',
        telegramFileId: result.fileId,
        fileName: _selectedFile?.name,
        fileSizeBytes: _selectedFileSize > 0 ? _selectedFileSize : null,
        description: _lectureDescController.text.trim().isNotEmpty ? _lectureDescController.text.trim() : null,
        uploaderId: _currentUser?.studentId ?? 'NUST_ADMIN',
        uploaderName: _currentUser?.name ?? 'ممثل الشعبة',
        uploaderRole: _currentUser?.role ?? 'representative',
        createdAt: DateTime.now(),
      );
      setState(() {
        _selectedFile = null;
        _allLectures.insert(0, newLec);
      });
      _lectureTitleController.clear();
      _subjectNameController.clear();
      _driveUrlController.clear();
      _lectureDescController.clear();
      _showSnackbar('تم رفع ونشر المحاضرة بنجاح');
      _loadDashboardData(forceRefresh: true, showSpinner: false);
    } else {
      _showSnackbar('${result.message}. يمكنك استخدام خيار "رابط سحابي / Drive" كبديل مباشر.', isError: true);
    }
  }

  Future<void> _pickAnnouncementImage() async {
    setState(() => _isPickingAnnouncementImage = true);
    final file = await TelegramUploaderService().pickImageOnly();
    if (mounted) {
      if (file != null) {
        final size = await TelegramUploaderService().getFileSize(file);
        setState(() {
          _isPickingAnnouncementImage = false;
          _selectedAnnouncementImage = file;
          _selectedAnnouncementImageSize = size;
        });
      } else {
        setState(() => _isPickingAnnouncementImage = false);
      }
    }
  }

  // ── نشر إعلان أكاديمي ──────────────────────────────────────────
  Future<void> _submitAnnouncement() async {
    final content = _announcementContentController.text.trim();
    final subject = _announcementSubjectController.text.trim();

    if (content.isEmpty && _selectedAnnouncementImage == null) {
      _showSnackbar('يرجى كتابة نص التبليغ أو إرفاق صورة الإعلان', isError: true);
      return;
    }

    // استخراج عنوان تلقائي لقاعدة البيانات دون الحاجة لإدخاله يدوياً
    final firstLine = content.isNotEmpty ? content.split('\n').first.trim() : '';
    final autoTitle = firstLine.length > 50
        ? '${firstLine.substring(0, 47)}...'
        : (firstLine.isNotEmpty ? firstLine : (subject.isNotEmpty ? subject : 'تبليغ أكاديمي'));

    final targetDept = _currentUser?.isAdmin == true ? _selectedAnnounceDept : (_currentUser?.department ?? _selectedAnnounceDept);
    final targetStage = _currentUser?.isAdmin == true ? _selectedAnnounceStage : (_currentUser?.stage ?? _selectedAnnounceStage);
    final targetSection = _currentUser?.isAdmin == true ? _selectedAnnounceSection : (_currentUser?.section ?? 'ALL');

    setState(() => _isLoading = true);

    String? uploadedImageUrl;
    if (_selectedAnnouncementImage != null) {
      final uploadRes = await TelegramUploaderService().uploadFileToTelegram(
        file: _selectedAnnouncementImage!,
        caption: '$autoTitle${subject.isNotEmpty ? " • $subject" : ""}',
        fileType: 'announcement',
      );

      if (!uploadRes.success || uploadRes.fileUrl == null) {
        if (mounted) {
          setState(() => _isLoading = false);
          _showSnackbar(uploadRes.message.isNotEmpty ? uploadRes.message : 'فشل الرفع', isError: true);
        }
        return;
      }
      uploadedImageUrl = uploadRes.fileUrl;
    }

    final newAnnounce = AnnouncementModel(
      id: '',
      title: autoTitle,
      content: content,
      authorId: _currentUser?.studentId ?? 'ADMIN_NUST',
      authorName: _currentUser?.name ?? 'إدارة الكلية',
      authorRole: _currentUser?.role ?? 'admin',
      department: targetDept,
      stage: targetStage,
      section: targetSection,
      category: _selectedAnnounceCategory,
      subjectName: subject.isNotEmpty ? subject : null,
      isPinned: _isAnnouncePinned,
      imageUrl: uploadedImageUrl,
      createdAt: DateTime.now(),
    );

    final success = await SupabaseService().createAnnouncement(newAnnounce);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      _announcementTitleController.clear();
      _announcementContentController.clear();
      _announcementSubjectController.clear();
      setState(() {
        _isAnnouncePinned = false;
        _selectedAnnouncementImage = null;
        _selectedAnnouncementImageSize = 0;
        _allAnnouncements.insert(0, newAnnounce);
      });
      _showSnackbar('تم نشر الإعلان بنجاح');
      _loadDashboardData(forceRefresh: true, showSpinner: false);
    } else {
      _showSnackbar('حدث خطأ أثناء نشر الإعلان', isError: true);
    }
  }

  void _showSnackbar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
        backgroundColor: isError ? AppTheme.danger : AppTheme.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isMujtaba) {
      return Scaffold(
        backgroundColor: AppTheme.lightBg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            'لوحة التحكم الإدارية',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.admin_panel_settings_rounded, size: 68, color: AppTheme.warning),
                ),
                const SizedBox(height: 22),
                Text(
                  'صلاحية إدارية حصرية',
                  style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 10),
                Text(
                  'لوحة التحكم مخصصة حصرياً للمشرف العام للمنظومة (مجتبى عواد).\nكممثل للشعبة، يمكنك رفع المحاضرات ونشر التبليغات مباشرة من صفحة المادة داخل التطبيق.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(fontSize: 13, color: AppTheme.textSecondary, height: 1.6),
                ),
                const SizedBox(height: 28),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: Text('العودة للمنصة', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.lightBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.shield_rounded, color: AppTheme.primary, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'مركز القيادة الأكاديمي',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textPrimary),
                  ),
                  Text(
                    'المشرف العام (مجتبى عواد)',
                    style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary),
            tooltip: 'تحديث البيانات فورياً',
            onPressed: () {
              _loadDashboardData(forceRefresh: true, showSpinner: true);
              _loadBanners(forceRefresh: true);
            },
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textSecondary,
          indicatorColor: AppTheme.primary,
          indicatorWeight: 3,
          labelStyle: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12.5),
          tabs: const [
            Tab(icon: Icon(Icons.cloud_upload_rounded), text: 'استوديو النشر'),
            Tab(icon: Icon(Icons.manage_accounts_rounded), text: 'المقررات والطلاب'),
            Tab(icon: Icon(Icons.radar_rounded), text: 'رادار العمليات'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildUnifiedPublishTab(),
          _buildCourseAndDirectoryTab(),
          _buildRadarAndModerationTab(),
        ],
      ),
    );
  }

  // ── زر الشريحة الموحد (Modern Segmented Pill Button) ────────────────
  Widget _buildPillSegmentButton({
    required int selectedIndex,
    required int index,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final isSelected = selectedIndex == index;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected ? AppShadows.card : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.cairo(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── تبويب 1: استوديو النشر السحابي (محاضرات، إعلانات، بوسترات) للمشرف العام ──────────
  Widget _buildUnifiedPublishTab() {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppTheme.lightSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.lightBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildPillSegmentButton(
                  selectedIndex: _publishModeIndex,
                  index: 0,
                  icon: Icons.upload_file_rounded,
                  label: 'رفع محاضرة',
                  onTap: () => setState(() => _publishModeIndex = 0),
                ),
              ),
              Expanded(
                child: _buildPillSegmentButton(
                  selectedIndex: _publishModeIndex,
                  index: 1,
                  icon: Icons.campaign_rounded,
                  label: 'نشر إعلان',
                  onTap: () => setState(() => _publishModeIndex = 1),
                ),
              ),
              Expanded(
                child: _buildPillSegmentButton(
                  selectedIndex: _publishModeIndex,
                  index: 2,
                  icon: Icons.photo_library_rounded,
                  label: 'بوستر الواجهة',
                  onTap: () => setState(() => _publishModeIndex = 2),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _publishModeIndex == 0
              ? _buildPublishLectureTab()
              : _publishModeIndex == 1
                  ? _buildPublishAnnouncementTab()
                  : DashboardBannersPanel(
                      currentUser: _currentUser,
                      onShowSnackbar: _showSnackbar,
                      onBannerChanged: () => _loadBanners(forceRefresh: true),
                    ),
        ),
      ],
    );
  }

  // ── تبويب 2: إدارة المقررات والطلاب (المقررات + دليل الطلاب والترقيات) ──────────
  Widget _buildCourseAndDirectoryTab() {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppTheme.lightSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.lightBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildPillSegmentButton(
                  selectedIndex: _courseAndUserSegmentIndex,
                  index: 0,
                  icon: Icons.menu_book_rounded,
                  label: 'تخصيص وإخفاء المقررات',
                  onTap: () => setState(() => _courseAndUserSegmentIndex = 0),
                ),
              ),
              Expanded(
                child: _buildPillSegmentButton(
                  selectedIndex: _courseAndUserSegmentIndex,
                  index: 1,
                  icon: Icons.people_alt_rounded,
                  label: 'دليل الطلاب والترقيات',
                  onTap: () => setState(() => _courseAndUserSegmentIndex = 1),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _courseAndUserSegmentIndex == 0
              ? DashboardCourseManagementTab(
                  currentUser: _currentUser,
                  onCourseChanged: () => setState(() {}),
                )
              : DashboardRepsDirectoryTab(
                  allUsers: _allUsers,
                  allLectures: _allLectures,
                  allAnnouncements: _allAnnouncements,
                  currentUser: _currentUser,
                  onUsersUpdated: () => _loadDashboardData(forceRefresh: true),
                  onShowSnackbar: _showSnackbar,
                ),
        ),
      ],
    );
  }

  // ── تبويب 3: رادار العمليات والنشاط (الرادار + إدارة وحذف المحتوى) ──────────
  Widget _buildRadarAndModerationTab() {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppTheme.lightSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.lightBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildPillSegmentButton(
                  selectedIndex: _radarAndModerationSegmentIndex,
                  index: 0,
                  icon: Icons.analytics_rounded,
                  label: 'رادار النشاط والنبض',
                  onTap: () => setState(() => _radarAndModerationSegmentIndex = 0),
                ),
              ),
              Expanded(
                child: _buildPillSegmentButton(
                  selectedIndex: _radarAndModerationSegmentIndex,
                  index: 1,
                  icon: Icons.auto_stories_rounded,
                  label: 'إدارة وحذف المحتوى',
                  onTap: () => setState(() => _radarAndModerationSegmentIndex = 1),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _radarAndModerationSegmentIndex == 0
              ? _buildActivityRadarTab()
              : _buildContentManagementTab(),
        ),
      ],
    );
  }

  // ── تبويب 1: نشر المحاضرات (رفع مباشر من الجهاز إلى سحابة تيليجرام) ─
  Widget _buildPublishLectureTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── بطاقة الإرشادات والتعريف بالسحابة ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primary.withValues(alpha: 0.2),
                  AppTheme.accent.withValues(alpha: 0.1),
                ],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.cloud_done_rounded, color: AppTheme.accent, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'منظومة النشر السحابي المباشر (NUST Cloud CDN)',
                        style: GoogleFonts.cairo(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'يمكنك رفع ملفات ومستندات المحاضرات (PDF، صور، عروض تقديمية) مباشرة من جهازك، وسيتم تخزينها وبثها للطلبة فوراً داخل التطبيق دون أي تحويل لخارج المنظومة.',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          color: const Color(0xFFCBD5E1),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // ── التبديل بين رفع ملف مباشر ورابط سحابي / Drive ──
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _uploadDirectFile ? AppTheme.primary.withValues(alpha: 0.15) : Colors.transparent,
                    side: BorderSide(color: _uploadDirectFile ? AppTheme.primary : Colors.grey.shade300, width: _uploadDirectFile ? 1.5 : 1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => setState(() => _uploadDirectFile = true),
                  icon: Icon(Icons.attach_file_rounded, size: 18, color: _uploadDirectFile ? AppTheme.primary : AppTheme.textSecondary),
                  label: Text(
                    'ملف مباشر من الجهاز',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _uploadDirectFile ? AppTheme.primary : AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: !_uploadDirectFile ? AppTheme.accent.withValues(alpha: 0.15) : Colors.transparent,
                    side: BorderSide(color: !_uploadDirectFile ? AppTheme.accent : Colors.grey.shade300, width: !_uploadDirectFile ? 1.5 : 1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => setState(() => _uploadDirectFile = false),
                  icon: Icon(Icons.link_rounded, size: 18, color: !_uploadDirectFile ? AppTheme.accent : AppTheme.textSecondary),
                  label: Text(
                    'رابط سحابي / Drive',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: !_uploadDirectFile ? AppTheme.accent : AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (!_uploadDirectFile) ...[
            TextField(
              controller: _driveUrlController,
              style: GoogleFonts.cairo(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'رابط Google Drive أو الرابط السحابي للمحاضرة',
                hintText: 'https://drive.google.com/file/d/... أو أي رابط ويب سحابي',
                prefixIcon: Icon(Icons.cloud_done_rounded, color: AppTheme.accent),
                helperText: 'يدعم الفيديوهات والملفات الكبيرة ومصادر المحاضرات الخارجية بكل سهولة وبدون قيود حجم',
              ),
            ),
          ] else ...[
            // ── مساحة اختيار أو عرض الملف المختار ──
            if (_selectedFile == null)
              InkWell(
                onTap: _isPickingFile ? null : _pickLectureFile,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.primaryLight.withValues(alpha: 0.4),
                      style: BorderStyle.solid,
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: _isPickingFile
                            ? const SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.primaryLight),
                              )
                            : const Icon(Icons.cloud_upload_outlined, color: AppTheme.primaryLight, size: 36),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'اضغط هنا لاختيار ملف المحاضرة من جهازك',
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'يدعم ملفات المستندات (PDF, Word, PowerPoint) والصور التوضيحية',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton.icon(
                        onPressed: _isPickingFile ? null : _pickLectureFile,
                        icon: const Icon(Icons.folder_open_rounded, size: 18),
                        label: const Text('تصفح الملفات'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.success.withValues(alpha: 0.5), width: 1.5),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.description_rounded,
                        color: AppTheme.primaryLight,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedFile!.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.cairo(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'الحجم: ${_formatFileSize(_selectedFileSize)}',
                                  style: GoogleFonts.cairo(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'مستند / ملف دراسي',
                                style: GoogleFonts.cairo(fontSize: 10, color: const Color(0xFF94A3B8)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: AppTheme.danger),
                      tooltip: 'إلغاء الملف',
                      onPressed: () => setState(() => _selectedFile = null),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 18),

          // ── 1. النطاق الأكاديمي (القسم والمرحلة والكورس) ──
          if (_currentUser?.isAdmin == true) ...[
            DropdownButtonFormField<String>(
              value: _selectedLectureDept,
              dropdownColor: Colors.white,
              style: GoogleFonts.cairo(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'القسم الأكاديمي المستهدف',
                prefixIcon: Icon(Icons.domain_rounded, color: AppTheme.primaryLight),
              ),
              items: AppConstants.departments
                  .map((d) => DropdownMenuItem(value: d, child: Text(d, style: GoogleFonts.cairo(color: AppTheme.textPrimary))))
                  .toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _selectedLectureDept = val;
                    _syncLectureSubjectSelection();
                  });
                }
              },
            ),
            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedLectureStage,
                    dropdownColor: Colors.white,
                    style: GoogleFonts.cairo(color: AppTheme.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'المرحلة الدراسية',
                    ),
                    items: AppConstants.stages
                        .map((s) => DropdownMenuItem(value: s, child: Text(s, style: GoogleFonts.cairo(color: AppTheme.textPrimary))))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedLectureStage = val;
                          _syncLectureSubjectSelection();
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.bookmark_added_rounded, color: AppTheme.primaryLight, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'الكورس الأول 📘',
                          style: GoogleFonts.cairo(color: AppTheme.primaryLight, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),

          // ── الشعبة الدراسية المستهدفة بالمحاضرة ──
          if (_currentUser?.isAdmin == true || (_currentUser?.assignedSections.isNotEmpty == true)) ...[
            DropdownButtonFormField<String>(
              value: (_currentUser?.isAdmin == true || _currentUser?.assignedSections.contains(_selectedLectureSection) == true || _selectedLectureSection == 'ALL')
                  ? _selectedLectureSection
                  : (_currentUser?.assignedSections.first ?? 'ALL'),
              dropdownColor: Colors.white,
              style: GoogleFonts.cairo(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'الشعبة المستهدفة لنشر المحاضرة',
                prefixIcon: Icon(Icons.groups_rounded, color: AppTheme.primaryLight),
              ),
              items: [
                const DropdownMenuItem(value: 'ALL', child: Text('🌐 جميع الشعب (عام لكافة الطلاب)')),
                if (_currentUser?.isAdmin == true) ...const [
                  DropdownMenuItem(value: 'A', child: Text('🏷️ شعبة A')),
                  DropdownMenuItem(value: 'B', child: Text('🏷️ شعبة B')),
                  DropdownMenuItem(value: 'C', child: Text('🏷️ شعبة C')),
                  DropdownMenuItem(value: 'D', child: Text('🏷️ شعبة D')),
                  DropdownMenuItem(value: 'E', child: Text('🏷️ شعبة E')),
                  DropdownMenuItem(value: 'F', child: Text('🏷️ شعبة F')),
                ] else if (_currentUser?.assignedSections.isNotEmpty == true) ...[
                  for (final sec in _currentUser!.assignedSections)
                    DropdownMenuItem(value: sec, child: Text('🏷️ شعبة $sec')),
                ],
              ],
              onChanged: (val) {
                if (val != null) setState(() => _selectedLectureSection = val);
              },
            ),
            const SizedBox(height: 14),
          ],

          // ── 2. المادة الدراسية الرسمية من نظام البصمة الجامعي ──
          DropdownButtonFormField<String>(
            value: _isCustomLectureSubject
                ? '__CUSTOM__'
                : (_availableLectureSubjects.contains(_selectedBiometricSubject)
                    ? _selectedBiometricSubject
                    : (_availableLectureSubjects.isNotEmpty ? _availableLectureSubjects.first : null)),
            dropdownColor: Colors.white,
            style: GoogleFonts.cairo(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              labelText: 'المادة الدراسية الرسمية (نظام البصمة - ${_availableLectureSubjects.length} مادة)',
              prefixIcon: const Icon(Icons.school_rounded, color: AppTheme.accent),
              helperText: 'مستخرجة مباشرة ومصنفة حسب القسم والمرحلة والكورس',
              helperStyle: GoogleFonts.cairo(fontSize: 10, color: const Color(0xFF94A3B8)),
            ),
            items: [
              ..._availableLectureSubjects.map((s) => DropdownMenuItem(
                value: s,
                child: Text(
                  s,
                  style: GoogleFonts.cairo(color: AppTheme.textPrimary, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              )),
              DropdownMenuItem(
                value: '__CUSTOM__',
                child: Row(
                  children: [
                    const Icon(Icons.edit_note_rounded, size: 16, color: AppTheme.accent),
                    const SizedBox(width: 6),
                    Text(
                      'مادة أخرى / إدخال يدوي...',
                      style: GoogleFonts.cairo(color: AppTheme.accent, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
            onChanged: (val) {
              if (val == '__CUSTOM__') {
                setState(() {
                  _isCustomLectureSubject = true;
                  _selectedBiometricSubject = null;
                  _subjectNameController.clear();
                });
              } else if (val != null) {
                setState(() {
                  _isCustomLectureSubject = false;
                  _selectedBiometricSubject = val;
                  _subjectNameController.text = val;
                });
              }
            },
          ),
          if (_isCustomLectureSubject || _availableLectureSubjects.isEmpty) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _subjectNameController,
              style: GoogleFonts.cairo(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'أدخل اسم المادة يدوياً...',
                prefixIcon: Icon(Icons.edit_note_rounded, color: AppTheme.accent),
              ),
            ),
          ],
          const SizedBox(height: 14),

          // ── 3. عنوان المحاضرة وأستاذ المادة ──
          TextField(
            controller: _lectureTitleController,
            style: GoogleFonts.cairo(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              labelText: 'عنوان المحاضرة (مثال: المحاضرة 1 - مقدمة عامة)',
              prefixIcon: Icon(Icons.title_rounded, color: AppTheme.primaryLight),
            ),
          ),
          const SizedBox(height: 14),

          // نوع المحاضرة: نظري أو عملي
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Center(child: Text('نظري')),
                  selected: _selectedLectureType == 'theory',
                  onSelected: (selected) {
                    if (selected) setState(() => _selectedLectureType = 'theory');
                  },
                  selectedColor: AppTheme.primary,
                  backgroundColor: Colors.white,
                  labelStyle: GoogleFonts.cairo(color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ChoiceChip(
                  label: const Center(child: Text('عملي ومختبر')),
                  selected: _selectedLectureType == 'practical',
                  onSelected: (selected) {
                    if (selected) setState(() => _selectedLectureType = 'practical');
                  },
                  selectedColor: AppTheme.accent,
                  backgroundColor: Colors.white,
                  labelStyle: GoogleFonts.cairo(
                    color: _selectedLectureType == 'practical' ? Colors.black : Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          TextField(
            controller: _lectureDescController,
            maxLines: 2,
            style: GoogleFonts.cairo(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              labelText: 'ملاحظات وتفاصيل إضافية للطلبة',
              prefixIcon: Icon(Icons.notes_rounded, color: AppTheme.primaryLight),
            ),
          ),
          const SizedBox(height: 24),

          // ── بطاقة تقدم الرفع المباشر عند بدء العملية ──
          if (_isLoading) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryLight),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _uploadStatusMessage.isNotEmpty
                              ? _uploadStatusMessage
                              : 'جاري الرفع...',
                          style: GoogleFonts.cairo(
                            color: AppTheme.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (_uploadProgress != null)
                        Text(
                          '${(_uploadProgress! * 100).toInt()}%',
                          style: GoogleFonts.cairo(
                            color: AppTheme.primaryLight,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                  if (_uploadProgress != null) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: _uploadProgress,
                        backgroundColor: Colors.white10,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryLight),
                        minHeight: 6,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // ── زر النشر والرفع ──
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _submitLecture,
            icon: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : Icon(
                    _uploadDirectFile ? Icons.cloud_upload_rounded : Icons.save_rounded,
                  ),
            label: Text(
              _isLoading
                  ? (_uploadStatusMessage.isNotEmpty ? _uploadStatusMessage : 'جاري الرفع والمزامنة...')
                  : (_uploadDirectFile
                      ? 'رفع ونشر المحاضرة إلى المنظومة'
                      : 'حفظ ونشر المحاضرة إلى البوابة'),
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: _uploadDirectFile ? AppTheme.primary : AppTheme.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 32),
          _buildMyRecentLecturesSection(),
        ],
      ),
    );
  }

  // ── تبويب 2: نشر الإعلانات ───────────────────────────────────
  Widget _buildPublishAnnouncementTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _announcementContentController,
            maxLines: 5,
            style: GoogleFonts.cairo(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              labelText: 'نص التبليغ أو الإعلان الأكاديمي',
              hintText: 'اكتب نص التبليغ هنا ليظهر مباشرة في لوحة التبليغات...',
              alignLabelWithHint: true,
              prefixIcon: Padding(
                padding: EdgeInsets.only(bottom: 70),
                child: Icon(Icons.campaign_rounded, color: AppTheme.primary),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // ── إرفاق صورة أو كتاب رسمي مع التبليغ (اختياري) ──
          if (_selectedAnnouncementImage == null)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: BorderSide(color: AppTheme.accent.withValues(alpha: 0.6), width: 1.2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _isPickingAnnouncementImage
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_photo_alternate_rounded, color: AppTheme.accent),
              label: Text(
                'إرفاق صورة أو كتاب رسمي مع التبليغ (اختياري 📷)',
                style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              onPressed: _isPickingAnnouncementImage ? null : _pickAnnouncementImage,
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.image_rounded, color: AppTheme.accent, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedAnnouncementImage!.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${_formatFileSize(_selectedAnnouncementImageSize)} ',
                          style: GoogleFonts.cairo(fontSize: 10, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18, color: AppTheme.danger),
                    tooltip: 'إلغاء إرفاق الصورة',
                    onPressed: () => setState(() {
                      _selectedAnnouncementImage = null;
                      _selectedAnnouncementImageSize = 0;
                    }),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),

          // ── 1. النطاق الأكاديمي للإعلان ──
          if (_currentUser?.isAdmin == true) ...[
            DropdownButtonFormField<String>(
              value: _selectedAnnounceDept,
              dropdownColor: Colors.white,
              style: GoogleFonts.cairo(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'القسم الموجه له الإعلان',
                prefixIcon: Icon(Icons.domain_rounded, color: AppTheme.primaryLight),
              ),
              items: [
                const DropdownMenuItem(value: 'ALL', child: Text('كافة أقسام الكلية الموحدة')),
                ...AppConstants.departments.map((d) => DropdownMenuItem(value: d, child: Text(d))),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _selectedAnnounceDept = val;
                    _selectedAnnouncementSubject = null;
                    _announcementSubjectController.text = 'عام';
                  });
                }
              },
            ),
            const SizedBox(height: 14),

            DropdownButtonFormField<String>(
              value: _selectedAnnounceStage,
              dropdownColor: Colors.white,
              style: GoogleFonts.cairo(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'المرحلة الدراسية المستهدفة',
              ),
              items: [
                const DropdownMenuItem(value: 'ALL', child: Text('كافة المراحل الدراسية')),
                ...AppConstants.stages.map((s) => DropdownMenuItem(value: s, child: Text(s))),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _selectedAnnounceStage = val;
                    _selectedAnnouncementSubject = null;
                    _announcementSubjectController.text = 'عام';
                  });
                }
              },
            ),
            const SizedBox(height: 14),

            DropdownButtonFormField<String>(
              value: _selectedAnnounceSection,
              dropdownColor: Colors.white,
              style: GoogleFonts.cairo(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'الشعبة المستهدفة لنشر التبليغ',
                prefixIcon: Icon(Icons.groups_rounded, color: AppTheme.primaryLight),
              ),
              items: const [
                DropdownMenuItem(value: 'ALL', child: Text('🌐 جميع الشعب (عام لكافة الطلاب)')),
                DropdownMenuItem(value: 'A', child: Text('🏷️ شعبة A')),
                DropdownMenuItem(value: 'B', child: Text('🏷️ شعبة B')),
                DropdownMenuItem(value: 'C', child: Text('🏷️ شعبة C')),
                DropdownMenuItem(value: 'D', child: Text('🏷️ شعبة D')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _selectedAnnounceSection = val);
              },
            ),
          ],
          const SizedBox(height: 14),

          // ── 2. المادة المرتبطة بالإعلان (نظام البصمة) ──
          DropdownButtonFormField<String>(
            value: _selectedAnnouncementSubject ?? '__GENERAL__',
            dropdownColor: Colors.white,
            style: GoogleFonts.cairo(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              labelText: 'المادة المرتبطة بالإعلان (نظام البصمة)',
              prefixIcon: const Icon(Icons.school_rounded, color: AppTheme.primaryLight),
              helperText: _availableAnnouncementSubjects.isNotEmpty
                  ? 'متاح ${_availableAnnouncementSubjects.length} مادة معتمدة لهذا القسم والمرحلة'
                  : 'حدد قسماً ومرحلة محددة لإظهار مواد البصمة',
              helperStyle: GoogleFonts.cairo(fontSize: 10, color: const Color(0xFF94A3B8)),
            ),
            items: [
              DropdownMenuItem(
                value: '__GENERAL__',
                child: Text('عام (بدون مادة محددة)', style: GoogleFonts.cairo(color: AppTheme.accent, fontWeight: FontWeight.bold)),
              ),
              ..._availableAnnouncementSubjects.map((s) => DropdownMenuItem(
                value: s,
                child: Text(s, style: GoogleFonts.cairo(color: AppTheme.textPrimary, fontSize: 13), overflow: TextOverflow.ellipsis),
              )),
              DropdownMenuItem(
                value: '__CUSTOM__',
                child: Row(
                  children: [
                    const Icon(Icons.edit_note_rounded, size: 16, color: AppTheme.accent),
                    const SizedBox(width: 6),
                    Text('مادة أخرى / إدخال يدوي...', style: GoogleFonts.cairo(color: AppTheme.accent, fontSize: 12)),
                  ],
                ),
              ),
            ],
            onChanged: (val) {
              setState(() {
                if (val == '__GENERAL__' || val == null) {
                  _selectedAnnouncementSubject = null;
                  _announcementSubjectController.text = 'عام';
                } else if (val == '__CUSTOM__') {
                  _selectedAnnouncementSubject = '__CUSTOM__';
                  _announcementSubjectController.clear();
                } else {
                  _selectedAnnouncementSubject = val;
                  _announcementSubjectController.text = val;
                }
              });
            },
          ),
          if (_selectedAnnouncementSubject == '__CUSTOM__') ...[
            const SizedBox(height: 14),
            TextField(
              controller: _announcementSubjectController,
              style: GoogleFonts.cairo(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'أدخل اسم المادة يدوياً...',
                prefixIcon: Icon(Icons.edit_note_rounded, color: AppTheme.accent),
              ),
            ),
          ],
          const SizedBox(height: 14),

          DropdownButtonFormField<String>(
            value: _selectedAnnounceCategory,
            dropdownColor: Colors.white,
            style: GoogleFonts.cairo(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              labelText: 'تصنيف الإعلان',
            ),
            items: AppConstants.announcementCategories.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (val) => setState(() => _selectedAnnounceCategory = val!),
          ),
          const SizedBox(height: 14),

          SwitchListTile(
            title: Text('تثبيت الإعلان في أعلى التطبيق', style: GoogleFonts.cairo(color: AppTheme.textPrimary, fontSize: 13)),
            value: _isAnnouncePinned,
            activeThumbColor: AppTheme.accent,
            contentPadding: EdgeInsets.zero,
            onChanged: (val) => setState(() => _isAnnouncePinned = val),
          ),
          const SizedBox(height: 24),

          ElevatedButton.icon(
            onPressed: _isLoading ? null : _submitAnnouncement,
            icon: const Icon(Icons.send_rounded),
            label: _isLoading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Text('إرسال ونشر الإعلان للطلبة'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _isLoading || _currentUser == null
                ? null
                : () {
                    CreatePollSheet.show(
                      context: context,
                      currentUser: _currentUser!,
                      department: _currentUser!.isAdmin
                          ? (_selectedAnnounceDept == 'ALL' ? AppConstants.departments.first : _selectedAnnounceDept)
                          : _currentUser!.department,
                      stage: _currentUser!.isAdmin
                          ? (_selectedAnnounceStage == 'ALL' ? AppConstants.stages.first : _selectedAnnounceStage)
                          : _currentUser!.stage,
                      section: _currentUser!.isAdmin
                          ? (_selectedAnnounceSection == 'ALL' ? null : _selectedAnnounceSection)
                          : _currentUser!.section,
                      subjectName: _selectedAnnouncementSubject != null &&
                              _selectedAnnouncementSubject != '__GENERAL__' &&
                              _selectedAnnouncementSubject != '__CUSTOM__'
                          ? _selectedAnnouncementSubject
                          : (_announcementSubjectController.text.trim().isNotEmpty
                              ? _announcementSubjectController.text.trim()
                              : null),
                      onSuccess: (_) => _loadDashboardData(forceRefresh: true),
                    );
                  },
            icon: const Icon(Icons.poll_rounded, color: AppTheme.accent),
            label: Text(
              'إنشاء استطلاع رأي وتصويت طلابي 📊',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: AppTheme.accent, fontSize: 13),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppTheme.accent, width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 32),
          _buildMyRecentAnnouncementsSection(),
        ],
      ),
    );
  }

  // ── سجل محاضراتي المنشورة مؤخراً للممثل مع حالة النشر الحية ─────────────
  Widget _buildMyRecentLecturesSection() {
    final myLectures = _allLectures.where((l) {
      if (_isMujtaba) return true;
      if (_currentUser == null) return false;
      return l.uploaderId == _currentUser!.studentId ||
          (l.department == _currentUser!.department &&
              AppConstants.normalizeStage(l.stage) == AppConstants.normalizeStage(_currentUser!.stage) &&
              _currentUser!.hasSectionAccess(l.section));
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryLight.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.history_edu_rounded, color: AppTheme.primaryLight, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _isMujtaba ? 'سجل المحاضرات المرفوعة بالنظام' : 'سجل محاضراتي المرفوعة للشعبة',
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryLight.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${myLectures.length}',
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryLight,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'تظهر هنا المحاضرات التي قمت برفعها وتأكيد وصولها للطلبة فوراً',
                    style: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFF94A3B8)),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: AppTheme.primaryLight, size: 20),
              tooltip: 'تحديث فوري للسجل',
              onPressed: () => _loadDashboardData(forceRefresh: true),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_isLoadingDashboard)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(color: AppTheme.primaryLight, strokeWidth: 2),
            ),
          )
        else if (myLectures.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              children: [
                Icon(Icons.cloud_upload_outlined, size: 36, color: Colors.white.withValues(alpha: 0.3)),
                const SizedBox(height: 8),
                Text(
                  'لم يتم رفع أي محاضرات حتى الآن',
                  style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFFCBD5E1)),
                ),
                const SizedBox(height: 4),
                Text(
                  'بمجرد رفعك لأي محاضرة من النموذج أعلاه ستظهر هنا فوراً مع حالة النشر وزر المعاينة والحذف',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFF94A3B8)),
                ),
              ],
            ),
          )
        else
          ...myLectures.map((l) => RepaintBoundary(key: ValueKey('dash_lec_${l.id}'), child: _buildRecentLectureItemCard(l))),
      ],
    );
  }

  Widget _buildRecentLectureItemCard(LectureModel l) {
    final bool isMyUpload = _currentUser != null && _currentUser!.studentId == l.uploaderId;
    final bool canDelete = _isMujtaba || isMyUpload;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  l.subjectName,
                  style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.accent),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (l.type == 'practical' ? AppTheme.accent : AppTheme.primaryLight).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  l.typeLabel,
                  style: GoogleFonts.cairo(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: l.type == 'practical' ? AppTheme.accent : AppTheme.primaryLight,
                  ),
                ),
              ),
              const Spacer(),
              // حالة النشر المؤكدة
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.success.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      'منشورة للطلبة ✓',
                      style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.success),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l.title,
            style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            '${l.department} • ${l.stage}${l.section.isNotEmpty && l.section != 'ALL' ? ' • شعبة ${l.section}' : ' • كافة الشعب'} • بواسطة: ${l.uploaderName}',
            style: GoogleFonts.cairo(fontSize: 10.5, color: const Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.primaryLight),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.remove_red_eye_rounded, size: 15, color: AppTheme.primaryLight),
                  label: Text(
                    'معاينة المحاضرة',
                    style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.primaryLight, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () {
                    final target = l.streamUrl ?? (l.driveUrl.isNotEmpty && l.driveUrl != 'telegram' ? l.driveUrl : l.downloadUrl);
                    if (target != null && target.isNotEmpty) {
                      AppMediaPreviewModal.show(
                        context: context,
                        title: l.title,
                        subtitle: '${l.subjectName} • ${l.uploaderName}',
                        url: target,
                        fileName: l.fileName ?? l.title,
                      );
                    }
                  },
                ),
              ),
              if (canDelete) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.danger, size: 20),
                  tooltip: 'حذف المحاضرة',
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: Colors.white,
                        title: Text('تأكيد حذف المحاضرة', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textPrimary)),
                        content: Text('هل تريد بالتأكيد حذف "${l.title}" نهائياً من المنظومة؟', style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFFCBD5E1))),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('حذف'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      final ok = await SupabaseService().deleteLecture(l.id);
                      if (ok) {
                        _showSnackbar('تم حذف المحاضرة بنجاح');
                        _loadDashboardData(forceRefresh: true);
                      } else {
                        _showSnackbar('تعذر حذف المحاضرة', isError: true);
                      }
                    }
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── سجل إعلاناتي وتبليغاتي المنشورة مؤخراً للممثل مع حالة النشر الحية ────────
  Widget _buildMyRecentAnnouncementsSection() {
    final myAnnouncements = _allAnnouncements.where((a) {
      if (a.subjectName == 'BANNER' || a.subjectName == 'SCHEDULE' || a.subjectName == 'COURSE') return false;
      if (_isMujtaba) return true;
      if (_currentUser == null) return false;
      return a.authorId == _currentUser!.studentId ||
          (a.department == _currentUser!.department &&
              AppConstants.normalizeStage(a.stage) == AppConstants.normalizeStage(_currentUser!.stage) &&
              _currentUser!.hasSectionAccess(a.section));
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.campaign_rounded, color: AppTheme.accent, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _isMujtaba ? 'سجل الإعلانات والتبليغات بالنظام' : 'سجل تبليغاتي المنشورة',
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${myAnnouncements.length}',
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'تظهر هنا التبليغات المنشورة مع حالة وصولها للطلبة وخيار الحذف',
                    style: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFF94A3B8)),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: AppTheme.accent, size: 20),
              tooltip: 'تحديث فوري للسجل',
              onPressed: () => _loadDashboardData(forceRefresh: true),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_isLoadingDashboard)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(color: AppTheme.accent, strokeWidth: 2),
            ),
          )
        else if (myAnnouncements.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              children: [
                Icon(Icons.campaign_outlined, size: 36, color: Colors.white.withValues(alpha: 0.3)),
                const SizedBox(height: 8),
                Text(
                  'لم يتم نشر أي إعلانات حتى الآن',
                  style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFFCBD5E1)),
                ),
                const SizedBox(height: 4),
                Text(
                  'بمجرد إرسالك لأي إعلان من النموذج أعلاه سيظهر هنا فوراً مع حالة النشر وخيار الحذف',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFF94A3B8)),
                ),
              ],
            ),
          )
        else
          ...myAnnouncements.map((a) => RepaintBoundary(key: ValueKey('dash_ann_${a.id}'), child: _buildRecentAnnouncementItemCard(a))),
      ],
    );
  }

  Widget _buildRecentAnnouncementItemCard(AnnouncementModel a) {
    final bool isMyAuthor = _currentUser != null && _currentUser!.studentId == a.authorId;
    final bool canDelete = _isMujtaba || isMyAuthor;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  a.subjectName ?? 'عام',
                  style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.accent),
                ),
              ),
              if (a.isPinned) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.push_pin_rounded, size: 11, color: AppTheme.primaryLight),
                      const SizedBox(width: 2),
                      Text('مثبت', style: GoogleFonts.cairo(fontSize: 10, color: AppTheme.primaryLight, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
              if (a.isPoll) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.poll_rounded, size: 11, color: Colors.amber),
                      const SizedBox(width: 2),
                      Text('استطلاع', style: GoogleFonts.cairo(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
              const Spacer(),
              // حالة النشر
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.success.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      'منشور للطلبة ✓',
                      style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.success),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            a.title,
            style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            a.displayContent,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFFCBD5E1), height: 1.4),
          ),
          const SizedBox(height: 6),
          Text(
            '${a.department} • ${a.stage}${a.section.isNotEmpty && a.section != 'ALL' ? ' • شعبة ${a.section}' : ' • كافة الشعب'} • بواسطة: ${a.authorName}',
            style: GoogleFonts.cairo(fontSize: 10.5, color: const Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.accent),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.menu_book_rounded, size: 15, color: AppTheme.accent),
                  label: Text(
                    'قراءة التبليغ كاملاً',
                    style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.accent, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: Colors.white,
                        title: Text(a.title, style: GoogleFonts.cairo(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                        content: SingleChildScrollView(
                          child: Text(a.displayContent, style: GoogleFonts.cairo(color: const Color(0xFFCBD5E1), fontSize: 12, height: 1.5)),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
                        ],
                      ),
                    );
                  },
                ),
              ),
              if (canDelete) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.danger, size: 20),
                  tooltip: 'حذف التبليغ',
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: Colors.white,
                        title: Text('تأكيد حذف التبليغ', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textPrimary)),
                        content: Text('هل تريد بالتأكيد حذف "${a.title}" نهائياً من المنظومة؟', style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFFCBD5E1))),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('حذف'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      final ok = await SupabaseService().deleteAnnouncement(a.id);
                      if (ok) {
                        _showSnackbar('تم حذف التبليغ بنجاح');
                        _loadDashboardData(forceRefresh: true);
                      } else {
                        _showSnackbar('تعذر حذف التبليغ', isError: true);
                      }
                    }
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// ودجت موحد لعرض حالة القوائم الفارغة (DRY Empty State Component)
  Widget _buildEmptyStateCard(String message) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: Center(
        child: Text(
          message,
          style: GoogleFonts.cairo(color: const Color(0xFF94A3B8), fontSize: 13),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  /// ودجت موحد لأزرار التوسع التدريجي (DRY Load More Component)
  Widget _buildLoadMoreButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.accent,
            side: const BorderSide(color: AppTheme.accent),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.expand_more_rounded),
          label: Text(
            label,
            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          onPressed: onPressed,
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // تبويب رادار نشاط الممثلين اللحظي وإحصائيات النظام لمجتبى
  // ══════════════════════════════════════════════════════════════
  Widget _buildActivityRadarTab() {
    final filtered = _activities.where((item) {
      final matchDept = _activityDeptFilter == 'ALL' || item.department == _activityDeptFilter;
      final matchStage = _activityStageFilter == 'ALL' ||
          AppConstants.normalizeStage(item.stage) == AppConstants.normalizeStage(_activityStageFilter);
      final matchType = _activityTypeFilter == 'ALL' || item.type == _activityTypeFilter;
      final q = _activitySearchQuery.trim().toLowerCase();
      final matchSearch = q.isEmpty ||
          item.actorName.toLowerCase().contains(q) ||
          item.title.toLowerCase().contains(q) ||
          item.subjectName.toLowerCase().contains(q) ||
          (item.section != null && item.section!.toLowerCase().contains(q));
      return matchDept && matchStage && matchType && matchSearch;
    }).toList();

    return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── لوحة المؤشرات والإحصائيات القيادية الحية للنظام ──
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primary.withValues(alpha: 0.35),
                  AppTheme.accent.withValues(alpha: 0.15),
                ],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppTheme.accent.withValues(alpha: 0.35)),
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
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.analytics_rounded, color: AppTheme.accent, size: 22),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'لوحة المؤشرات والتحليل المباشر',
                              style: GoogleFonts.cairo(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            Text(
                              'إشراف عام: مجتبى عواد • مزامنة حية مع السيرفر',
                              style: GoogleFonts.cairo(fontSize: 10, color: const Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, color: AppTheme.accent, size: 22),
                      tooltip: 'تحديث فوري للبيانات',
                      onPressed: _loadDashboardData,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── بطاقة إجمالي الطلاب الكبرى ──
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.accent.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.groups_rounded, color: AppTheme.accent, size: 30),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'إجمالي الطلاب المسجلين بالمنظومة',
                              style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFFCBD5E1)),
                            ),
                            Row(
                              children: [
                                Text(
                                  '${_allUsers.length}',
                                  style: GoogleFonts.cairo(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'طالب مسجل',
                                  style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.accent, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          setState(() => _moderationSegmentIndex = 1);
                          _tabController.animateTo(2);
                        },
                        child: Text(
                          'عرض الطلاب',
                          style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ── البطاقات الإحصائية المصغرة ──
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricMiniCard(
                        title: 'الطلبة',
                        value: '${_allUsers.where((u) => u.isStudent).length}',
                        icon: Icons.person_rounded,
                        color: AppTheme.primaryLight,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _buildMetricMiniCard(
                        title: 'الممثلون',
                        value: '${_representatives.length}',
                        icon: Icons.badge_rounded,
                        color: AppTheme.accent,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _buildMetricMiniCard(
                        title: 'المحاضرات',
                        value: '${_allLectures.length}',
                        icon: Icons.menu_book_rounded,
                        color: Colors.purpleAccent,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _buildMetricMiniCard(
                        title: 'التبليغات',
                        value: '${_allAnnouncements.where((a) => a.subjectName != 'BANNER' && a.subjectName != 'SCHEDULE' && a.subjectName != 'COURSE').length}',
                        icon: Icons.campaign_rounded,
                        color: Colors.amberAccent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricMiniCard(
                        title: 'البوسترات',
                        value: '${_existingBanners.length}',
                        icon: Icons.photo_library_rounded,
                        color: Colors.pinkAccent,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _buildMetricMiniCard(
                        title: 'الجداول',
                        value: '${_allAnnouncements.where((a) => a.subjectName == 'SCHEDULE' || a.content.contains('[SCHEDULE_TIMETABLE]')).length}',
                        icon: Icons.calendar_month_rounded,
                        color: Colors.tealAccent,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _buildMetricMiniCard(
                        title: 'المشرفون',
                        value: '${_allUsers.where((u) => u.isAdmin).length}',
                        icon: Icons.shield_rounded,
                        color: Colors.cyanAccent,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── بطاقة تفصيل الأقسام الأكاديمية ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.lightBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.account_balance_rounded, color: AppTheme.accent, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'توزيع الطلاب حسب الأقسام العلمية',
                      style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...AppConstants.departments.map((dept) {
                  final deptCount = _allUsers.where((u) => u.department.contains(dept) || dept.contains(u.department)).length;
                  final double pct = _allUsers.isEmpty ? 0.0 : (deptCount / _allUsers.length);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(dept, style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
                            Text(
                              '$deptCount طالب (${(pct * 100).toStringAsFixed(0)}%)',
                              style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.accent, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: pct,
                            backgroundColor: Colors.white10,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              dept.contains('طبية')
                                  ? const Color(0xFF10B981)
                                  : (dept.contains('حاسوب') ? const Color(0xFF3B82F6) : const Color(0xFFF59E0B)),
                            ),
                            minHeight: 6,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── بطاقة تفصيل المراحل الدراسية ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.lightBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.stairs_rounded, color: AppTheme.primaryLight, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'توزيع الطلاب حسب المراحل الدراسية',
                      style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: AppConstants.stages.map((stage) {
                    final stageCount = _allUsers.where((u) =>
                        AppConstants.normalizeStage(u.stage) == AppConstants.normalizeStage(stage)).length;
                    return Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Column(
                          children: [
                            Text(
                              stage.replaceAll('المرحلة ', ''),
                              style: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFF94A3B8), fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$stageCount',
                              style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                            ),
                            Text(
                              'طالب',
                              style: GoogleFonts.cairo(fontSize: 9, color: const Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // ── عنوان رادار نشاط النشر ──
          Row(
            children: [
              const Icon(Icons.radar_rounded, color: AppTheme.accent, size: 20),
              const SizedBox(width: 8),
              Text(
                'رادار نشاط وعمليات النشر المباشرة',
                style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── شريط البحث والفلاتر ──
          TextField(
            style: GoogleFonts.cairo(color: AppTheme.textPrimary, fontSize: 13),
            onChanged: (val) => setState(() => _activitySearchQuery = val),
            decoration: InputDecoration(
              hintText: 'ابحث عن ممثل أو مادة أو عنوان...',
              hintStyle: GoogleFonts.cairo(color: const Color(0xFF64748B), fontSize: 12),
              prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.accent, size: 20),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppTheme.lightBorder),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
          const SizedBox(height: 10),

          // فلاتر النوع
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('جميع النشاطات'),
                  selected: _activityTypeFilter == 'ALL',
                  onSelected: (s) => setState(() => _activityTypeFilter = 'ALL'),
                  selectedColor: AppTheme.accent,
                  labelStyle: GoogleFonts.cairo(
                    color: _activityTypeFilter == 'ALL' ? Colors.black : const Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('محاضرات فقط 📘'),
                  selected: _activityTypeFilter == 'lecture',
                  onSelected: (s) => setState(() => _activityTypeFilter = 'lecture'),
                  selectedColor: AppTheme.accent,
                  labelStyle: GoogleFonts.cairo(
                    color: _activityTypeFilter == 'lecture' ? Colors.black : const Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('تبليغات فقط 📢'),
                  selected: _activityTypeFilter == 'announcement',
                  onSelected: (s) => setState(() => _activityTypeFilter = 'announcement'),
                  selectedColor: AppTheme.accent,
                  labelStyle: GoogleFonts.cairo(
                    color: _activityTypeFilter == 'announcement' ? Colors.black : const Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // فلاتر الأقسام
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('كافة الأقسام'),
                  selected: _activityDeptFilter == 'ALL',
                  onSelected: (s) => setState(() => _activityDeptFilter = 'ALL'),
                  selectedColor: AppTheme.primaryLight,
                  labelStyle: GoogleFonts.cairo(
                    color: _activityDeptFilter == 'ALL' ? Colors.white : const Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ...AppConstants.departments.map((dept) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(dept),
                      selected: _activityDeptFilter == dept,
                      onSelected: (s) => setState(() => _activityDeptFilter = s ? dept : 'ALL'),
                      selectedColor: AppTheme.primaryLight,
                      labelStyle: GoogleFonts.cairo(
                        color: _activityDeptFilter == dept ? Colors.white : const Color(0xFF94A3B8),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── قائمة النشاطات الحية ──
          if (_isLoadingDashboard)
            const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator(color: AppTheme.accent)))
          else if (filtered.isEmpty)
            _buildEmptyStateCard('لا توجد عمليات نشر مسجلة تطابق الفلاتر المحددة')
          else ...[
            ...filtered.take(_activityDisplayLimit).map((item) => _buildActivityCard(item)),
            if (filtered.length > _activityDisplayLimit)
              _buildLoadMoreButton(
                label: 'عرض المزيد (${filtered.length - _activityDisplayLimit} نشاط إضافي)',
                onPressed: () => setState(() => _activityDisplayLimit += 50),
              ),
          ],
        ],
      );
  }

  Widget _buildActivityCard(RepresentativeActivityItem item) {
    final isLecture = item.type == 'lecture';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLecture ? AppTheme.primaryLight.withValues(alpha: 0.3) : AppTheme.accent.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isLecture ? AppTheme.primaryLight.withValues(alpha: 0.15) : AppTheme.accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isLecture ? Icons.menu_book_rounded : Icons.campaign_rounded,
                  color: isLecture ? AppTheme.primaryLight : AppTheme.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.actorName,
                            style: GoogleFonts.cairo(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isLecture ? AppTheme.primaryLight.withValues(alpha: 0.2) : AppTheme.accent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isLecture ? 'محاضرة' : 'تبليغ',
                            style: GoogleFonts.cairo(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: isLecture ? AppTheme.primaryLight : AppTheme.accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item.department} • ${item.stage}${item.section != null ? ' • شعبة ${item.section}' : ''}',
                      style: GoogleFonts.cairo(fontSize: 10.5, color: const Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'مادة: ${item.subjectName}',
                        style: GoogleFonts.cairo(fontSize: 10.5, color: AppTheme.accent, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${item.createdAt.year}/${item.createdAt.month.toString().padLeft(2, '0')}/${item.createdAt.day.toString().padLeft(2, '0')} ${item.createdAt.hour.toString().padLeft(2, '0')}:${item.createdAt.minute.toString().padLeft(2, '0')}',
                      style: GoogleFonts.cairo(fontSize: 10, color: const Color(0xFF64748B)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  item.title,
                  style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                if (item.content != null && item.content!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.content!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFFCBD5E1), height: 1.4),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (item.streamUrl != null || item.driveUrl != null)
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.primaryLight),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.remove_red_eye_rounded, size: 16, color: AppTheme.primaryLight),
                    label: Text('معاينة المحتوى', style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.primaryLight, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      final target = item.streamUrl ?? item.driveUrl;
                      if (target != null && target.isNotEmpty) {
                        AppMediaPreviewModal.show(
                          context: context,
                          title: item.title,
                          subtitle: '${item.subjectName} • ${item.actorName}',
                          url: target,
                          fileName: item.title,
                        );
                      }
                    },
                  ),
                ),
              if (item.type == 'announcement')
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.accent),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.menu_book_rounded, size: 16, color: AppTheme.accent),
                    label: Text('قراءة التبليغ', style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.accent, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: Colors.white,
                          title: Text(item.title, style: GoogleFonts.cairo(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                          content: Text(item.content ?? '', style: GoogleFonts.cairo(color: const Color(0xFFCBD5E1), fontSize: 12)),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.danger, size: 20),
                tooltip: 'حذف المحتوى فورياً',
                onPressed: () => _confirmDeleteActivity(item),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteActivity(RepresentativeActivityItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('تأكيد الحذف الإشرافي', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textPrimary)),
        content: Text('هل تريد بالتأكيد حذف "${item.title}" المنشورة بواسطة ${item.actorName}؟', style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFFCBD5E1))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف فوري'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      bool ok = false;
      if (item.type == 'lecture') {
        ok = await SupabaseService().deleteLecture(item.id);
      } else {
        ok = await SupabaseService().deleteAnnouncement(item.id);
      }
      if (ok) {
        _showSnackbar('تم حذف المحتوى فورياً');
        _loadDashboardData();
      }
    }
  }

  Widget _buildMetricMiniCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.cairo(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          Text(
            title,
            style: GoogleFonts.cairo(
              fontSize: 10,
              color: const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }

  // ── تبويب 3: مركز إدارة وحذف المحتوى المنشور الموحد ───────────────
  Widget _buildContentManagementTab() {
    // تجميع كافة المحتويات المنشورة في نموذج موحد
    final List<Map<String, dynamic>> allItems = [];

    for (final lec in _allLectures) {
      allItems.add({
        'id': lec.id,
        'type': 'lecture',
        'title': lec.title,
        'subjectName': lec.subjectName,
        'department': lec.department,
        'stage': lec.stage,
        'authorName': lec.uploaderName,
        'authorRole': lec.uploaderRole,
        'createdAt': lec.createdAt,
        'fileUrl': lec.streamUrl ?? lec.driveUrl,
        'content': lec.description,
      });
    }

    for (final ann in _allAnnouncements) {
      if (ann.subjectName == 'COURSE') continue; // سجل المقررات داخلي
      String type = 'announcement';
      if (ann.subjectName == 'SCHEDULE' || ann.content.contains('[SCHEDULE_TIMETABLE]')) {
        type = 'schedule';
      } else if (ann.imageUrl != null && ann.imageUrl!.isNotEmpty) {
        type = 'banner';
      }

      allItems.add({
        'id': ann.id,
        'type': type,
        'title': ann.title,
        'subjectName': ann.subjectName ?? 'عام',
        'department': ann.department,
        'stage': ann.stage,
        'authorName': ann.authorName,
        'authorRole': ann.authorRole,
        'createdAt': ann.createdAt,
        'fileUrl': ann.imageUrl,
        'content': ann.content,
      });
    }

    allItems.sort((a, b) => (b['createdAt'] as DateTime).compareTo(a['createdAt'] as DateTime));

    final filtered = allItems.where((item) {
      final type = item['type'] as String;
      if (_contentFilterType != 'ALL' && type != _contentFilterType) return false;

      final dept = item['department'] as String;
      if (_contentDeptFilter != 'ALL' && !dept.contains(_contentDeptFilter) && !_contentDeptFilter.contains(dept)) {
        return false;
      }

      final stage = item['stage'] as String;
      if (_contentStageFilter != 'ALL' && !stage.contains(_contentStageFilter) && !_contentStageFilter.contains(stage)) {
        return false;
      }

      final q = _contentSearchQuery.trim().toLowerCase();
      if (q.isNotEmpty) {
        final title = (item['title'] as String).toLowerCase();
        final subject = (item['subjectName'] as String).toLowerCase();
        final author = (item['authorName'] as String).toLowerCase();
        final content = ((item['content'] as String?) ?? '').toLowerCase();
        if (!title.contains(q) && !subject.contains(q) && !author.contains(q) && !content.contains(q)) {
          return false;
        }
      }

      return true;
    }).toList();

    return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // رأس لوحة إدارة المحتوى
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'مركز إدارة وحذف المحتوى المنشور',
                    style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                  Text(
                    '${filtered.length} عنصر معروض من إجمالي ${allItems.length}',
                    style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.accent),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: AppTheme.accent, size: 22),
                tooltip: 'تحديث فوري',
                onPressed: _loadDashboardData,
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── تصنيف نوع المحتوى ──
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: Text('الكل (${allItems.length})'),
                  selected: _contentFilterType == 'ALL',
                  onSelected: (s) => setState(() => _contentFilterType = 'ALL'),
                  selectedColor: AppTheme.accent,
                  labelStyle: GoogleFonts.cairo(
                    color: _contentFilterType == 'ALL' ? Colors.black : const Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: Text('محاضرات 📘 (${allItems.where((i) => i['type'] == 'lecture').length})'),
                  selected: _contentFilterType == 'lecture',
                  onSelected: (s) => setState(() => _contentFilterType = 'lecture'),
                  selectedColor: AppTheme.accent,
                  labelStyle: GoogleFonts.cairo(
                    color: _contentFilterType == 'lecture' ? Colors.black : const Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: Text('تبليغات 📢 (${allItems.where((i) => i['type'] == 'announcement').length})'),
                  selected: _contentFilterType == 'announcement',
                  onSelected: (s) => setState(() => _contentFilterType = 'announcement'),
                  selectedColor: AppTheme.accent,
                  labelStyle: GoogleFonts.cairo(
                    color: _contentFilterType == 'announcement' ? Colors.black : const Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: Text('بوسترات 🖼️ (${allItems.where((i) => i['type'] == 'banner').length})'),
                  selected: _contentFilterType == 'banner',
                  onSelected: (s) => setState(() => _contentFilterType = 'banner'),
                  selectedColor: AppTheme.accent,
                  labelStyle: GoogleFonts.cairo(
                    color: _contentFilterType == 'banner' ? Colors.black : const Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: Text('جداول 📅 (${allItems.where((i) => i['type'] == 'schedule').length})'),
                  selected: _contentFilterType == 'schedule',
                  onSelected: (s) => setState(() => _contentFilterType = 'schedule'),
                  selectedColor: AppTheme.accent,
                  labelStyle: GoogleFonts.cairo(
                    color: _contentFilterType == 'schedule' ? Colors.black : const Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // شريط البحث في المحتوى
          TextField(
            style: GoogleFonts.cairo(color: AppTheme.textPrimary, fontSize: 13),
            onChanged: (val) => setState(() => _contentSearchQuery = val),
            decoration: InputDecoration(
              hintText: 'ابحث في العنوان، المادة، الناشر، أو المحتوى...',
              hintStyle: GoogleFonts.cairo(color: const Color(0xFF64748B), fontSize: 12),
              prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.accent, size: 20),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppTheme.lightBorder),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
          const SizedBox(height: 10),

          // فلاتر الأقسام
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('كافة الأقسام'),
                  selected: _contentDeptFilter == 'ALL',
                  onSelected: (s) => setState(() => _contentDeptFilter = 'ALL'),
                  selectedColor: AppTheme.primaryLight,
                  labelStyle: GoogleFonts.cairo(
                    color: _contentDeptFilter == 'ALL' ? Colors.white : const Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ...AppConstants.departments.map((dept) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(dept),
                      selected: _contentDeptFilter == dept,
                      onSelected: (s) => setState(() => _contentDeptFilter = s ? dept : 'ALL'),
                      selectedColor: AppTheme.primaryLight,
                      labelStyle: GoogleFonts.cairo(
                        color: _contentDeptFilter == dept ? Colors.white : const Color(0xFF94A3B8),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 14),

          if (filtered.isEmpty)
            _buildEmptyStateCard('لا توجد عناصر منشورة تطابق الفلاتر المحددة')
          else ...[
            ...filtered.take(_contentDisplayLimit).map((item) => _buildUnifiedContentCard(item)),
            if (filtered.length > _contentDisplayLimit)
              _buildLoadMoreButton(
                label: 'عرض المزيد (${filtered.length - _contentDisplayLimit} منشور إضافي)',
                onPressed: () => setState(() => _contentDisplayLimit += 50),
              ),
          ],
        ],
      );
  }

  Widget _buildUnifiedContentCard(Map<String, dynamic> item) {
    final String type = item['type'];
    final String title = item['title'];
    final String subjectName = item['subjectName'];
    final String department = item['department'];
    final String stage = item['stage'];
    final String authorName = item['authorName'];
    final DateTime createdAt = item['createdAt'];
    final String? fileUrl = item['fileUrl'];
    final String? content = item['content'];

    IconData typeIcon = Icons.article_rounded;
    Color typeColor = AppTheme.accent;
    String typeLabel = 'تبليغ';

    if (type == 'lecture') {
      typeIcon = Icons.menu_book_rounded;
      typeColor = const Color(0xFF38BDF8);
      typeLabel = 'محاضرة';
    } else if (type == 'banner') {
      typeIcon = Icons.photo_library_rounded;
      typeColor = const Color(0xFFF43F5E);
      typeLabel = 'بوستر واجهة';
    } else if (type == 'schedule') {
      typeIcon = Icons.calendar_month_rounded;
      typeColor = const Color(0xFF10B981);
      typeLabel = 'جدول دراسي';
    }

    final bool hasImage = fileUrl != null &&
        fileUrl.isNotEmpty &&
        (type == 'banner' || type == 'schedule' || fileUrl.contains('.jpg') || fileUrl.contains('.png') || fileUrl.contains('.webp') || fileUrl.contains('api.telegram.org'));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: typeColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(typeIcon, color: typeColor, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: typeColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: typeColor.withValues(alpha: 0.35)),
                          ),
                          child: Text(
                            typeLabel,
                            style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.bold, color: typeColor),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'مادة: $subjectName • $department ($stage)',
                      style: GoogleFonts.cairo(fontSize: 10.5, color: const Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // في حال وجود صورة مصغرة (بوستر أو جدول)
          if (hasImage) ...[
            GestureDetector(
              onTap: () {
                AppFullscreenModal.show(
                  context: context,
                  title: title,
                  subtitle: '$department • $stage',
                  imageUrl: fileUrl,
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    AppNetworkImage(
                      imageUrl: fileUrl,
                      width: double.infinity,
                      height: 140,
                      fit: BoxFit.cover,
                    ),
                    Container(
                      margin: const EdgeInsets.all(8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.fullscreen_rounded, size: 14, color: Colors.white),
                          const SizedBox(width: 4),
                          Text('اضغط لتكبير الصورة', style: GoogleFonts.cairo(fontSize: 10, color: Colors.white)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ] else if (content != null && content.isNotEmpty && !content.contains('[SCHEDULE_TIMETABLE]')) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFFCBD5E1), height: 1.4),
              ),
            ),
            const SizedBox(height: 10),
          ],

          // تذييل البطاقة مع اسم الناشر والتاريخ وأزرار الإجراء
          Row(
            children: [
              Text(
                'نُشر بواسطة: $authorName • ${createdAt.year}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.day.toString().padLeft(2, '0')}',
                style: GoogleFonts.cairo(fontSize: 10, color: const Color(0xFF64748B)),
              ),
              const Spacer(),
              if (type == 'lecture' && fileUrl != null && fileUrl.isNotEmpty)
                IconButton(
                  tooltip: 'معاينة الملف السحابي',
                  icon: const Icon(Icons.remove_red_eye_rounded, color: AppTheme.primaryLight, size: 20),
                  onPressed: () {
                    AppMediaPreviewModal.show(
                      context: context,
                      title: title,
                      subtitle: '$department • $authorName',
                      url: fileUrl,
                      fileName: title,
                    );
                  },
                ),
              IconButton(
                tooltip: 'حذف المحتوى نهائياً',
                icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.danger, size: 20),
                onPressed: () => _confirmDeleteUnifiedContent(item),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteUnifiedContent(Map<String, dynamic> item) async {
    final String type = item['type'];
    final String id = item['id'];
    final String title = item['title'];
    final String authorName = item['authorName'];

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          'تأكيد حذف المحتوى الإشرافي',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textPrimary),
        ),
        content: Text(
          'هل تريد بالتأكيد حذف "$title" المنشور بواسطة $authorName؟\nسيتم حذفه نهائياً من قاعدة بيانات السيرفر والتطبيق لكافة الطلبة.',
          style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFFCBD5E1), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('إلغاء', style: GoogleFonts.cairo(color: const Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف نهائي'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      bool ok = false;
      if (type == 'lecture') {
        ok = await SupabaseService().deleteLecture(id);
      } else {
        ok = await SupabaseService().deleteAnnouncement(id);
      }

      if (ok) {
        _showSnackbar('تم حذف المحتوى بنجاح');
        _loadDashboardData();
        if (type == 'banner') _loadBanners();
      } else {
        _showSnackbar('تعذر حذف المحتوى، تحقق من الاتصال', isError: true);
      }
    }
  }

  // ── إدارة البوسترات المصورة (خاص بمجتبى عواد عبر سيرفر تيليجرام) ───────────
  Future<void> _loadBanners({bool forceRefresh = false}) async {
    setState(() => _isLoadingBanners = true);
    final all = await SupabaseService().fetchAnnouncements(department: 'ALL', forceRefresh: forceRefresh);
    final banners = all.where((a) =>
      a.imageUrl != null && a.imageUrl!.isNotEmpty &&
      (a.category == 'banner' || a.subjectName == 'BANNER' || a.content.contains('[HOME_BANNER]'))
    ).toList();
    if (mounted) {
      setState(() {
        _existingBanners = banners;
        _isLoadingBanners = false;
      });
    }
  }


}
