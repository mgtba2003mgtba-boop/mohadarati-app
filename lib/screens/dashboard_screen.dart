import 'package:flutter/material.dart';
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
import 'package:file_picker/file_picker.dart';

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
  String _userSearchQuery = '';

  bool _isLoadingDashboard = false;
  List<LectureModel> _allLectures = [];
  List<AnnouncementModel> _allAnnouncements = [];
  List<RepresentativeActivityItem> _activities = [];

  String _activityDeptFilter = 'ALL';
  String _activityStageFilter = 'ALL';
  String _activityTypeFilter = 'ALL';
  String _activitySearchQuery = '';

  String _repDeptFilter = 'ALL';
  String _repStageFilter = 'ALL';
  String _repSearchQuery = '';

  // ── فلاتر دليل الطلاب والممثلين ──
  String _userDirectoryRoleFilter = 'ALL'; // 'ALL', 'REPS', 'STUDENTS'
  String _userDirectoryStageFilter = 'ALL';

  // ── فلاتر مركز إدارة وحذف المحتوى ──
  String _contentFilterType = 'ALL'; // 'ALL', 'lecture', 'announcement', 'banner', 'schedule'
  String _contentDeptFilter = 'ALL';
  String _contentStageFilter = 'ALL';
  String _contentSearchQuery = '';

  int _publishModeIndex = 0; // 0 = محاضرة, 1 = إعلان, 2 = بوستر
  int _moderationSegmentIndex = 0; // 0 = المحتوى والمنشورات, 1 = الطلاب والممثلين

  // ── مواد البصمة لقسم ومرحلة وكورس المحاضرة ──
  String? _selectedBiometricSubject;
  bool _isCustomLectureSubject = false;

  // ── مواد البصمة للإعلان ──
  String? _selectedAnnouncementSubject;

  List<String> get _availableLectureSubjects {
    return BiometricSubjects.getSubjectNames(
      department: _selectedLectureDept,
      stage: _selectedLectureStage,
      semester: 1,
    );
  }

  List<String> get _availableAnnouncementSubjects {
    if (_selectedAnnounceDept == 'ALL' || _selectedAnnounceStage == 'ALL') {
      return [];
    }
    return BiometricSubjects.getSubjectNames(
      department: _selectedAnnounceDept,
      stage: _selectedAnnounceStage,
      semester: 1,
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

    final int tabsCount = _isMujtaba ? 3 : 2;
    int initialTab = 0;
    if (_isMujtaba) {
      if (widget.initialTabIndex == 1) {
        initialTab = 1;
        _publishModeIndex = 1; // نشر إعلان
      } else if (widget.initialTabIndex >= 2) {
        initialTab = 2; // إدارة المحتوى والطلاب
      } else {
        initialTab = 0; // إحصائيات الطلاب والنبض
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

  Future<void> _loadDashboardData({bool forceRefresh = false}) async {
    setState(() => _isLoadingDashboard = true);
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

  Future<void> _loadAllUsers() async {
    final users = await SupabaseService().fetchAllUsers();
    if (mounted) {
      setState(() => _allUsers = users);
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
    const targetSection = 'ALL';

    if (_selectedFile == null) {
      _showSnackbar('يرجى اختيار ملف المحاضرة أولاً (PDF / مستند / صورة)', isError: true);
      return;
    }

    setState(() => _isLoading = true);

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
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

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
    final title = _announcementTitleController.text.trim();
    final content = _announcementContentController.text.trim();
    final subject = _announcementSubjectController.text.trim();

    if (title.isEmpty) {
      _showSnackbar('يرجى إدخال عنوان الإعلان', isError: true);
      return;
    }
    if (content.isEmpty) {
      _showSnackbar('يرجى كتابة تفاصيل الإعلان', isError: true);
      return;
    }

    final targetDept = _currentUser?.isAdmin == true ? _selectedAnnounceDept : (_currentUser?.department ?? _selectedAnnounceDept);
    final targetStage = _currentUser?.isAdmin == true ? _selectedAnnounceStage : (_currentUser?.stage ?? _selectedAnnounceStage);
    final targetSection = _currentUser?.isAdmin == true ? _selectedAnnounceSection : (_currentUser?.section ?? 'ALL');

    setState(() => _isLoading = true);

    final newAnnounce = AnnouncementModel(
      id: '',
      title: title,
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
      setState(() => _isAnnouncePinned = false);
      _showSnackbar('تم نشر الإعلان بنجاح');
      _loadDashboardData(forceRefresh: true);
    } else {
      _showSnackbar('حدث خطأ أثناء نشر الإعلان', isError: true);
    }
  }

  // ── ترقية مستخدم ──────────────────────────────────────────────
  void _showPromoteDialog(AppUserModel user) {
    String selectedRole = user.role;
    bool canLectures = user.canPublishLectures;
    bool canAnnouncements = user.canPublishAnnouncements;
    final sectionController = TextEditingController(text: user.section ?? '');

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.darkCard,
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
                    const Divider(color: AppTheme.darkBorder, height: 20),

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

                    const Divider(color: AppTheme.darkBorder, height: 20),

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
                    if (ok) {
                      _showSnackbar('تم تعديل صلاحيات (${user.name}) بنجاح');
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
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        title: Text(
          _isMujtaba ? 'داش بورد مجتبى (المشرف العام)' : 'لوحة ممثل الدفعة والنشر',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: AppTheme.accent,
          unselectedLabelColor: const Color(0xFF94A3B8),
          indicatorColor: AppTheme.accent,
          labelStyle: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: _isMujtaba
              ? const [
                  Tab(icon: Icon(Icons.analytics_rounded), text: 'إحصائيات الطلاب والنبض'),
                  Tab(icon: Icon(Icons.add_circle_outline_rounded), text: 'مركز النشر والمقررات'),
                  Tab(icon: Icon(Icons.admin_panel_settings_rounded), text: 'إدارة المحتوى والطلاب'),
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
                _buildActivityRadarTab(),
                _buildUnifiedPublishTab(),
                _buildModerationAndDirectoryTab(),
              ]
            : [
                _buildPublishLectureTab(),
                _buildPublishAnnouncementTab(),
              ],
      ),
    );
  }

  // ── مركز النشر الموحد (محاضرات، إعلانات، بوسترات) للمشرف العام ──────────
  Widget _buildUnifiedPublishTab() {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppTheme.darkCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildPublishSegmentButton(
                  index: 0,
                  icon: Icons.upload_file_rounded,
                  label: 'رفع محاضرة',
                ),
              ),
              Expanded(
                child: _buildPublishSegmentButton(
                  index: 1,
                  icon: Icons.campaign_rounded,
                  label: 'نشر إعلان',
                ),
              ),
              Expanded(
                child: _buildPublishSegmentButton(
                  index: 2,
                  icon: Icons.photo_library_rounded,
                  label: 'بوستر الواجهة',
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

  Widget _buildPublishSegmentButton({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _publishModeIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _publishModeIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.black : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.cairo(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.black : const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── مركز إدارة المحتوى والطلاب الموحد (مع شريحة تبديل سريعة) ──────────
  Widget _buildModerationAndDirectoryTab() {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppTheme.darkCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildModerationSegmentButton(
                  index: 0,
                  icon: Icons.auto_stories_rounded,
                  label: 'المحتوى والمنشورات',
                ),
              ),
              Expanded(
                child: _buildModerationSegmentButton(
                  index: 1,
                  icon: Icons.people_alt_rounded,
                  label: 'الطلاب والممثلين',
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _moderationSegmentIndex == 0
              ? _buildContentManagementTab()
              : _buildRepsDirectoryTab(),
        ),
      ],
    );
  }

  Widget _buildModerationSegmentButton({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _moderationSegmentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _moderationSegmentIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.black : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.cairo(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.black : const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
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
                  color: AppTheme.darkCard,
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
                color: AppTheme.darkCard,
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
                                color: AppTheme.success.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'الحجم: ${_formatFileSize(_selectedFileSize)}',
                                style: GoogleFonts.cairo(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.success,
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
              dropdownColor: AppTheme.darkCard,
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
                    dropdownColor: AppTheme.darkCard,
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
                      color: AppTheme.darkCard,
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
            dropdownColor: AppTheme.darkCard,
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
                  ? 'جاري رفع المحاضرة إلى سحابة الكلية والمزامنة...'
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
            controller: _announcementTitleController,
            style: GoogleFonts.cairo(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              labelText: 'عنوان الإعلان أو التبليغ',
              prefixIcon: Icon(Icons.campaign_rounded, color: AppTheme.primaryLight),
            ),
          ),
          const SizedBox(height: 14),

          TextField(
            controller: _announcementContentController,
            maxLines: 4,
            style: GoogleFonts.cairo(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              labelText: 'نص الإعلان بالتفصيل',
              prefixIcon: Icon(Icons.description_rounded, color: AppTheme.primaryLight),
            ),
          ),
          const SizedBox(height: 14),

          // ── 1. النطاق الأكاديمي للإعلان ──
          if (_currentUser?.isAdmin == true) ...[
            DropdownButtonFormField<String>(
              value: _selectedAnnounceDept,
              dropdownColor: AppTheme.darkCard,
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
              dropdownColor: AppTheme.darkCard,
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
              dropdownColor: AppTheme.darkCard,
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
            dropdownColor: AppTheme.darkCard,
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
            dropdownColor: AppTheme.darkCard,
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
              l.stage == _currentUser!.stage &&
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
              color: AppTheme.darkCard,
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
          ...myLectures.map((l) => _buildRecentLectureItemCard(l)),
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
        color: AppTheme.darkCard,
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
                        backgroundColor: AppTheme.darkCard,
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
              a.stage == _currentUser!.stage &&
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
              color: AppTheme.darkCard,
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
          ...myAnnouncements.map((a) => _buildRecentAnnouncementItemCard(a)),
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
        color: AppTheme.darkCard,
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
                        backgroundColor: AppTheme.darkCard,
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
                        backgroundColor: AppTheme.darkCard,
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

  // ══════════════════════════════════════════════════════════════
  // تبويب رادار نشاط الممثلين اللحظي وإحصائيات النظام لمجتبى
  // ══════════════════════════════════════════════════════════════
  Widget _buildActivityRadarTab() {
    final filtered = _activities.where((item) {
      final matchDept = _activityDeptFilter == 'ALL' || item.department == _activityDeptFilter;
      final matchStage = _activityStageFilter == 'ALL' || item.stage == _activityStageFilter;
      final matchType = _activityTypeFilter == 'ALL' || item.type == _activityTypeFilter;
      final q = _activitySearchQuery.trim().toLowerCase();
      final matchSearch = q.isEmpty ||
          item.actorName.toLowerCase().contains(q) ||
          item.title.toLowerCase().contains(q) ||
          item.subjectName.toLowerCase().contains(q) ||
          (item.section != null && item.section!.toLowerCase().contains(q));
      return matchDept && matchStage && matchType && matchSearch;
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      child: ListView(
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
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.darkBorder),
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
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.darkBorder),
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
                    final stageCount = _allUsers.where((u) => u.stage.contains(stage) || stage.contains(u.stage)).length;
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
              fillColor: AppTheme.darkCard,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppTheme.darkBorder),
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
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppTheme.darkCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.darkBorder),
              ),
              child: Center(
                child: Text(
                  'لا توجد عمليات نشر مسجلة تطابق الفلاتر المحددة',
                  style: GoogleFonts.cairo(color: const Color(0xFF94A3B8), fontSize: 13),
                ),
              ),
            )
          else
            ...filtered.map((item) => _buildActivityCard(item)),
        ],
      ),
    );
  }

  Widget _buildActivityCard(RepresentativeActivityItem item) {
    final isLecture = item.type == 'lecture';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
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
                          backgroundColor: AppTheme.darkCard,
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
        backgroundColor: AppTheme.darkCard,
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
      final matchStage = _userDirectoryStageFilter == 'ALL' || user.stage.contains(_userDirectoryStageFilter) || _userDirectoryStageFilter.contains(user.stage);
      final q = _repSearchQuery.trim().toLowerCase();
      final matchSearch = q.isEmpty ||
          user.name.toLowerCase().contains(q) ||
          user.studentId.toLowerCase().contains(q) ||
          (user.section != null && user.section!.toLowerCase().contains(q)) ||
          user.department.toLowerCase().contains(q);
      return matchDept && matchStage && matchSearch;
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      child: ListView(
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
                  AppTheme.darkCard,
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
                        dropdownColor: AppTheme.darkCard,
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
                        dropdownColor: AppTheme.darkCard,
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
                              u.stage == _selectedRepStage &&
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
                                backgroundColor: AppTheme.darkCard,
                                side: BorderSide(color: isSel ? AppTheme.accent : AppTheme.darkBorder),
                                onSelected: (s) {
                                  if (s) setState(() => _selectedRepSection = sec);
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                const Divider(color: AppTheme.darkBorder, height: 24),

                // 3. ممثلو الشعبة الحالية والزر المباشر للتكليف
                Builder(
                  builder: (context) {
                    final currentReps = _allUsers.where((u) =>
                      u.isRepresentative &&
                      u.department == _selectedRepDept &&
                      u.stage == _selectedRepStage &&
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
                              border: Border.all(color: AppTheme.darkBorder),
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
                                  color: AppTheme.darkCard,
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
              Column(
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
              fillColor: AppTheme.darkCard,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppTheme.darkBorder),
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
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppTheme.darkCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.darkBorder),
              ),
              child: Center(
                child: Text(
                  'لم يتم العثور على طلاب أو ممثلين مطابقين للبحث',
                  style: GoogleFonts.cairo(color: const Color(0xFF94A3B8), fontSize: 13),
                ),
              ),
            )
          else
            ...filtered.map((user) => _buildRepCard(user)),
        ],
      ),
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
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAdmin
              ? Colors.greenAccent.withValues(alpha: 0.4)
              : (isRep ? AppTheme.accent.withValues(alpha: 0.4) : AppTheme.darkBorder),
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

          const Divider(color: AppTheme.darkBorder, height: 16),
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
              backgroundColor: AppTheme.darkCard,
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
                          border: Border.all(color: AppTheme.darkBorder),
                        ),
                        child: filteredStudents.isEmpty
                            ? Center(
                                child: Text('لا توجد نتائج مطابقة للبحث',
                                    style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFF94A3B8))),
                              )
                            : ListView.separated(
                                itemCount: filteredStudents.length,
                                separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.darkBorder),
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
        backgroundColor: AppTheme.darkCard,
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

  Future<void> _launchUrlExternal(String? urlString, {required String errorMsg}) async {
    if (urlString == null || urlString.isEmpty) return;
    try {
      final uri = Uri.parse(urlString.trim());
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        _showSnackbar(errorMsg, isError: true);
      }
    } catch (e) {
      if (mounted) {
        _showSnackbar('$errorMsg: $e', isError: true);
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

    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      child: ListView(
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
              fillColor: AppTheme.darkCard,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppTheme.darkBorder),
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
            Container(
              padding: const EdgeInsets.all(36),
              decoration: BoxDecoration(
                color: AppTheme.darkCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.darkBorder),
              ),
              child: Center(
                child: Text(
                  'لا توجد عناصر منشورة تطابق الفلاتر المحددة',
                  style: GoogleFonts.cairo(color: const Color(0xFF94A3B8), fontSize: 13),
                ),
              ),
            )
          else
            ...filtered.map((item) => _buildUnifiedContentCard(item)),
        ],
      ),
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
        color: AppTheme.darkCard,
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
        backgroundColor: AppTheme.darkCard,
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
                color: AppTheme.darkCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _selectedBannerImage != null ? AppTheme.success : AppTheme.darkBorder,
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
              fillColor: AppTheme.darkCard,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.darkBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.darkBorder)),
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
              fillColor: AppTheme.darkCard,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.darkBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.darkBorder)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primaryLight)),
            ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedBannerDept,
                  dropdownColor: AppTheme.darkCard,
                  style: GoogleFonts.cairo(color: AppTheme.textPrimary, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'القسم المستهدف',
                    labelStyle: GoogleFonts.cairo(color: const Color(0xFF94A3B8), fontSize: 11),
                    filled: true,
                    fillColor: AppTheme.darkCard,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.darkBorder)),
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
                  dropdownColor: AppTheme.darkCard,
                  style: GoogleFonts.cairo(color: AppTheme.textPrimary, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'المرحلة المستهدفة',
                    labelStyle: GoogleFonts.cairo(color: const Color(0xFF94A3B8), fontSize: 11),
                    filled: true,
                    fillColor: AppTheme.darkCard,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.darkBorder)),
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
                color: AppTheme.darkCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.darkBorder),
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
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.darkBorder),
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
