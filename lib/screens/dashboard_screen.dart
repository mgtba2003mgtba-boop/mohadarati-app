import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../models/app_user_model.dart';
import '../models/lecture_model.dart';
import '../models/announcement_model.dart';
import '../services/supabase_service.dart';
import '../services/telegram_uploader_service.dart';
import '../widgets/app_network_image.dart';
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
  final _professorNameController = TextEditingController();
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
  String _selectedAnnounceCategory = 'academic';
  bool _isAnnouncePinned = false;

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

    final int tabsCount = _isMujtaba ? 5 : 2;
    _tabController = TabController(
      length: tabsCount,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, tabsCount - 1),
    );

    if (_isMujtaba) {
      _loadDashboardData();
      _loadBanners();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _lectureTitleController.dispose();
    _subjectNameController.dispose();
    _professorNameController.dispose();
    _driveUrlController.dispose();
    _lectureDescController.dispose();
    _announcementTitleController.dispose();
    _announcementContentController.dispose();
    _announcementSubjectController.dispose();
    _bannerTitleController.dispose();
    _bannerContentController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoadingDashboard = true);
    final service = SupabaseService();
    try {
      final results = await Future.wait([
        service.fetchLectures(),
        service.fetchAnnouncements(),
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
          content: a.content,
        ));
      }

      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (mounted) {
        setState(() {
          _activities = items;
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

    if (_uploadDirectFile) {
      if (_selectedFile == null) {
        _showSnackbar('يرجى اختيار ملف المحاضرة أولاً', isError: true);
        return;
      }

      setState(() => _isLoading = true);

      final result = await TelegramUploaderService().uploadLecture(
        file: _selectedFile!,
        title: title,
        subjectName: subject,
        department: targetDept,
        stage: targetStage,
        semester: _selectedLectureSemester,
        lectureType: _selectedLectureType,
        professorName: _professorNameController.text.trim().isNotEmpty ? _professorNameController.text.trim() : null,
        description: _lectureDescController.text.trim().isNotEmpty ? _lectureDescController.text.trim() : null,
        uploaderId: _currentUser?.studentId ?? 'NUST_ADMIN',
        uploaderName: _currentUser?.name ?? 'ممثل الدفعة',
        uploaderRole: _currentUser?.role ?? 'representative',
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (result.success) {
        setState(() => _selectedFile = null);
        _lectureTitleController.clear();
        _subjectNameController.clear();
        _driveUrlController.clear();
        _professorNameController.clear();
        _lectureDescController.clear();
        _showSnackbar('تم رفع ونشر المحاضرة بنجاح');
      } else {
        _showSnackbar(result.message, isError: true);
      }
    } else {
      final driveUrl = _driveUrlController.text.trim();
      if (driveUrl.isEmpty) {
        _showSnackbar('يرجى لصق رابط Google Drive للمحاضرة', isError: true);
        return;
      }
      if (!driveUrl.contains('drive.google.com') && !driveUrl.startsWith('http')) {
        _showSnackbar('تأكد من إدخال رابط Google Drive صحيح يبدأ بـ https://', isError: true);
        return;
      }

      setState(() => _isLoading = true);

      final newLecture = LectureModel(
        id: '',
        title: title,
        subjectName: subject,
        department: targetDept,
        stage: targetStage,
        semester: _selectedLectureSemester,
        type: _selectedLectureType,
        driveUrl: driveUrl,
        description: _lectureDescController.text.trim().isNotEmpty ? _lectureDescController.text.trim() : null,
        professorName: _professorNameController.text.trim().isNotEmpty ? _professorNameController.text.trim() : null,
        uploaderId: _currentUser?.studentId ?? 'NUST_ADMIN',
        uploaderName: _currentUser?.name ?? 'ممثل الدفعة',
        uploaderRole: _currentUser?.role ?? 'representative',
        createdAt: DateTime.now(),
      );

      final success = await SupabaseService().createLecture(newLecture);

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (success) {
        _lectureTitleController.clear();
        _subjectNameController.clear();
        _driveUrlController.clear();
        _professorNameController.clear();
        _lectureDescController.clear();
        _showSnackbar('تم نشر المحاضرة بنجاح');
      } else {
        _showSnackbar('حدث خطأ أثناء حفظ المحاضرة بسيرفر Supabase', isError: true);
      }
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
                      title: 'ممثل الدفعة (Representative)',
                      subtitle: 'صلاحيات نشر المحاضرات والإعلانات',
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
                      title: 'أستاذ مادة (Professor)',
                      subtitle: 'صلاحيات نشر وتعديل المحاضرات',
                      roleValue: AppConstants.roleProfessor,
                      groupValue: selectedRole,
                      onChanged: (val) {
                        setDialogState(() {
                          selectedRole = val!;
                          canLectures = true;
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
                      title: Text('صلاحية نشر المحاضرات (Google Drive)', style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textPrimary)),
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
                  Tab(icon: Icon(Icons.radar_rounded), text: 'رادار نشاط الممثلين'),
                  Tab(icon: Icon(Icons.badge_rounded), text: 'ممثلو الشعب والمراحل'),
                  Tab(icon: Icon(Icons.auto_stories_rounded), text: 'إدارة المحتوى'),
                  Tab(icon: Icon(Icons.photo_library_rounded), text: 'بوسترات الواجهة'),
                  Tab(icon: Icon(Icons.campaign_rounded), text: 'نشر مركزي'),
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
                _buildRepsDirectoryTab(),
                _buildContentManagementTab(),
                _buildBannersPanel(),
                _buildCentralPublishTab(),
              ]
            : [
                _buildPublishLectureTab(),
                _buildPublishAnnouncementTab(),
              ],
      ),
    );
  }

  // ── تبويب 1: نشر المحاضرات (رفع مباشر من الجهاز أو Google Drive) ─
  Widget _buildPublishLectureTab() {
    final isVideo = _selectedFile != null &&
        ['mp4', 'mkv', 'avi', 'mov'].contains(_selectedFile!.extension?.toLowerCase());

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
                        'يمكنك رفع ملفات الفيديو والمستندات مباشرة من جهازك، وسيتم تخزينها وبثها للطلبة فوراً داخل التطبيق دون أي تحويل لخارج المنظومة.',
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
          const SizedBox(height: 16),

          // ── شريط اختيار طريقة النشر: رفع ملف مباشر vs رابط خارجي ──
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _uploadDirectFile = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _uploadDirectFile ? AppTheme.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.upload_file_rounded,
                            size: 18,
                            color: _uploadDirectFile ? Colors.white : AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'رفع ملف من الجهاز',
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _uploadDirectFile ? Colors.white : AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _uploadDirectFile = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: !_uploadDirectFile ? AppTheme.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_to_drive_rounded,
                            size: 18,
                            color: !_uploadDirectFile ? Colors.white : AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'رابط Google Drive',
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: !_uploadDirectFile ? Colors.white : AppTheme.textSecondary,
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
          const SizedBox(height: 18),

          // ── مساحة اختيار أو عرض الملف المختار (في حال الرفع المباشر) ──
          if (_uploadDirectFile) ...[
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
                        'يدعم ملفات الفيديو (MP4, MKV) والمستندات (PDF, Word, PowerPoint) بحجم يصل حتى 2GB',
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
                        color: isVideo
                            ? AppTheme.accent.withValues(alpha: 0.2)
                            : AppTheme.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isVideo ? Icons.video_file_rounded : Icons.description_rounded,
                        color: isVideo ? AppTheme.accent : AppTheme.primaryLight,
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
                                isVideo ? 'فيديو تدفق مباشر' : 'مستند دراسي',
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
          ],

          // ── حقل رابط Google Drive (فقط عند اختيار الوضع الخارجي) ──
          if (!_uploadDirectFile) ...[
            TextField(
              controller: _driveUrlController,
              style: GoogleFonts.cairo(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: 'رابط Google Drive للمحاضرة',
                hintText: 'https://drive.google.com/file/d/.../view',
                prefixIcon: const Icon(Icons.add_to_drive_rounded, color: AppTheme.accent),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.open_in_new_rounded, color: AppTheme.primaryLight),
                  tooltip: 'تجربة الرابط',
                  onPressed: () async {
                    final url = _driveUrlController.text.trim();
                    if (url.isNotEmpty && await canLaunchUrl(Uri.parse(url))) {
                      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                    } else {
                      _showSnackbar('الرابط غير صالح للتجربة', isError: true);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],

          // ── الحقول المشتركة ──
          TextField(
            controller: _lectureTitleController,
            style: GoogleFonts.cairo(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              labelText: 'عنوان المحاضرة (مثال: المحاضرة 1 - مقدمة في الدوائر)',
              prefixIcon: Icon(Icons.title_rounded, color: AppTheme.primaryLight),
            ),
          ),
          const SizedBox(height: 14),

          TextField(
            controller: _subjectNameController,
            style: GoogleFonts.cairo(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              labelText: 'اسم المادة الدراسية (مثال: أجهزة طبية، شبكات، برمجيات)',
              prefixIcon: Icon(Icons.book_rounded, color: AppTheme.primaryLight),
            ),
          ),
          const SizedBox(height: 14),

          TextField(
            controller: _professorNameController,
            style: GoogleFonts.cairo(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              labelText: 'اسم أستاذ المادة (اختياري)',
              prefixIcon: Icon(Icons.person_outline_rounded, color: AppTheme.primaryLight),
            ),
          ),
          const SizedBox(height: 14),

          if (_currentUser?.isAdmin == true) ...[
            // اختيار القسم
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
              onChanged: (val) => setState(() => _selectedLectureDept = val!),
            ),
            const SizedBox(height: 14),

            // اختيار المرحلة والكورس
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
                    onChanged: (val) => setState(() => _selectedLectureStage = val!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _selectedLectureSemester,
                    dropdownColor: AppTheme.darkCard,
                    style: GoogleFonts.cairo(color: AppTheme.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'الكورس / الفصل',
                    ),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('الكورس 1')),
                      DropdownMenuItem(value: 2, child: Text('الكورس 2')),
                    ],
                    onChanged: (val) => setState(() => _selectedLectureSemester = val!),
                  ),
                ),
              ],
            ),
          ] else ...[
            // نطاق النشر مقيد بشعبة ممثل الدفعة
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.darkCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_rounded, color: AppTheme.accent, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'نطاق النشر مقيد بصفك وشعبتك حصراً',
                          style: GoogleFonts.cairo(fontSize: 10, color: const Color(0xFF94A3B8)),
                        ),
                        Text(
                          '${_currentUser?.department ?? _selectedLectureDept} • ${_currentUser?.stage ?? _selectedLectureStage}',
                          style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                      ],
                    ),
                  ),
                  DropdownButton<int>(
                    value: _selectedLectureSemester,
                    dropdownColor: AppTheme.darkCard,
                    style: GoogleFonts.cairo(color: AppTheme.textPrimary, fontSize: 12),
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('الكورس 1')),
                      DropdownMenuItem(value: 2, child: Text('الكورس 2')),
                    ],
                    onChanged: (val) => setState(() => _selectedLectureSemester = val!),
                  ),
                ],
              ),
            ),
          ],
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

          TextField(
            controller: _announcementSubjectController,
            style: GoogleFonts.cairo(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              labelText: 'اسم المادة الدراسية (اختياري - لربط الإعلان بصفحة المادة)',
              prefixIcon: Icon(Icons.menu_book_rounded, color: AppTheme.primaryLight),
            ),
          ),
          const SizedBox(height: 14),

          if (_currentUser?.isAdmin == true) ...[
            DropdownButtonFormField<String>(
              value: _selectedAnnounceDept,
              dropdownColor: AppTheme.darkCard,
              style: GoogleFonts.cairo(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'القسم الموجه له الإعلان',
              ),
              items: [
                const DropdownMenuItem(value: 'ALL', child: Text('كافة أقسام الكلية الموحدة')),
                ...AppConstants.departments.map((d) => DropdownMenuItem(value: d, child: Text(d))),
              ],
              onChanged: (val) => setState(() => _selectedAnnounceDept = val!),
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
              onChanged: (val) => setState(() => _selectedAnnounceStage = val!),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.darkCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_rounded, color: AppTheme.accent, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'نطاق الإعلان موجه لطلبة صفك حصراً',
                          style: GoogleFonts.cairo(fontSize: 10, color: const Color(0xFF94A3B8)),
                        ),
                        Text(
                          '${_currentUser?.department ?? _selectedAnnounceDept} • ${_currentUser?.stage ?? _selectedAnnounceStage}',
                          style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ],
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
          // ── لوحة المؤشرات والإحصائيات الحيوية للنظام ──
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
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.hub_rounded, color: AppTheme.accent, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          'نبض المنظومة وإحصائيات الكلية',
                          style: GoogleFonts.cairo(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, color: AppTheme.accent, size: 20),
                      tooltip: 'تحديث فوري',
                      onPressed: _loadDashboardData,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricMiniCard(
                        title: 'الطلبة',
                        value: '${_allUsers.length}',
                        icon: Icons.people_alt_rounded,
                        color: AppTheme.primaryLight,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildMetricMiniCard(
                        title: 'ممثلو الشعب',
                        value: '${_representatives.length}',
                        icon: Icons.badge_rounded,
                        color: AppTheme.accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildMetricMiniCard(
                        title: 'المحاضرات',
                        value: '${_allLectures.length}',
                        icon: Icons.menu_book_rounded,
                        color: Colors.purpleAccent,
                      ),
                    ),
                    const SizedBox(width: 8),
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
              ],
            ),
          ),
          const SizedBox(height: 16),

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
                    onPressed: () => _launchUrlExternal(item.streamUrl ?? item.driveUrl, errorMsg: 'تعذر فتح الملف'),
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
  // تبويب دليل وإدارة ممثلي الشعب والمراحل لمجتبى
  // ══════════════════════════════════════════════════════════════
  Widget _buildRepsDirectoryTab() {
    final filtered = _representatives.where((rep) {
      final matchDept = _repDeptFilter == 'ALL' || rep.department == _repDeptFilter;
      final matchStage = _repStageFilter == 'ALL' || rep.stage == _repStageFilter;
      final q = _repSearchQuery.trim().toLowerCase();
      final matchSearch = q.isEmpty ||
          rep.name.toLowerCase().contains(q) ||
          rep.studentId.toLowerCase().contains(q) ||
          (rep.section != null && rep.section!.toLowerCase().contains(q));
      return matchDept && matchStage && matchSearch;
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // زر تكليف ممثل جديد
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'دليل ممثلي الشعب والمراحل',
                    style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                  Text(
                    '${filtered.length} ممثلين نشطين في المنظومة',
                    style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.accent),
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.person_add_rounded, color: Colors.black, size: 18),
                label: Text(
                  'تكليف ممثل جديد',
                  style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
                ),
                onPressed: _showAssignNewRepDialog,
              ),
            ],
          ),
          const SizedBox(height: 14),

          // شريط البحث
          TextField(
            style: GoogleFonts.cairo(color: AppTheme.textPrimary, fontSize: 13),
            onChanged: (val) => setState(() => _repSearchQuery = val),
            decoration: InputDecoration(
              hintText: 'ابحث عن ممثل أو شعبة أو قسم...',
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
                  'لم يتم العثور على ممثلين مطابقين للبحث',
                  style: GoogleFonts.cairo(color: const Color(0xFF94A3B8), fontSize: 13),
                ),
              ),
            )
          else
            ...filtered.map((rep) => _buildRepCard(rep)),
        ],
      ),
    );
  }

  Widget _buildRepCard(AppUserModel rep) {
    final lectureCount = _allLectures.where((l) => l.uploaderId == rep.studentId).length;
    final announceCount = _allAnnouncements.where((a) => a.authorId == rep.studentId).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppTheme.accent.withValues(alpha: 0.2),
                child: Text(
                  rep.name.isNotEmpty ? rep.name[0] : 'R',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: AppTheme.accent),
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
                            color: AppTheme.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            'شعبة ${rep.section ?? 'عامة'}',
                            style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.accent),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${rep.studentId} • ${rep.department} (${rep.stage})',
                      style: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ),
            ],
          ),
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

          const Divider(color: AppTheme.darkBorder, height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
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
            ],
          ),
        ],
      ),
    );
  }

  void _showAssignNewRepDialog() {
    String? selectedStudentId;
    String selectedDept = AppConstants.departments.first;
    String selectedStage = AppConstants.stages.first;
    final sectionController = TextEditingController(text: 'A');
    bool canLectures = true;
    bool canAnnouncements = true;
    String searchFilter = '';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final availableStudents = _allUsers.where((u) {
              if (selectedStudentId == u.studentId) return true;
              final q = searchFilter.trim().toLowerCase();
              if (q.isEmpty) return true;
              return u.name.toLowerCase().contains(q) || u.studentId.toLowerCase().contains(q);
            }).toList();

            return AlertDialog(
              backgroundColor: AppTheme.darkCard,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(
                'تكليف ممثل جديد لشعبة',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textPrimary),
              ),
              content: SizedBox(
                width: 400,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('اختر الطالب المراد تكليفه:', style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFFCBD5E1))),
                      const SizedBox(height: 6),
                      TextField(
                        style: GoogleFonts.cairo(color: AppTheme.textPrimary, fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'ابحث بالاسم أو الرقم الجامعي...',
                          hintStyle: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFF64748B)),
                          prefixIcon: const Icon(Icons.search, size: 18, color: AppTheme.accent),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          filled: true,
                          fillColor: Colors.black.withValues(alpha: 0.2),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onChanged: (val) => setDialogState(() => searchFilter = val),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            dropdownColor: AppTheme.darkCard,
                            hint: Text('اختر الطالب من القائمة', style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFF94A3B8))),
                            value: selectedStudentId,
                            items: availableStudents.map((st) {
                              return DropdownMenuItem<String>(
                                value: st.studentId,
                                child: Text('${st.name} (${st.studentId})', style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textPrimary)),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                final st = _allUsers.firstWhere((u) => u.studentId == val);
                                setDialogState(() {
                                  selectedStudentId = val;
                                  selectedDept = st.department.isNotEmpty ? st.department : selectedDept;
                                  selectedStage = st.stage.isNotEmpty ? st.stage : selectedStage;
                                  if (st.section != null && st.section!.isNotEmpty) {
                                    sectionController.text = st.section!;
                                  }
                                });
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      Text('القسم الأكاديمي:', style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFFCBD5E1))),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        dropdownColor: AppTheme.darkCard,
                        value: selectedDept,
                        style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textPrimary),
                        items: AppConstants.departments.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                        onChanged: (val) => setDialogState(() => selectedDept = val!),
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 10),

                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('المرحلة:', style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFFCBD5E1))),
                                const SizedBox(height: 4),
                                DropdownButtonFormField<String>(
                                  dropdownColor: AppTheme.darkCard,
                                  value: selectedStage,
                                  style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textPrimary),
                                  items: AppConstants.stages.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                                  onChanged: (val) => setDialogState(() => selectedStage = val!),
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('الشعبة (A, B, C...):', style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFFCBD5E1))),
                                const SizedBox(height: 4),
                                TextField(
                                  controller: sectionController,
                                  style: GoogleFonts.cairo(color: AppTheme.textPrimary, fontSize: 12),
                                  decoration: InputDecoration(
                                    hintText: 'A / B / C',
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('صلاحية نشر المحاضرات', style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textPrimary)),
                        value: canLectures,
                        activeColor: AppTheme.primaryLight,
                        onChanged: (v) => setDialogState(() => canLectures = v),
                      ),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('صلاحية نشر التبليغات', style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textPrimary)),
                        value: canAnnouncements,
                        activeColor: AppTheme.accent,
                        onChanged: (v) => setDialogState(() => canAnnouncements = v),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('إلغاء', style: GoogleFonts.cairo(color: const Color(0xFF94A3B8))),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
                  onPressed: () async {
                    if (selectedStudentId == null) {
                      _showSnackbar('يرجى اختيار طالب أولاً', isError: true);
                      return;
                    }
                    Navigator.pop(ctx);
                    final ok = await SupabaseService().updateUserRole(
                      studentId: selectedStudentId!,
                      role: AppConstants.roleRepresentative,
                      canPublishLectures: canLectures,
                      canPublishAnnouncements: canAnnouncements,
                      section: sectionController.text.trim().toUpperCase(),
                      stage: selectedStage,
                      department: selectedDept,
                    );
                    if (ok) {
                      _showSnackbar('تم تكليف ممثل الشعبة بنجاح');
                      _loadDashboardData();
                    } else {
                      _showSnackbar('فشل تكليف الممثل', isError: true);
                    }
                  },
                  child: Text('تكليف رسمي', style: GoogleFonts.cairo(color: Colors.black, fontWeight: FontWeight.bold)),
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
      final ok = await SupabaseService().updateUserRole(
        studentId: rep.studentId,
        role: AppConstants.roleStudent,
        canPublishLectures: false,
        canPublishAnnouncements: false,
      );
      if (ok) {
        _showSnackbar('تم سحب التكليف بنجاح');
        _loadDashboardData();
      }
    }
  }

  Widget _buildCentralPublishTab() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: AppTheme.darkCard,
            child: TabBar(
              labelColor: AppTheme.accent,
              unselectedLabelColor: const Color(0xFF94A3B8),
              indicatorColor: AppTheme.accent,
              labelStyle: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12),
              tabs: const [
                Tab(icon: Icon(Icons.campaign_rounded, size: 18), text: 'إعلان مركزي'),
                Tab(icon: Icon(Icons.upload_file_rounded, size: 18), text: 'محاضرة مركزية'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildPublishAnnouncementTab(),
                _buildPublishLectureTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserManagementTab() {
    return _buildRepsDirectoryTab();
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

  // ── تبويب 4: إدارة المحتوى المنشور (حذف وتعديل) ───────────────
  Widget _buildContentManagementTab() {
    return FutureBuilder<List<LectureModel>>(
      future: SupabaseService().fetchLectures(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primaryLight));
        }
        final lectures = snapshot.data!;
        if (lectures.isEmpty) {
          return Center(
            child: Text('لا توجد محاضرات منشورة لإدارتها', style: GoogleFonts.cairo(color: const Color(0xFF94A3B8))),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(14),
          itemCount: lectures.length,
          itemBuilder: (context, index) {
            final item = lectures[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.darkCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.darkBorder),
              ),
              child: ListTile(
                title: Text(item.title, style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                subtitle: Text('${item.subjectName} • ${item.department}', style: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFF94A3B8))),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.danger),
                  onPressed: () async {
                    final ok = await SupabaseService().deleteLecture(item.id);
                    if (ok) {
                      setState(() {});
                      _showSnackbar('تم حذف المحاضرة');
                    }
                  },
                ),
              ),
            );
          },
        );
      },
    );
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

    final newBanner = AnnouncementModel(
      id: '',
      title: title,
      content: _bannerContentController.text.trim().isNotEmpty
          ? _bannerContentController.text.trim()
          : 'إعلان وبوستر رسمي في الواجهة الرئيسية',
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
          ClipRRect(
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
                  ' • ',
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
