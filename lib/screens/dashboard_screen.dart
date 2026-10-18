import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
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
import '../models/course_override_model.dart';
import '../services/course_customization_service.dart';
import '../widgets/course_customization_sheet.dart';
import '../widgets/app_icon_badge.dart';
import '../widgets/app_tactile_bounce.dart';


class RepresentativeActivityItem {
  final String id;
  final String type; // 'lecture' | 'announcement'
  final String title;
  final String subjectName;
  final String department;
  final String stage;
  final String? section;
  final String actorName;
  final String actorId;
  final String actorRole;
  final DateTime createdAt;
  final String? driveUrl;
  final String? streamUrl;
  final String? content;

  RepresentativeActivityItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subjectName,
    required this.department,
    required this.stage,
    this.section,
    required this.actorName,
    required this.actorId,
    required this.actorRole,
    required this.createdAt,
    this.driveUrl,
    this.streamUrl,
    this.content,
  });
}

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

  // ── إدارة شعب نظام البصمة وتكليف الممثلين ─────────────────────
  String _selectedRepDept = AppConstants.departments.first;
  String _selectedRepStage = AppConstants.stages.first;
  String _selectedRepSection = 'A';
  List<String> _availableBiometricSections = ['A', 'B', 'C', 'D'];
  bool _isLoadingSections = false;

    // ── متحكمات بنل البوسترات المصورة (خاص بمجتبى عواد) ──────────────
  final _bannerTitleController = TextEditingController();
  final _bannerContentController = TextEditingController();
  PlatformFile? _selectedBannerImage;
  int _selectedBannerImageSize = 0;
  bool _isPickingBannerImage = false;
  String _selectedBannerDept = 'ALL';
  String _selectedBannerStage = 'ALL';
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

  String _repDeptFilter = 'ALL';
  String _repSearchQuery = '';

  // ── فلاتر دليل الطلاب والممثلين ──
  String _userDirectoryRoleFilter = 'ALL'; // 'ALL', 'REPS', 'STUDENTS'
  String _userDirectoryStageFilter = 'ALL';
  int _directoryDisplayLimit = 50;
  int _activityDisplayLimit = 50;
  int _contentDisplayLimit = 50;

  // ── فلاتر مركز إدارة وحذف المحتوى ──
  String _contentFilterType = 'ALL'; // 'ALL', 'lecture', 'announcement', 'banner', 'schedule'
  String _contentDeptFilter = 'ALL';
  String _contentStageFilter = 'ALL';
  String _contentSearchQuery = '';

  int _publishModeIndex = 0; // 0 = محاضرة, 1 = إعلان, 2 = بوستر
  int _moderationSegmentIndex = 0; // 0 = المحتوى والمنشورات, 1 = الطلاب والممثلين
  // ── إدارة المقررات وتخصيص الأسماء والرموز والإخفاء ──
  String _courseMgmtDept = AppConstants.departments.first;
  String _courseMgmtStage = AppConstants.stages.first;
  int _courseMgmtSemester = 1;
  String _courseMgmtSearchQuery = '';
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
      _courseMgmtDept = _currentUser!.department;
      _courseMgmtStage = _currentUser!.stage;
    }

    final int tabsCount = _isMujtaba ? 3 : 2;
    int initialTab = 0;
    if (_isMujtaba) {
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
    } else {
      initialTab = widget.initialTabIndex.clamp(0, 1);
    }

    _tabController = TabController(
      length: tabsCount,
      vsync: this,
      initialIndex: initialTab,
    );

    _syncLectureSubjectSelection();

    _loadDashboardData(forceRefresh: true);
    if (_isMujtaba) {
      _loadBanners();
      _loadBiometricSections();
    }
  }

  Future<void> _loadBiometricSections() async {
    setState(() => _isLoadingSections = true);
    final list = await SupabaseService().fetchBiometricSections(
      department: _selectedRepDept,
      stage: _selectedRepStage,
    );
    if (mounted) {
      setState(() {
        _availableBiometricSections = list;
        if (!_availableBiometricSections.contains(_selectedRepSection)) {
          _selectedRepSection = _availableBiometricSections.isNotEmpty ? _availableBiometricSections.first : 'A';
        }
        _isLoadingSections = false;
      });
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
    _bannerTitleController.dispose();
    _bannerContentController.dispose();
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
        if (size > 50 * 1024 * 1024) {
          _showSnackbar(
            'تنبيه: حجم الملف المختار (${_formatFileSize(size)}) يتجاوز الحد الأقصى للرفع المباشر (50 ميغابايت). يرجى ضغط الملف أو تقليل حجمه.',
            isError: true,
          );
        }
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
    const targetSection = 'ALL';

    if (_selectedFile == null) {
      _showSnackbar('يرجى اختيار ملف المحاضرة أولاً (PDF / مستند / صورة)', isError: true);
      return;
    }

    if (_selectedFileSize > 50 * 1024 * 1024) {
      _showSnackbar(
        'حجم الملف المختار (${_formatFileSize(_selectedFileSize)}) يتجاوز الحد الأقصى المسموح به للرفع المباشر (50 ميغابايت). يرجى تقليل حجم الملف أو استخدام ملف آخر.',
        isError: true,
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _uploadStatusMessage = 'جاري التحضير ورفع المحاضرة إلى السحابة...';
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
      setState(() => _selectedFile = null);
      _lectureTitleController.clear();
      _subjectNameController.clear();
      _driveUrlController.clear();
      _lectureDescController.clear();
      _showSnackbar('تم رفع ونشر المحاضرة بنجاح');
      _loadDashboardData(forceRefresh: true);
    } else {
      _showSnackbar(result.message, isError: true);
    }
  }

  // ── نشر إعلان أكاديمي ──────────────────────────────────────────
  Future<void> _submitAnnouncement() async {
    final content = _announcementContentController.text.trim();
    final subject = _announcementSubjectController.text.trim();

    if (content.isEmpty) {
      _showSnackbar('يرجى كتابة نص التبليغ بالتفصيل', isError: true);
      return;
    }

    // استخراج عنوان تلقائي لقاعدة البيانات دون الحاجة لإدخاله يدوياً
    final firstLine = content.split('\n').first.trim();
    final autoTitle = firstLine.length > 50
        ? '${firstLine.substring(0, 47)}...'
        : (firstLine.isNotEmpty ? firstLine : (subject.isNotEmpty ? subject : 'تبليغ أكاديمي'));

    final targetDept = _currentUser?.isAdmin == true ? _selectedAnnounceDept : (_currentUser?.department ?? _selectedAnnounceDept);
    final targetStage = _currentUser?.isAdmin == true ? _selectedAnnounceStage : (_currentUser?.stage ?? _selectedAnnounceStage);
    final targetSection = _currentUser?.isAdmin == true ? _selectedAnnounceSection : (_currentUser?.section ?? 'ALL');

    setState(() => _isLoading = true);

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
        _allAnnouncements.insert(0, newAnnounce);
      });
      _showSnackbar('تم نشر الإعلان بنجاح');
      _loadDashboardData(forceRefresh: true, showSpinner: false);
    } else {
      _showSnackbar('حدث خطأ أثناء نشر الإعلان', isError: true);
    }
  }

  // ── ترقية مستخدم ──────────────────────────────────────────────
  void _showPromoteDialog(AppUserModel user) {
    String selectedRole = user.role;
    bool canLectures = user.canPublishLectures;
    bool canAnnouncements = user.canPublishAnnouncements;
    int selectedSemester = user.semester;
    final sectionController = TextEditingController(text: user.section ?? '');

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(
                'ترقية وإدارة صلاحيات: ${user.name}',
                style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'المعرف: ${user.studentId} • ${user.department}',
                      style: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFF94A3B8)),
                    ),
                    const Divider(color: AppTheme.lightBorder, height: 20),

                    Text('الدور والصلاحية الأكاديمية:', style: GoogleFonts.cairo(fontSize: 13, color: AppTheme.textPrimary)),
                    const SizedBox(height: 8),

                    // اختيار الدور
                    _buildRoleRadio(
                      title: 'طالب (Student)',
                      subtitle: 'صلاحيات قراءة فقط',
                      roleValue: AppConstants.roleStudent,
                      groupValue: selectedRole,
                      onChanged: (val) {
                        setDialogState(() {
                          selectedRole = val!;
                          canLectures = false;
                          canAnnouncements = false;
                        });
                      },
                    ),
                    _buildRoleRadio(
                      title: 'ممثل الشعبة ⭐ (Representative)',
                      subtitle: 'صلاحيات نشر المحاضرات والتبليغات لشعبته فقط',
                      roleValue: AppConstants.roleRepresentative,
                      groupValue: selectedRole,
                      onChanged: (val) {
                        setDialogState(() {
                          selectedRole = val!;
                          canLectures = true;
                          canAnnouncements = true;
                        });
                      },
                    ),
                    _buildRoleRadio(
                      title: 'مشرف عام (Admin)',
                      subtitle: 'كامل الصلاحيات والتحكم والترقيات',
                      roleValue: AppConstants.roleAdmin,
                      groupValue: selectedRole,
                      onChanged: (val) {
                        setDialogState(() {
                          selectedRole = val!;
                          canLectures = true;
                          canAnnouncements = true;
                        });
                      },
                    ),

                    const Divider(color: AppTheme.lightBorder, height: 20),

                    // الشعبة
                    TextField(
                      controller: sectionController,
                      style: GoogleFonts.cairo(color: AppTheme.textPrimary, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'الشعبة الأكاديمية (A, B, C...)',
                        labelStyle: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textSecondary),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                    ),
                    const SizedBox(height: 12),

                    Text('الفصل الدراسي المخصص للطالب:', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: Center(
                              child: Text(
                                'الفصل الأول (1)',
                                style: GoogleFonts.cairo(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: selectedSemester == 1 ? Colors.white : AppTheme.textSecondary,
                                ),
                              ),
                            ),
                            selected: selectedSemester == 1,
                            selectedColor: AppTheme.primary,
                            onSelected: (s) {
                              if (s) setDialogState(() => selectedSemester = 1);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: Center(
                              child: Text(
                                'الفصل الثاني (2)',
                                style: GoogleFonts.cairo(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: selectedSemester == 2 ? Colors.white : AppTheme.textSecondary,
                                ),
                              ),
                            ),
                            selected: selectedSemester == 2,
                            selectedColor: AppTheme.primary,
                            onSelected: (s) {
                              if (s) setDialogState(() => selectedSemester = 2);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // مفاتيح الصلاحيات المخصصة
                    SwitchListTile(
                      title: Text('صلاحية نشر ومشاركة المحاضرات', style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textPrimary)),
                      value: canLectures,
                      activeThumbColor: AppTheme.primaryLight,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) => setDialogState(() => canLectures = val),
                    ),
                    SwitchListTile(
                      title: Text('صلاحية نشر الإعلانات والتبليغات', style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textPrimary)),
                      value: canAnnouncements,
                      activeThumbColor: AppTheme.primaryLight,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) => setDialogState(() => canAnnouncements = val),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('إلغاء', style: GoogleFonts.cairo(color: const Color(0xFF94A3B8))),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final ok = await SupabaseService().updateUserRole(
                      studentId: user.studentId,
                      role: selectedRole,
                      canPublishLectures: canLectures,
                      canPublishAnnouncements: canAnnouncements,
                      section: sectionController.text.trim().toUpperCase(),
                    );
                    if (selectedSemester != user.semester) {
                      await SupabaseService().updateUserSemester(
                        studentId: user.studentId,
                        semester: selectedSemester,
                      );
                    }
                    if (ok) {
                      _showSnackbar('تم تعديل صلاحيات وفصل (${user.name}) بنجاح');
                      _loadDashboardData();
                    } else {
                      _showSnackbar('فشل تعديل الصلاحيات', isError: true);
                    }
                  },
                  child: const Text('حفظ الترقية'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildRoleRadio({
    required String title,
    required String subtitle,
    required String roleValue,
    required String groupValue,
    required ValueChanged<String?> onChanged,
  }) {
    return RadioListTile<String>(
      title: Text(title, style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
      subtitle: Text(subtitle, style: GoogleFonts.cairo(fontSize: 10, color: const Color(0xFF94A3B8))),
      value: roleValue,
      groupValue: groupValue,
      activeColor: AppTheme.primaryLight,
      contentPadding: EdgeInsets.zero,
      onChanged: onChanged,
    );
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
    return Scaffold(
      backgroundColor: AppTheme.lightBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
        title: Text(
          _isMujtaba ? 'داش بورد المشرف العام (مجتبى عواد)' : 'لوحة ممثل الدفعة والنشر',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textSecondary,
          indicatorColor: AppTheme.primary,
          indicatorWeight: 3,
          labelStyle: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12.5),
          tabs: _isMujtaba
              ? const [
                  Tab(icon: Icon(Icons.cloud_upload_rounded), text: 'استوديو النشر'),
                  Tab(icon: Icon(Icons.manage_accounts_rounded), text: 'المقررات والطلاب'),
                  Tab(icon: Icon(Icons.radar_rounded), text: 'رادار العمليات'),
                ]
              : const [
                  Tab(icon: Icon(Icons.upload_file_rounded), text: 'نشر المحاضرات'),
                  Tab(icon: Icon(Icons.campaign_rounded), text: 'نشر إعلان'),
                ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _isMujtaba
            ? [
                _buildUnifiedPublishTab(),
                _buildCourseAndDirectoryTab(),
                _buildRadarAndModerationTab(),
              ]
            : [
                _buildPublishLectureTab(),
                _buildPublishAnnouncementTab(),
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
                  : _buildBannersPanel(),
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
              ? _buildCourseManagementTab()
              : _buildRepsDirectoryTab(),
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

  // ── مركز إدارة وتخصيص وإخفاء المقررات الدراسية ──────────────────
  Widget _buildCourseManagementTab() {
    final allBiometric = BiometricSubjects.getSubjectNames(
      department: _courseMgmtDept,
      stage: _courseMgmtStage,
      semester: _courseMgmtSemester,
    );

    final customService = CourseCustomizationService();

    final filteredSubjects = allBiometric.where((name) {
      if (_courseMgmtSearchQuery.isEmpty) return true;
      final q = _courseMgmtSearchQuery.toLowerCase().trim();
      final override = customService.getOverrideFor(
        name,
        department: _courseMgmtDept,
        stage: _courseMgmtStage,
        semester: _courseMgmtSemester,
      );
      final disp = override?.displayName ?? name;
      final code = override?.customCode ?? BiometricSubjects.findSubject(
        name,
        department: _courseMgmtDept,
        stage: _courseMgmtStage,
        semester: _courseMgmtSemester,
      )?.code;
      return disp.toLowerCase().contains(q) || name.toLowerCase().contains(q) || (code != null && code.toLowerCase().contains(q));
    }).toList();

    int hiddenCount = 0;
    for (final name in allBiometric) {
      if (customService.getOverrideFor(
        name,
        department: _courseMgmtDept,
        stage: _courseMgmtStage,
        semester: _courseMgmtSemester,
      )?.isHidden == true) {
        hiddenCount++;
      }
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // لوحة اختيار القسم والمرحلة
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppTheme.lightBorder),
              boxShadow: AppShadows.card,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.school_rounded, color: AppTheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'نطاق المقررات الدراسية',
                      style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        value: _courseMgmtDept,
                        dropdownColor: Colors.white,
                        style: AppTypography.body(color: AppTheme.textPrimary),
                        decoration: InputDecoration(
                          labelText: 'القسم الأكاديمي',
                          labelStyle: AppTypography.caption(color: AppTheme.textSecondary),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          filled: true,
                          fillColor: AppTheme.lightSurface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            borderSide: const BorderSide(color: AppTheme.lightBorder),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            borderSide: const BorderSide(color: AppTheme.lightBorder),
                          ),
                        ),
                        items: AppConstants.departments.map((d) {
                          return DropdownMenuItem(
                            value: d,
                            child: Text(d, style: GoogleFonts.cairo(fontSize: 12)),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _courseMgmtDept = val);
                            CourseCustomizationService().getOverrides(
                              department: _courseMgmtDept,
                              stage: _courseMgmtStage,
                              semester: _courseMgmtSemester,
                              forceRefresh: true,
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: _courseMgmtStage,
                        dropdownColor: Colors.white,
                        style: AppTypography.body(color: AppTheme.textPrimary),
                        decoration: InputDecoration(
                          labelText: 'المرحلة',
                          labelStyle: AppTypography.caption(color: AppTheme.textSecondary),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          filled: true,
                          fillColor: AppTheme.lightSurface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            borderSide: const BorderSide(color: AppTheme.lightBorder),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            borderSide: const BorderSide(color: AppTheme.lightBorder),
                          ),
                        ),
                        items: AppConstants.stages.map((s) {
                          return DropdownMenuItem(
                            value: s,
                            child: Text(s, style: GoogleFonts.cairo(fontSize: 12)),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _courseMgmtStage = val);
                            CourseCustomizationService().getOverrides(
                              department: _courseMgmtDept,
                              stage: _courseMgmtStage,
                              semester: _courseMgmtSemester,
                              forceRefresh: true,
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // محدد الفصل الدراسي الأول / الفصل الدراسي الثاني
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppTheme.lightSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.lightBorder),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: AppTactileBounce(
                          lowerBound: 0.94,
                          onTap: () {
                            if (_courseMgmtSemester != 1) {
                              HapticFeedback.selectionClick();
                              setState(() => _courseMgmtSemester = 1);
                              CourseCustomizationService().getOverrides(
                                department: _courseMgmtDept,
                                stage: _courseMgmtStage,
                                semester: 1,
                                forceRefresh: true,
                              );
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            decoration: BoxDecoration(
                              color: _courseMgmtSemester == 1 ? Colors.white : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: _courseMgmtSemester == 1 ? AppShadows.subtle : null,
                            ),
                            child: Center(
                              child: Text(
                                'الفصل الدراسي الأول',
                                style: GoogleFonts.cairo(
                                  fontSize: 11.5,
                                  fontWeight: _courseMgmtSemester == 1 ? FontWeight.bold : FontWeight.w600,
                                  color: _courseMgmtSemester == 1 ? AppTheme.primary : AppTheme.textSecondary,
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
                            if (_courseMgmtSemester != 2) {
                              HapticFeedback.selectionClick();
                              setState(() => _courseMgmtSemester = 2);
                              CourseCustomizationService().getOverrides(
                                department: _courseMgmtDept,
                                stage: _courseMgmtStage,
                                semester: 2,
                                forceRefresh: true,
                              );
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            decoration: BoxDecoration(
                              color: _courseMgmtSemester == 2 ? Colors.white : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: _courseMgmtSemester == 2 ? AppShadows.subtle : null,
                            ),
                            child: Center(
                              child: Text(
                                'الفصل الدراسي الثاني',
                                style: GoogleFonts.cairo(
                                  fontSize: 11.5,
                                  fontWeight: _courseMgmtSemester == 2 ? FontWeight.bold : FontWeight.w600,
                                  color: _courseMgmtSemester == 2 ? AppTheme.primary : AppTheme.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // شريط البحث وإحصائيات سريعة
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppTheme.lightBorder),
              boxShadow: AppShadows.card,
            ),
            child: Column(
              children: [
                TextField(
                  style: AppTypography.body(color: AppTheme.textPrimary),
                  onChanged: (val) => setState(() => _courseMgmtSearchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'بحث في المقررات أو الرمز...',
                    hintStyle: AppTypography.body(color: AppTheme.textMuted),
                    prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.primary, size: 20),
                    suffixIcon: _courseMgmtSearchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () => setState(() => _courseMgmtSearchQuery = ''),
                          )
                        : null,
                    filled: true,
                    fillColor: AppTheme.lightSurface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: const BorderSide(color: AppTheme.lightBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: const BorderSide(color: AppTheme.lightBorder),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'إجمالي المقررات: ${allBiometric.length}',
                      style: GoogleFonts.cairo(fontSize: 11.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w600),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: hiddenCount > 0 ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: hiddenCount > 0 ? const Color(0xFFFCA5A5) : const Color(0xFF86EFAC),
                        ),
                      ),
                      child: Text(
                        '$hiddenCount مخفي عن الطلاب',
                        style: GoogleFonts.cairo(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: hiddenCount > 0 ? AppTheme.danger : const Color(0xFF16A34A),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // قائمة المقررات الدراسية
          if (filteredSubjects.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: AppTheme.lightBorder),
              ),
              child: Center(
                child: Text(
                  'لا توجد مواد مطابقة للبحث في هذا القسم والمرحلة',
                  style: GoogleFonts.cairo(color: AppTheme.textMuted, fontSize: 13),
                ),
              ),
            )
          else
            ...filteredSubjects.map((origName) {
              final override = customService.getOverrideFor(
                origName,
                department: _courseMgmtDept,
                stage: _courseMgmtStage,
                semester: _courseMgmtSemester,
              );
              final subModel = BiometricSubjects.findSubject(
                origName,
                department: _courseMgmtDept,
                stage: _courseMgmtStage,
                semester: _courseMgmtSemester,
              );
              final isHidden = override?.isHidden ?? false;
              final dispName = override?.displayName ?? origName;
              final code = override?.customCode ?? subModel?.code;
              final hasOverride = override != null;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isHidden ? const Color(0xFFF8FAFC) : Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(
                    color: isHidden ? const Color(0xFFCBD5E1) : AppTheme.lightBorder,
                    width: isHidden ? 1.2 : 1.0,
                  ),
                  boxShadow: isHidden ? [] : AppShadows.card,
                ),
                child: Row(
                  children: [
                    AppIconBadge.indigo(
                      icon: BiometricSubjects.getIconForSubject(origName),
                      size: 42,
                      iconSize: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  dispName,
                                  style: AppTypography.h3(
                                    color: isHidden ? const Color(0xFF64748B) : AppTheme.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (code != null) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: Text(
                                    code,
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
                          if (dispName != origName) ...[
                            const SizedBox(height: 2),
                            Text(
                              'الاسم المرجعي بالبصمة: $origName',
                              style: AppTypography.tiny(color: AppTheme.textMuted),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: isHidden ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isHidden ? 'مخفي عن الطلاب' : 'مرئي للطلاب',
                                  style: GoogleFonts.cairo(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: isHidden ? AppTheme.danger : const Color(0xFF16A34A),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch.adaptive(
                      value: !isHidden,
                      activeColor: AppTheme.primary,
                      onChanged: (visible) async {
                        if (_currentUser != null) {
                          await CourseCustomizationService().toggleHideCourse(
                            originalName: origName,
                            isHidden: !visible,
                            department: _courseMgmtDept,
                            stage: _courseMgmtStage,
                            semester: _courseMgmtSemester,
                            user: _currentUser!,
                            currentCustomName: override?.displayName,
                            currentCustomCode: override?.customCode,
                          );
                          setState(() {});
                        }
                      },
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.edit_note_rounded,
                        color: hasOverride ? AppTheme.primary : AppTheme.textSecondary,
                        size: 22,
                      ),
                      tooltip: 'تخصيص المقرر',
                      onPressed: () {
                        if (_currentUser != null) {
                          CourseCustomizationSheet.show(
                            context: context,
                            originalName: origName,
                            defaultCode: subModel?.code,
                            department: _courseMgmtDept,
                            stage: _courseMgmtStage,
                            semester: _courseMgmtSemester,
                            user: _currentUser!,
                            currentOverride: override,
                            onSaved: () => setState(() {}),
                          );
                        }
                      },
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
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
                                color: _selectedFileSize > 50 * 1024 * 1024
                                    ? AppTheme.danger.withValues(alpha: 0.2)
                                    : AppTheme.success.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _selectedFileSize > 50 * 1024 * 1024
                                    ? 'الحجم: ${_formatFileSize(_selectedFileSize)} (يتجاوز 50MB)'
                                    : 'الحجم: ${_formatFileSize(_selectedFileSize)}',
                                style: GoogleFonts.cairo(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: _selectedFileSize > 50 * 1024 * 1024 ? AppTheme.danger : AppTheme.success,
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
                              : 'جاري رفع المحاضرة إلى سحابة المنظومة ومزامنتها...',
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
              (l.section == _currentUser!.section || l.section == 'ALL'));
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
              (a.section == _currentUser!.section || a.section == 'ALL' || a.section.isEmpty));
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

  // ══════════════════════════════════════════════════════════════
  // ══════════════════════════════════════════════════════════════
  // تبويب دليل وإدارة الطلاب وممثلي الشعب لمجتبى
  // ══════════════════════════════════════════════════════════════
  Widget _buildRepsDirectoryTab() {
    final filtered = _allUsers.where((user) {
      if (_userDirectoryRoleFilter == 'REPS') {
        if (!user.isRepresentative && !user.canPublishLectures && !user.canPublishAnnouncements) return false;
      } else if (_userDirectoryRoleFilter == 'STUDENTS') {
        if (!user.isStudent) return false;
      }

      final matchDept = _repDeptFilter == 'ALL' || user.department.contains(_repDeptFilter) || _repDeptFilter.contains(user.department);
      final matchStage = _userDirectoryStageFilter == 'ALL' ||
          AppConstants.normalizeStage(user.stage) == AppConstants.normalizeStage(_userDirectoryStageFilter);
      final q = _repSearchQuery.trim().toLowerCase();
      final matchSearch = q.isEmpty ||
          user.name.toLowerCase().contains(q) ||
          user.studentId.toLowerCase().contains(q) ||
          (user.section != null && user.section!.toLowerCase().contains(q)) ||
          user.department.toLowerCase().contains(q);
      return matchDept && matchStage && matchSearch;
    }).toList();

    return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ══════════════════════════════════════════════════════════════
          // بطاقة إدارة وتكليف ممثلي الشُعب (نظام البصمة المعتمد)
          // ══════════════════════════════════════════════════════════════
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primary.withValues(alpha: 0.15),
                  Colors.white,
                ],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.fingerprint_rounded, color: AppTheme.accent, size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'إدارة وتكليف ممثلي الشُعب (نظام البصمة)',
                            style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                          ),
                          Text(
                            'اختر القسم والمرحلة والشعبة لتعيين الممثل المعتمد من قاعدة بيانات البصمة',
                            style: GoogleFonts.cairo(fontSize: 10, color: const Color(0xFF94A3B8)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // 1. اختيار القسم والمرحلة
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        value: _selectedRepDept,
                        dropdownColor: Colors.white,
                        style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textPrimary),
                        decoration: InputDecoration(
                          labelText: 'القسم الأكاديمي',
                          labelStyle: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textSecondary),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        items: AppConstants.departments.map((d) => DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis))).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedRepDept = val);
                            _loadBiometricSections();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: _selectedRepStage,
                        dropdownColor: Colors.white,
                        style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textPrimary),
                        decoration: InputDecoration(
                          labelText: 'المرحلة',
                          labelStyle: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textSecondary),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        items: AppConstants.stages.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedRepStage = val);
                            _loadBiometricSections();
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // 2. أزرار الشعب الأفقية المستخرجة من البصمة
                Text(
                  'شُعب المرحلة المعتمدة بالبصمة:',
                  style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFFCBD5E1)),
                ),
                const SizedBox(height: 6),
                _isLoadingSections
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent))),
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _availableBiometricSections.map((sec) {
                            final isSel = _selectedRepSection == sec;
                            final repCount = _allUsers.where((u) =>
                              u.isRepresentative &&
                              u.department == _selectedRepDept &&
                              AppConstants.normalizeStage(u.stage) == AppConstants.normalizeStage(_selectedRepStage) &&
                              u.section == sec
                            ).length;

                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(
                                  'شعبة ($sec) ${repCount > 0 ? "★ ($repCount)" : ""}',
                                  style: GoogleFonts.cairo(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isSel ? Colors.black : (repCount > 0 ? AppTheme.accent : const Color(0xFF94A3B8)),
                                  ),
                                ),
                                selected: isSel,
                                selectedColor: AppTheme.accent,
                                backgroundColor: Colors.white,
                                side: BorderSide(color: isSel ? AppTheme.accent : AppTheme.lightBorder),
                                onSelected: (s) {
                                  if (s) setState(() => _selectedRepSection = sec);
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                const Divider(color: AppTheme.lightBorder, height: 24),

                // 3. ممثلو الشعبة الحالية والزر المباشر للتكليف
                Builder(
                  builder: (context) {
                    final currentReps = _allUsers.where((u) =>
                      u.isRepresentative &&
                      u.department == _selectedRepDept &&
                      AppConstants.normalizeStage(u.stage) == AppConstants.normalizeStage(_selectedRepStage) &&
                      u.section == _selectedRepSection
                    ).toList();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'ممثلو شعبة ($_selectedRepSection):',
                              style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.accent),
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.accent,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.black, size: 16),
                              label: Text(
                                'تكليف ممثل للشعبة ⭐',
                                style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
                              ),
                              onPressed: () => _showAssignBiometricRepDialog(
                                department: _selectedRepDept,
                                stage: _selectedRepStage,
                                section: _selectedRepSection,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        if (currentReps.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppTheme.lightBorder),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline_rounded, color: Color(0xFF94A3B8), size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'لا يوجد ممثل مكلف حالياً لشعبة ($_selectedRepSection). انقر على "تكليف ممثل للشعبة" لاختيار طالب من نظام البصمة.',
                                    style: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFF94A3B8)),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Column(
                            children: currentReps.map((rep) {
                              return Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor: AppTheme.accent.withValues(alpha: 0.2),
                                      backgroundImage: rep.photoUrl != null && rep.photoUrl!.isNotEmpty ? NetworkImage(rep.photoUrl!) : null,
                                      child: rep.photoUrl == null || rep.photoUrl!.isEmpty
                                          ? const Icon(Icons.person, color: AppTheme.accent, size: 18)
                                          : null,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            rep.name,
                                            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                          ),
                                          Text(
                                            '${rep.studentId} • ممثل شعبة ${rep.section ?? _selectedRepSection}',
                                            style: GoogleFonts.cairo(fontSize: 10, color: const Color(0xFF94A3B8)),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.edit_note_rounded, color: AppTheme.accent, size: 18),
                                      tooltip: 'تعديل الصلاحيات',
                                      onPressed: () => _showPromoteDialog(rep),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.person_remove_rounded, color: AppTheme.danger, size: 18),
                                      tooltip: 'سحب التكليف',
                                      onPressed: () => _confirmDemoteRep(rep),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // رأس دليل الطلاب المسجلين
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'دليل الطلاب والمسجلين في التطبيق',
                      style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                    Text(
                      '${filtered.length} مستخدم معروض من إجمالي ${_allUsers.length} طالب',
                      style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.accent),
                    ),
                  ],
                ),
              ),
              AppTactileBounce(
                lowerBound: 0.92,
                onTap: _showBatchPromotionDialog,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.primary, Color(0xFF6366F1)],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: AppShadows.subtle,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.school_rounded, color: Colors.white, size: 15),
                      const SizedBox(width: 5),
                      Text(
                        'ترقية دفعة إلى الفصل 2 🎓',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── تصنيف الرتب (الكل / الممثلين / الطلاب) ──
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: Text('جميع المسجلين (${_allUsers.length})'),
                  selected: _userDirectoryRoleFilter == 'ALL',
                  onSelected: (s) => setState(() => _userDirectoryRoleFilter = 'ALL'),
                  selectedColor: AppTheme.accent,
                  labelStyle: GoogleFonts.cairo(
                    color: _userDirectoryRoleFilter == 'ALL' ? Colors.black : const Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: Text('ممثلو الشعب ⭐ (${_representatives.length})'),
                  selected: _userDirectoryRoleFilter == 'REPS',
                  onSelected: (s) => setState(() => _userDirectoryRoleFilter = 'REPS'),
                  selectedColor: AppTheme.accent,
                  labelStyle: GoogleFonts.cairo(
                    color: _userDirectoryRoleFilter == 'REPS' ? Colors.black : const Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: Text('الطلبة فقط 🎓 (${_allUsers.where((u) => u.isStudent).length})'),
                  selected: _userDirectoryRoleFilter == 'STUDENTS',
                  onSelected: (s) => setState(() => _userDirectoryRoleFilter = 'STUDENTS'),
                  selectedColor: AppTheme.accent,
                  labelStyle: GoogleFonts.cairo(
                    color: _userDirectoryRoleFilter == 'STUDENTS' ? Colors.black : const Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // شريط البحث
          TextField(
            style: GoogleFonts.cairo(color: AppTheme.textPrimary, fontSize: 13),
            onChanged: (val) => setState(() => _repSearchQuery = val),
            decoration: InputDecoration(
              hintText: 'ابحث بالاسم، المعرف الجامعي (ST-...)، الشعبة، أو القسم...',
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

          // فلترة الأقسام
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('كافة الأقسام'),
                  selected: _repDeptFilter == 'ALL',
                  onSelected: (s) => setState(() => _repDeptFilter = 'ALL'),
                  selectedColor: AppTheme.primaryLight,
                  labelStyle: GoogleFonts.cairo(
                    color: _repDeptFilter == 'ALL' ? Colors.white : const Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ...AppConstants.departments.map((dept) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(dept),
                      selected: _repDeptFilter == dept,
                      onSelected: (s) => setState(() => _repDeptFilter = s ? dept : 'ALL'),
                      selectedColor: AppTheme.primaryLight,
                      labelStyle: GoogleFonts.cairo(
                        color: _repDeptFilter == dept ? Colors.white : const Color(0xFF94A3B8),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // فلترة المراحل
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('كافة المراحل'),
                  selected: _userDirectoryStageFilter == 'ALL',
                  onSelected: (s) => setState(() => _userDirectoryStageFilter = 'ALL'),
                  selectedColor: AppTheme.primaryLight,
                  labelStyle: GoogleFonts.cairo(
                    color: _userDirectoryStageFilter == 'ALL' ? Colors.white : const Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ...AppConstants.stages.map((stage) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(stage),
                      selected: _userDirectoryStageFilter == stage,
                      onSelected: (s) => setState(() => _userDirectoryStageFilter = s ? stage : 'ALL'),
                      selectedColor: AppTheme.primaryLight,
                      labelStyle: GoogleFonts.cairo(
                        color: _userDirectoryStageFilter == stage ? Colors.white : const Color(0xFF94A3B8),
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
            _buildEmptyStateCard('لم يتم العثور على طلاب أو ممثلين مطابقين للبحث')
          else ...[
            ...filtered.take(_directoryDisplayLimit).map((user) => _buildRepCard(user)),
            if (filtered.length > _directoryDisplayLimit)
              _buildLoadMoreButton(
                label: 'عرض المزيد (${filtered.length - _directoryDisplayLimit} طالب إضافي)',
                onPressed: () => setState(() => _directoryDisplayLimit += 50),
              ),
          ],
        ],
      );
  }

  Widget _buildRepCard(AppUserModel rep) {
    final bool isRep = rep.isRepresentative || rep.canPublishLectures || rep.canPublishAnnouncements;
    final bool isAdmin = rep.isAdmin;
    final lectureCount = _allLectures.where((l) => l.uploaderId == rep.studentId).length;
    final announceCount = _allAnnouncements.where((a) => a.authorId == rep.studentId).length;

    Color avatarColor = AppTheme.primaryLight;
    if (isAdmin) {
      avatarColor = Colors.greenAccent;
    } else if (isRep) {
      avatarColor = AppTheme.accent;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAdmin
              ? Colors.greenAccent.withValues(alpha: 0.4)
              : (isRep ? AppTheme.accent.withValues(alpha: 0.4) : AppTheme.lightBorder),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: avatarColor.withValues(alpha: 0.15),
                child: Text(
                  rep.name.isNotEmpty ? rep.name[0] : 'S',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: avatarColor),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            rep.name,
                            style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: avatarColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: avatarColor.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            isAdmin ? 'مشرف عام 🛡️' : (isRep ? 'ممثل الشعبة ⭐' : 'طالب 🎓'),
                            style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.bold, color: avatarColor),
                          ),
                        ),
                        const SizedBox(width: 6),
                        AppTactileBounce(
                          lowerBound: 0.92,
                          onTap: () async {
                            final nextSemester = rep.semester == 1 ? 2 : 1;
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                title: Text('تحويل الفصل الدراسي', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 15)),
                                content: Text(
                                  'هل تريد تحويل الطالب (${rep.name}) إلى الفصل الدراسي ${nextSemester == 2 ? "الثاني" : "الأول"}؟',
                                  style: GoogleFonts.cairo(fontSize: 13),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: Text('إلغاء', style: GoogleFonts.cairo(color: AppTheme.textSecondary)),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.primary,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: Text('تأكيد التحويل', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              final success = await SupabaseService().updateUserSemester(
                                studentId: rep.studentId,
                                semester: nextSemester,
                              );
                              if (success) {
                                setState(() {
                                  final idx = _allUsers.indexWhere((u) => u.studentId == rep.studentId);
                                  if (idx != -1) {
                                    _allUsers[idx] = _allUsers[idx].copyWith(semester: nextSemester);
                                  }
                                });
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('تم تحويل ${rep.name} إلى الفصل $nextSemester بنجاح', style: GoogleFonts.cairo()),
                                      backgroundColor: const Color(0xFF16A34A),
                                    ),
                                  );
                                }
                              }
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: rep.semester == 2 ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: rep.semester == 2 ? const Color(0xFF3B82F6) : const Color(0xFF94A3B8),
                                width: 0.9,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.swap_horiz_rounded,
                                  size: 12,
                                  color: rep.semester == 2 ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  rep.semester == 2 ? 'الفصل 2' : 'الفصل 1',
                                  style: GoogleFonts.cairo(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: rep.semester == 2 ? const Color(0xFF2563EB) : const Color(0xFF475569),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${rep.studentId} • ${rep.department} (${rep.stage})${rep.section != null && rep.section!.isNotEmpty ? ' • شعبة ${rep.section}' : ''}',
                      style: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFF94A3B8)),
                    ),
                    if (rep.createdAt != null)
                      Text(
                        'تاريخ التسجيل: ${rep.createdAt!.year}/${rep.createdAt!.month.toString().padLeft(2, '0')}/${rep.createdAt!.day.toString().padLeft(2, '0')}',
                        style: GoogleFonts.cairo(fontSize: 9.5, color: const Color(0xFF64748B)),
                      ),
                  ],
                ),
              ),
            ],
          ),

          if (isRep) ...[
            const SizedBox(height: 10),
            // إحصائية نشاط الممثل
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bar_chart_rounded, size: 16, color: AppTheme.primaryLight),
                  const SizedBox(width: 6),
                  Text(
                    'نشاط النشر: $lectureCount محاضرات • $announceCount تبليغات',
                    style: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFFCBD5E1), fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // مفاتيح التحكم السريع بالصلاحيات بنقرة زر
            Row(
              children: [
                Expanded(
                  child: SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('رفع المحاضرات', style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textPrimary)),
                    value: rep.canPublishLectures,
                    activeColor: AppTheme.primaryLight,
                    onChanged: (val) async {
                      setState(() {
                        final idx = _allUsers.indexWhere((u) => u.studentId == rep.studentId);
                        if (idx != -1) {
                          _allUsers[idx] = AppUserModel(
                            id: rep.id,
                            studentId: rep.studentId,
                            name: rep.name,
                            department: rep.department,
                            stage: rep.stage,
                            section: rep.section,
                            role: rep.role,
                            canPublishLectures: val,
                            canPublishAnnouncements: rep.canPublishAnnouncements,
                          );
                        }
                      });
                      await SupabaseService().updateUserRole(
                        studentId: rep.studentId,
                        role: rep.role,
                        canPublishLectures: val,
                        canPublishAnnouncements: rep.canPublishAnnouncements,
                        section: rep.section,
                      );
                    },
                  ),
                ),
                Expanded(
                  child: SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('نشر التبليغات', style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textPrimary)),
                    value: rep.canPublishAnnouncements,
                    activeColor: AppTheme.accent,
                    onChanged: (val) async {
                      setState(() {
                        final idx = _allUsers.indexWhere((u) => u.studentId == rep.studentId);
                        if (idx != -1) {
                          _allUsers[idx] = AppUserModel(
                            id: rep.id,
                            studentId: rep.studentId,
                            name: rep.name,
                            department: rep.department,
                            stage: rep.stage,
                            section: rep.section,
                            role: rep.role,
                            canPublishLectures: rep.canPublishLectures,
                            canPublishAnnouncements: val,
                          );
                        }
                      });
                      await SupabaseService().updateUserRole(
                        studentId: rep.studentId,
                        role: rep.role,
                        canPublishLectures: rep.canPublishLectures,
                        canPublishAnnouncements: val,
                        section: rep.section,
                      );
                    },
                  ),
                ),
              ],
            ),
          ],

          const Divider(color: AppTheme.lightBorder, height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (isRep) ...[
                TextButton.icon(
                  icon: const Icon(Icons.edit_note_rounded, color: AppTheme.accent, size: 18),
                  label: Text('تعديل الشعبة والصلاحيات', style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.accent)),
                  onPressed: () => _showPromoteDialog(rep),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  icon: const Icon(Icons.person_remove_rounded, color: AppTheme.danger, size: 18),
                  label: Text('سحب التكليف', style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.danger)),
                  onPressed: () => _confirmDemoteRep(rep),
                ),
              ] else ...[
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.star_rounded, color: Colors.black, size: 16),
                  label: Text('ترقية إلى ممثل شعبة ⭐', style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black)),
                  onPressed: () => _showPromoteDialog(rep),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  icon: const Icon(Icons.tune_rounded, color: const Color(0xFF94A3B8), size: 18),
                  label: Text('إدارة الصلاحيات', style: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFF94A3B8))),
                  onPressed: () => _showPromoteDialog(rep),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _showBatchPromotionDialog() {
    String selectedDept = _repDeptFilter != 'ALL' ? _repDeptFilter : AppConstants.departments.first;
    String selectedStage = _userDirectoryStageFilter != 'ALL' ? _userDirectoryStageFilter : AppConstants.stages.first;
    int targetSemester = 2;
    bool isProcessing = false;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final matchingStudents = _allUsers.where((u) {
              final deptMatch = u.department == selectedDept || u.department.contains(selectedDept);
              final stageMatch = AppConstants.normalizeStage(u.stage) == AppConstants.normalizeStage(selectedStage);
              return deptMatch && stageMatch;
            }).toList();

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primarySubtle,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.school_rounded, color: AppTheme.primary, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'ترقية دفعة إلى الفصل الدراسي',
                      style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'اختر القسم والمرحلة المستهدفة لتحويل جميع طلابها دفعة واحدة إلى الفصل الدراسي المطلوب:',
                      style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 14),

                    // اختيار القسم
                    DropdownButtonFormField<String>(
                      value: selectedDept,
                      dropdownColor: Colors.white,
                      style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'القسم الأكاديمي',
                        labelStyle: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textSecondary),
                        filled: true,
                        fillColor: AppTheme.lightSurface,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      items: AppConstants.departments.map((d) {
                        return DropdownMenuItem(value: d, child: Text(d, style: GoogleFonts.cairo(fontSize: 12)));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedDept = val);
                      },
                    ),
                    const SizedBox(height: 10),

                    // اختيار المرحلة
                    DropdownButtonFormField<String>(
                      value: selectedStage,
                      dropdownColor: Colors.white,
                      style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'المرحلة',
                        labelStyle: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textSecondary),
                        filled: true,
                        fillColor: AppTheme.lightSurface,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      items: AppConstants.stages.map((s) {
                        return DropdownMenuItem(value: s, child: Text(s, style: GoogleFonts.cairo(fontSize: 12)));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedStage = val);
                      },
                    ),
                    const SizedBox(height: 12),

                    // الفصل الدراسي المستهدف
                    Text(
                      'الفصل الدراسي المستهدف:',
                      style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: Center(
                              child: Text(
                                'الفصل الثاني (2)',
                                style: GoogleFonts.cairo(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: targetSemester == 2 ? Colors.white : AppTheme.textSecondary,
                                ),
                              ),
                            ),
                            selected: targetSemester == 2,
                            selectedColor: AppTheme.primary,
                            onSelected: (s) {
                              if (s) setDialogState(() => targetSemester = 2);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: Center(
                              child: Text(
                                'الفصل الأول (1)',
                                style: GoogleFonts.cairo(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: targetSemester == 1 ? Colors.white : AppTheme.textSecondary,
                                ),
                              ),
                            ),
                            selected: targetSemester == 1,
                            selectedColor: AppTheme.primary,
                            onSelected: (s) {
                              if (s) setDialogState(() => targetSemester = 1);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // بطاقة الإحصائية والمعاينة
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: matchingStudents.isEmpty
                            ? const Color(0xFFFEF2F2)
                            : const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: matchingStudents.isEmpty
                              ? const Color(0xFFFCA5A5)
                              : const Color(0xFF86EFAC),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            matchingStudents.isEmpty ? Icons.info_outline : Icons.check_circle_outline_rounded,
                            color: matchingStudents.isEmpty ? AppTheme.danger : const Color(0xFF16A34A),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              matchingStudents.isEmpty
                                  ? 'لا يوجد طلاب مسجلين في هذا القسم والمرحلة حالياً.'
                                  : 'سيتم تحويل ${matchingStudents.length} طالب إلى الفصل الدراسي ($targetSemester).',
                              style: GoogleFonts.cairo(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: matchingStudents.isEmpty ? AppTheme.danger : const Color(0xFF15803D),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isProcessing ? null : () => Navigator.pop(dialogCtx),
                  child: Text('إلغاء', style: GoogleFonts.cairo(color: AppTheme.textSecondary)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    disabledBackgroundColor: AppTheme.primary.withValues(alpha: 0.5),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: (matchingStudents.isEmpty || isProcessing)
                      ? null
                      : () async {
                          setDialogState(() => isProcessing = true);
                          final count = await SupabaseService().batchUpdateSemester(
                            department: selectedDept,
                            stage: selectedStage,
                            semester: targetSemester,
                          );
                          setDialogState(() => isProcessing = false);
                          if (dialogCtx.mounted) Navigator.pop(dialogCtx);

                          // تحديث الكاش المحلي للمستخدمين المعروضين
                          setState(() {
                            for (int i = 0; i < _allUsers.length; i++) {
                              final u = _allUsers[i];
                              if ((u.department == selectedDept || u.department.contains(selectedDept)) &&
                                  AppConstants.normalizeStage(u.stage) == AppConstants.normalizeStage(selectedStage)) {
                                _allUsers[i] = u.copyWith(semester: targetSemester);
                              }
                            }
                          });

                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'تمت ترقية $count طالب في قسم $selectedDept ($selectedStage) إلى الفصل $targetSemester بنجاح',
                                  style: GoogleFonts.cairo(),
                                ),
                                backgroundColor: const Color(0xFF16A34A),
                              ),
                            );
                          }
                        },
                  child: isProcessing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          'تأكيد الترقية والتحويل',
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAssignBiometricRepDialog({
    required String department,
    required String stage,
    required String section,
  }) {
    String searchQuery = '';
    bool canLectures = true;
    bool canAnnouncements = true;
    bool isLoadingStudents = true;
    List<StudentModel> biometricStudents = [];
    StudentModel? selectedStudent;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            if (isLoadingStudents && biometricStudents.isEmpty) {
              SupabaseService()
                  .fetchBiometricStudentsBySection(
                    department: department,
                    stage: stage,
                    section: section,
                  )
                  .then((list) {
                setDialogState(() {
                  biometricStudents = list;
                  isLoadingStudents = false;
                });
              });
            }

            final filteredStudents = biometricStudents.where((s) {
              final q = searchQuery.trim().toLowerCase();
              if (q.isEmpty) return true;
              return s.name.toLowerCase().contains(q) || s.id.toLowerCase().contains(q);
            }).toList();

            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.stars_rounded, color: AppTheme.accent, size: 24),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'تكليف ممثل لشعبة ($section)',
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$department • $stage • قائمة نظام البصمة المعتمدة',
                    style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.primaryLight),
                  ),
                ],
              ),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      style: GoogleFonts.cairo(color: AppTheme.textPrimary, fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'ابحث عن اسم الطالب أو الرقم الجامعي...',
                        hintStyle: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFF64748B)),
                        prefixIcon: const Icon(Icons.search, size: 18, color: AppTheme.accent),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        filled: true,
                        fillColor: Colors.black.withValues(alpha: 0.2),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onChanged: (val) => setDialogState(() => searchQuery = val),
                    ),
                    const SizedBox(height: 10),

                    if (isLoadingStudents)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24.0),
                          child: CircularProgressIndicator(color: AppTheme.accent),
                        ),
                      )
                    else if (biometricStudents.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            'لم يتم العثور على طلاب مسجلين في شعبة ($section) في نظام البصمة لهذا القسم والمرحلة.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFF94A3B8)),
                          ),
                        ),
                      )
                    else
                      Container(
                        height: 220,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.lightBorder),
                        ),
                        child: filteredStudents.isEmpty
                            ? Center(
                                child: Text('لا توجد نتائج مطابقة للبحث',
                                    style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFF94A3B8))),
                              )
                            : ListView.separated(
                                itemCount: filteredStudents.length,
                                separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.lightBorder),
                                itemBuilder: (ctx, i) {
                                  final st = filteredStudents[i];
                                  final isSelected = selectedStudent?.id == st.id;
                                  final isAlreadyRep = _allUsers.any((u) => u.studentId == st.id && u.isRepresentative);

                                  return ListTile(
                                    dense: true,
                                    selected: isSelected,
                                    selectedTileColor: AppTheme.accent.withValues(alpha: 0.15),
                                    leading: CircleAvatar(
                                      radius: 16,
                                      backgroundColor: isSelected
                                          ? AppTheme.accent
                                          : AppTheme.primaryLight.withValues(alpha: 0.2),
                                      child: Text(
                                        st.name.isNotEmpty ? st.name.characters.first : 'ط',
                                        style: GoogleFonts.cairo(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: isSelected ? Colors.black : Colors.white,
                                        ),
                                      ),
                                    ),
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            st.name,
                                            style: GoogleFonts.cairo(
                                              fontSize: 12,
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                              color: isSelected ? AppTheme.accent : AppTheme.textPrimary,
                                            ),
                                          ),
                                        ),
                                        if (isAlreadyRep)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.amber.withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'ممثل حالي ⭐',
                                              style: GoogleFonts.cairo(fontSize: 9, color: Colors.amber, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                      ],
                                    ),
                                    subtitle: Text(
                                      'الرقم الجامعي: ${st.id}',
                                      style: GoogleFonts.cairo(fontSize: 10, color: const Color(0xFF94A3B8)),
                                    ),
                                    trailing: Radio<String>(
                                      value: st.id,
                                      groupValue: selectedStudent?.id,
                                      activeColor: AppTheme.accent,
                                      onChanged: (_) {
                                        setDialogState(() => selectedStudent = st);
                                      },
                                    ),
                                    onTap: () {
                                      setDialogState(() => selectedStudent = st);
                                    },
                                  );
                                },
                              ),
                      ),
                    const SizedBox(height: 12),

                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('صلاحية نشر المحاضرات لشعبته', style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textPrimary)),
                      value: canLectures,
                      activeColor: AppTheme.primaryLight,
                      onChanged: (v) => setDialogState(() => canLectures = v),
                    ),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('صلاحية نشر التبليغات لشعبته', style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textPrimary)),
                      value: canAnnouncements,
                      activeColor: AppTheme.accent,
                      onChanged: (v) => setDialogState(() => canAnnouncements = v),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: Text('إلغاء', style: GoogleFonts.cairo(color: const Color(0xFF94A3B8))),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.verified_user_rounded, color: Colors.black, size: 18),
                  label: Text('تكليف وتثبيت الممثل ⭐',
                      style: GoogleFonts.cairo(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: selectedStudent == null
                      ? null
                      : () async {
                          final targetStudent = selectedStudent!;
                          Navigator.pop(dialogCtx);
                          _showSnackbar('جارٍ تكليف ${targetStudent.name} ممثلاً لشعبة ($section)...');
                          final ok = await SupabaseService().assignSectionRepresentative(
                            student: targetStudent,
                            section: section,
                            canLectures: canLectures,
                            canAnnouncements: canAnnouncements,
                          );
                          if (ok) {
                            _showSnackbar('تم تكليف ${targetStudent.name} ممثلاً لشعبة ($section) بنجاح ⭐');
                            await _loadDashboardData();
                          } else {
                            _showSnackbar('حدث خطأ أثناء حفظ التكليف', isError: true);
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDemoteRep(AppUserModel rep) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('سحب التكليف من الممثل', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textPrimary)),
        content: Text('هل تريد بالتأكيد إلغاء صفة الممثل عن "${rep.name}" وإعادته طالباً عادياً؟', style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFFCBD5E1))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('سحب التكليف'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final ok = await SupabaseService().revokeRepresentative(rep.studentId);
      if (ok) {
        _showSnackbar('تم سحب التكليف بنجاح');
        _loadDashboardData();
      } else {
        _showSnackbar('حدث خطأ أثناء سحب التكليف', isError: true);
      }
    }
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
  Future<void> _loadBanners() async {
    setState(() => _isLoadingBanners = true);
    final all = await SupabaseService().fetchAnnouncements(department: 'ALL');
    final banners = all.where((a) => a.imageUrl != null && a.imageUrl!.isNotEmpty).toList();
    if (mounted) {
      setState(() {
        _existingBanners = banners;
        _isLoadingBanners = false;
      });
    }
  }

  Future<void> _pickBannerImage() async {
    setState(() => _isPickingBannerImage = true);
    final file = await TelegramUploaderService().pickImageOnly();
    if (mounted) {
      if (file != null) {
        final size = await TelegramUploaderService().getFileSize(file);
        setState(() {
          _isPickingBannerImage = false;
          _selectedBannerImage = file;
          _selectedBannerImageSize = size;
          if (_bannerTitleController.text.trim().isEmpty) {
            final nameWithoutExt = file.name.contains('.')
                ? file.name.substring(0, file.name.lastIndexOf('.'))
                : file.name;
            _bannerTitleController.text = nameWithoutExt;
          }
        });
      } else {
        setState(() => _isPickingBannerImage = false);
      }
    }
  }

  Future<void> _submitBanner() async {
    if (_selectedBannerImage == null) {
      _showSnackbar('يرجى اختيار صورة البوستر أولاً', isError: true);
      return;
    }
    final title = _bannerTitleController.text.trim();
    if (title.isEmpty) {
      _showSnackbar('يرجى كتابة عنوان البوستر', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    final res = await TelegramUploaderService().uploadFileToTelegram(
      file: _selectedBannerImage!,
      caption: title,
      fileType: 'banner',
    );

    if (!res.success || res.fileUrl == null) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackbar(res.message, isError: true);
      }
      return;
    }

    final baseContent = _bannerContentController.text.trim();
    final tgTag = res.telegramMessageId != null ? ' [TG_MSG_ID:${res.telegramMessageId}]' : '';

    final newBanner = AnnouncementModel(
      id: '',
      title: title,
      content: '$baseContent$tgTag',
      authorId: _currentUser?.studentId ?? 'ST-NUST-001630760-413',
      authorName: _currentUser?.name ?? 'مجتبى عواد',
      authorRole: 'admin',
      department: _selectedBannerDept,
      stage: _selectedBannerStage,
      category: 'activity',
      isPinned: true,
      imageUrl: res.fileUrl,
      createdAt: DateTime.now(),
    );

    final ok = await SupabaseService().createAnnouncement(newBanner);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (ok) {
      _bannerTitleController.clear();
      _bannerContentController.clear();
      setState(() {
        _selectedBannerImage = null;
        _selectedBannerImageSize = 0;
      });
      _showSnackbar('تم رفع ونشر البوستر في الواجهة الرئيسية بنجاح عبر سيرفر تيليجرام');
      _loadBanners();
    } else {
      _showSnackbar('حدث خطأ أثناء حفظ بيانات البوستر', isError: true);
    }
  }

  Future<void> _deleteBanner(String id) async {
    final ok = await SupabaseService().deleteAnnouncement(id);
    if (ok && mounted) {
      _showSnackbar('تم حذف البوستر بنجاح');
      _loadBanners();
    }
  }

  Widget _buildBannersPanel() {
    if (!_isMujtaba) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_rounded, size: 48, color: AppTheme.warning),
              const SizedBox(height: 12),
              Text(
                'صلاحية مقيدة',
                style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 6),
              Text(
                'هذا القسم مخصص حصرياً للمشرف العام (مجتبى عواد) لنشر وتحديث بوسترات الواجهة الرئيسية.',
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFF94A3B8)),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primary.withValues(alpha: 0.25),
                  AppTheme.accent.withValues(alpha: 0.12),
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
                const Icon(Icons.photo_library_rounded, color: AppTheme.accent, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'بنل بوسترات وإعلانات الواجهة الرئيسية',
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'يتم رفع الصور والبوسترات مباشرة إلى سيرفر تيليجرام وتخزينها، لتظهر في الكاروسيل بالواجهة الرئيسية لكافة الطلبة.',
                        style: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFFCBD5E1), height: 1.4),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.warning.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppTheme.warning.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          '⭐ صلاحية نشر حصرية: المشرف العام (مجتبى عواد)',
                          style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFFFBBF24)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          Text(
            'نشر بوستر جديد في الواجهة الرئيسية',
            style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 12),

          GestureDetector(
            onTap: _isPickingBannerImage ? null : _pickBannerImage,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _selectedBannerImage != null ? AppTheme.success : AppTheme.lightBorder,
                  width: _selectedBannerImage != null ? 1.5 : 1,
                ),
              ),
              child: _selectedBannerImage == null
                  ? Column(
                      children: [
                        const Icon(Icons.add_photo_alternate_rounded, size: 40, color: AppTheme.primaryLight),
                        const SizedBox(height: 8),
                        Text(
                          'اضغط لاختيار صورة البوستر (JPG, PNG, WEBP)',
                          style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'سيتم رفع الصورة إلى سيرفر تيليجرام وربطها بالواجهة',
                          style: GoogleFonts.cairo(fontSize: 10, color: const Color(0xFF94A3B8)),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.success.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 28),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedBannerImage!.name,
                                style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'الحجم:  • جاهزة للرفع إلى تيليجرام',
                                style: GoogleFonts.cairo(fontSize: 10, color: const Color(0xFF94A3B8)),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: _pickBannerImage,
                          child: Text('تغيير', style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.primaryLight)),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 14),

          TextField(
            controller: _bannerTitleController,
            style: GoogleFonts.cairo(color: AppTheme.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'عنوان الإعلان أو البوستر *',
              labelStyle: GoogleFonts.cairo(color: const Color(0xFF94A3B8), fontSize: 12),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.lightBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.lightBorder)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primaryLight)),
            ),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _bannerContentController,
            maxLines: 2,
            style: GoogleFonts.cairo(color: AppTheme.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'تفاصيل إضافية أو نص التبليغ (اختياري)',
              labelStyle: GoogleFonts.cairo(color: const Color(0xFF94A3B8), fontSize: 12),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.lightBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.lightBorder)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primaryLight)),
            ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedBannerDept,
                  dropdownColor: Colors.white,
                  style: GoogleFonts.cairo(color: AppTheme.textPrimary, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'القسم المستهدف',
                    labelStyle: GoogleFonts.cairo(color: const Color(0xFF94A3B8), fontSize: 11),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.lightBorder)),
                  ),
                  items: ['ALL', ...AppConstants.departments].map((dept) {
                    return DropdownMenuItem(
                      value: dept,
                      child: Text(dept == 'ALL' ? 'كافة الأقسام (عام للكل)' : dept),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedBannerDept = val ?? 'ALL'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedBannerStage,
                  dropdownColor: Colors.white,
                  style: GoogleFonts.cairo(color: AppTheme.textPrimary, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'المرحلة المستهدفة',
                    labelStyle: GoogleFonts.cairo(color: const Color(0xFF94A3B8), fontSize: 11),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.lightBorder)),
                  ),
                  items: ['ALL', ...AppConstants.stages].map((stg) {
                    return DropdownMenuItem(
                      value: stg,
                      child: Text(stg == 'ALL' ? 'كافة المراحل (عام)' : stg),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedBannerStage = val ?? 'ALL'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          ElevatedButton.icon(
            onPressed: _isLoading ? null : _submitBanner,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: _isLoading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.cloud_upload_rounded, color: Colors.white, size: 20),
            label: Text(
              _isLoading ? 'جاري الرفع إلى سيرفر تيليجرام...' : 'رفع ونشر البوستر في الواجهة الرئيسية',
              style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          const SizedBox(height: 28),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'البوسترات النشطة حالياً في الواجهة',
                style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: AppTheme.primaryLight, size: 20),
                onPressed: _loadBanners,
                tooltip: 'تحديث القائمة',
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (_isLoadingBanners)
            const Center(child: CircularProgressIndicator(color: AppTheme.primaryLight))
          else if (_existingBanners.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.lightBorder),
              ),
              child: Center(
                child: Text('لا توجد بوسترات مخصصة حالياً (تُعرض الصور الافتراضية)', style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFF94A3B8))),
              ),
            )
          else
            ..._existingBanners.map((banner) => _buildBannerItem(banner)),
        ],
      ),
    );
  }

  Widget _buildBannerItem(AnnouncementModel banner) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              if (banner.imageUrl != null && banner.imageUrl!.isNotEmpty) {
                AppFullscreenModal.show(
                  context: context,
                  title: banner.title,
                  subtitle: '${banner.department} • ${banner.stage}',
                  imageUrl: banner.imageUrl,
                );
              }
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: banner.imageUrl != null && banner.imageUrl!.isNotEmpty
                  ? AppNetworkImage(
                      imageUrl: banner.imageUrl!,
                      width: 70,
                      height: 50,
                      fit: BoxFit.cover,
                      errorWidget: Container(
                        width: 70,
                        height: 50,
                        color: AppTheme.primary,
                        child: const Icon(Icons.broken_image, color: Colors.white54, size: 20),
                      ),
                    )
                  : Container(width: 70, height: 50, color: AppTheme.primary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  banner.title,
                  style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${banner.department} • ${banner.stage}',
                  style: GoogleFonts.cairo(fontSize: 10, color: const Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'حذف البوستر',
            icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.danger, size: 20),
            onPressed: () => _deleteBanner(banner.id),
          ),
        ],
      ),
    );
  }

}
