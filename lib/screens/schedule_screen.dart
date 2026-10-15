import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../models/app_user_model.dart';
import '../models/schedule_model.dart';
import '../services/supabase_service.dart';
import '../widgets/app_icon_badge.dart';
import '../widgets/app_media_preview_modal.dart';
import 'package:file_picker/file_picker.dart';
import '../services/telegram_uploader_service.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  AppUserModel? _user;
  List<ScheduleModel> _schedules = [];

  // ── فلاتر المشرف العام لمراقبة جداول كافة الأقسام والشُعب ─────────
  String _supervisorDept = 'ALL';
  String _supervisorStage = 'ALL';
  String _supervisorSection = 'ALL';

  // ── فلتر الشعبة السريع لعرض وفصل منشورات الكروبات ──────────
  String _selectedScheduleSection = 'ALL';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final user = SupabaseService().currentUser;
    if (user != null && !user.isAdmin && user.section != null && user.section!.isNotEmpty) {
      _selectedScheduleSection = user.section!;
    }
    _loadSchedules();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSchedules({bool forceRefresh = false}) async {
    setState(() => _isLoading = true);
    final service = SupabaseService();
    _user = service.currentUser;

    if (_user != null) {
      final isAdmin = _user!.isAdmin;
      final dept = isAdmin ? _supervisorDept : _user!.department;
      final stage = isAdmin ? _supervisorStage : _user!.stage;
      final section = isAdmin ? (_supervisorSection == 'ALL' ? null : _supervisorSection) : null;

      _schedules = await service.fetchSchedules(
        department: dept,
        stage: stage,
        section: section,
        forceRefresh: forceRefresh,
      );
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  List<ScheduleModel> _getFilteredSchedules(String type) {
    return _schedules.where((s) {
      if (s.type != type) return false;
      if (_selectedScheduleSection == 'ALL') return true;
      if (_selectedScheduleSection == 'UNIFIED') return s.isUnified;
      return s.section.toUpperCase() == _selectedScheduleSection.toUpperCase() || s.isUnified;
    }).toList();
  }

  int _countSchedulesForSection(String type, String sectionKey) {
    return _schedules.where((s) {
      if (s.type != type) return false;
      if (sectionKey == 'ALL') return true;
      if (sectionKey == 'UNIFIED') return s.isUnified;
      return s.section.toUpperCase() == sectionKey.toUpperCase();
    }).length;
  }

  Future<void> _launchUrl(String? url) async {
    if (url == null || url.trim().isEmpty) return;
    final uri = Uri.parse(url.trim());
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  String _resolveUrl(String? url) {
    if (url == null || url.trim().isEmpty) return '';
    return AppConstants.resolveImageUrl(url);
  }

  void _openFullscreenViewer(String imageUrl, String title) {
    final resolvedUrl = _resolveUrl(imageUrl);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: const Color(0xFF0F172A),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1E293B),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 26),
              tooltip: 'إغلاق',
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              title,
              style: GoogleFonts.cairo(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.download_rounded, color: Colors.white),
                tooltip: 'تنزيل',
                onPressed: () => _launchUrl(resolvedUrl),
              ),
            ],
          ),
          body: SizedBox.expand(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 6.0,
              child: Center(
                child: Image.network(
                  resolvedUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2.5),
                          const SizedBox(height: 14),
                          Text('جاري فتح الصورة...', style: GoogleFonts.cairo(color: Colors.white70, fontSize: 13)),
                        ],
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.broken_image_rounded, color: Colors.white54, size: 54),
                          const SizedBox(height: 14),
                          Text(
                            'تعذر تحميل الصورة داخل المعاينة',
                            style: GoogleFonts.cairo(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 18),
                          ElevatedButton.icon(
                            onPressed: () => _launchUrl(resolvedUrl),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.open_in_browser_rounded, size: 18, color: Colors.white),
                            label: Text('فتح في المتصفح / تنزيل مباشر', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showUploadScheduleDialog() {
    final titleController = TextEditingController(text: 'جدول المحاضرات الأسبوعي');
    final urlController = TextEditingController();
    String type = _tabController.index == 0 ? 'lectures' : 'exams';
    PlatformFile? selectedFile;
    int selectedFileSize = 0;
    bool isPicking = false;
    bool isUploading = false;
    final isAdmin = _user?.isAdmin == true;
    String targetSection = isAdmin ? 'ALL' : (_user?.section ?? 'A');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
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
                child: const Icon(Icons.cloud_upload_rounded, color: AppTheme.primary, size: 22),
              ),
              const SizedBox(width: 10),
              Text(
                'رفع / تحديث الجدول الأكاديمي',
                style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'نوع الجدول:',
                  style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('جدول محاضرات'),
                      selected: type == 'lectures',
                      onSelected: (s) => setDlgState(() {
                        type = 'lectures';
                        if (titleController.text.contains('امتحانات')) {
                          titleController.text = 'جدول المحاضرات الأسبوعي';
                        }
                      }),
                      selectedColor: AppTheme.primary,
                      labelStyle: GoogleFonts.cairo(
                        color: type == 'lectures' ? Colors.white : AppTheme.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('جدول امتحانات'),
                      selected: type == 'exams',
                      onSelected: (s) => setDlgState(() {
                        type = 'exams';
                        if (titleController.text.contains('محاضرات')) {
                          titleController.text = 'جدول الامتحانات الفصلية';
                        }
                      }),
                      selectedColor: AppTheme.primary,
                      labelStyle: GoogleFonts.cairo(
                        color: type == 'exams' ? Colors.white : AppTheme.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // الشعبة المستهدفة: اختيار للمشرف، قفل تلقائي للممثل
                if (isAdmin) ...[
                  Text(
                    'الشعبة المستهدفة:',
                    style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: targetSection,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppTheme.lightSurface,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppTheme.lightBorder),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'ALL', child: Text('عام (لكل الشُعب - موحد)')),
                      DropdownMenuItem(value: 'A', child: Text('شعبة A')),
                      DropdownMenuItem(value: 'B', child: Text('شعبة B')),
                      DropdownMenuItem(value: 'C', child: Text('شعبة C')),
                      DropdownMenuItem(value: 'D', child: Text('شعبة D')),
                    ],
                    onChanged: (val) {
                      if (val != null) setDlgState(() => targetSection = val);
                    },
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.primarySubtle,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.primary.withValues(alpha: 0.18)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lock_rounded, size: 16, color: AppTheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'الشعبة المستهدفة: شعبة ${_user?.section ?? "A"} (قفل تلقائي)',
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),

                // زر اختيار الملف من الجهاز للرفع المباشر إلى سيرفر تيليجرام
                Text(
                  'ملف أو صورة الجدول:',
                  style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: isPicking || isUploading
                      ? null
                      : () async {
                          setDlgState(() => isPicking = true);
                          final f = await TelegramUploaderService().pickImageOrPdfFile();
                          if (f != null) {
                            final size = await TelegramUploaderService().getFileSize(f);
                            setDlgState(() {
                              selectedFile = f;
                              selectedFileSize = size;
                              isPicking = false;
                              if (titleController.text.isEmpty) {
                                final clean = f.name.contains('.') ? f.name.substring(0, f.name.lastIndexOf('.')) : f.name;
                                titleController.text = clean;
                              }
                            });
                          } else {
                            setDlgState(() => isPicking = false);
                          }
                        },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: selectedFile != null ? AppTheme.success.withValues(alpha: 0.08) : AppTheme.lightSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selectedFile != null ? AppTheme.success : AppTheme.lightBorder,
                        width: selectedFile != null ? 1.5 : 1,
                      ),
                    ),
                    child: selectedFile == null
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.add_photo_alternate_rounded, color: AppTheme.primary, size: 22),
                              const SizedBox(width: 8),
                              Text(
                                isPicking ? 'جاري الفتح...' : 'اختر صورة الجدول أو ملف PDF من جهازك',
                                style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Icon(
                                selectedFile!.name.toLowerCase().endsWith('.pdf') ? Icons.picture_as_pdf_rounded : Icons.image_rounded,
                                color: AppTheme.success,
                                size: 26,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      selectedFile!.name,
                                      style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      ' KB • يعتمد سيرفر تيليجرام',
                                      style: GoogleFonts.cairo(fontSize: 10, color: AppTheme.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              TextButton(
                                onPressed: () => setDlgState(() => selectedFile = null),
                                child: Text('إلغاء', style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.danger)),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 14),

                TextField(
                  controller: titleController,
                  style: GoogleFonts.cairo(color: AppTheme.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'عنوان وتسمية الجدول',
                    filled: true,
                    fillColor: AppTheme.lightSurface,
                  ),
                ),
                const SizedBox(height: 10),

                if (selectedFile == null)
                  TextField(
                    controller: urlController,
                    style: GoogleFonts.cairo(color: AppTheme.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'أو الصق رابط مباشر / درايف',
                      hintText: 'https://...',
                      hintStyle: GoogleFonts.cairo(color: AppTheme.textMuted, fontSize: 11),
                      prefixIcon: const Icon(Icons.link_rounded, color: AppTheme.primary),
                      filled: true,
                      fillColor: AppTheme.lightSurface,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isUploading ? null : () => Navigator.pop(ctx),
              child: Text('إلغاء', style: GoogleFonts.cairo(color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              onPressed: isUploading
                  ? null
                  : () async {
                      final title = titleController.text.trim();
                      if (title.isEmpty) return;

                      String? finalFileUrl = urlController.text.trim().isNotEmpty ? urlController.text.trim() : null;
                      int? telegramMsgId;

                      if (selectedFile != null) {
                        setDlgState(() => isUploading = true);
                        final uploadRes = await TelegramUploaderService().uploadFileToTelegram(
                          file: selectedFile!,
                          fileType: 'schedule',
                          caption: title,
                        );

                        if (!uploadRes.success || uploadRes.fileUrl == null) {
                          setDlgState(() => isUploading = false);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(uploadRes.message, style: GoogleFonts.cairo()),
                                backgroundColor: AppTheme.danger,
                              ),
                            );
                          }
                          return;
                        }
                        finalFileUrl = uploadRes.fileUrl;
                        telegramMsgId = uploadRes.telegramMessageId;
                      }

                      final schedule = ScheduleModel(
                        id: '',
                        title: title,
                        type: type,
                        department: _user?.department ?? 'ALL',
                        stage: _user?.stage ?? 'ALL',
                        section: targetSection,
                        fileUrl: finalFileUrl,
                        fileName: selectedFile?.name ?? title,
                        uploaderName: _user?.name ?? 'المشرف',
                        uploaderId: _user?.studentId,
                        telegramMessageId: telegramMsgId,
                        createdAt: DateTime.now(),
                      );

                      Navigator.pop(ctx);
                      final ok = await SupabaseService().createSchedule(schedule);
                      if (ok && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('تم رفع وحفظ الجدول في سيرفر تيليجرام بنجاح', style: GoogleFonts.cairo()),
                            backgroundColor: AppTheme.success,
                          ),
                        );
                        _loadSchedules();
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              child: isUploading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text('رفع ونشر الجدول', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPublish = _user?.canManageLectures == true || _user?.isAdmin == true;

    return Scaffold(
      backgroundColor: AppTheme.lightBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: Row(
          children: [
            AppIconBadge.amber(
              icon: Icons.calendar_month_rounded,
              size: 40,
              iconSize: 22,
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'الجدول الدراسي والامتحاني',
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
          if (canPublish)
            IconButton(
              icon: const Icon(Icons.add_photo_alternate_rounded, color: AppTheme.primary),
              tooltip: 'رفع جدول',
              onPressed: _showUploadScheduleDialog,
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary),
            tooltip: 'تحديث الجدول',
            onPressed: () => _loadSchedules(forceRefresh: true),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Container(
            height: 42,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppTheme.lightSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.lightBorder.withValues(alpha: 0.6)),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: AppTheme.primary,
              unselectedLabelColor: const Color(0xFF64748B),
              indicator: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(9),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 1.5),
                  ),
                ],
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelStyle: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12),
              unselectedLabelStyle: GoogleFonts.cairo(fontWeight: FontWeight.w600, fontSize: 12),
              tabs: const [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_today_rounded, size: 15),
                      SizedBox(width: 8),
                      Text('المحاضرات الأسبوعية'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.assignment_rounded, size: 15),
                      SizedBox(width: 8),
                      Text('جدول الامتحانات'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : Column(
              children: [
                if (_user?.isAdmin == true) _buildSupervisorBar(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildLecturesScheduleTab(),
                      _buildExamsScheduleTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSupervisorBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.admin_panel_settings_rounded, color: Color(0xFFF59E0B), size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'مراقبة الجداول الأكاديمية (إشراف عام)',
                          style: GoogleFonts.cairo(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFFF59E0B), width: 0.6),
                          ),
                          child: Text(
                            'المشرف العام',
                            style: GoogleFonts.cairo(color: const Color(0xFFFBBF24), fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'استعراض جداول المحاضرات والامتحانات لكافة المراحل والشُعب',
                      style: GoogleFonts.cairo(color: Colors.white70, fontSize: 10),
                    ),
                  ],
                ),
              ),
              if (_supervisorDept != 'ALL' || _supervisorStage != 'ALL' || _supervisorSection != 'ALL')
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _supervisorDept = 'ALL';
                      _supervisorStage = 'ALL';
                      _supervisorSection = 'ALL';
                    });
                    _loadSchedules();
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.restart_alt_rounded, size: 14, color: Color(0xFFFBBF24)),
                  label: Text(
                    'عرض الكل',
                    style: GoogleFonts.cairo(color: const Color(0xFFFBBF24), fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 4,
                child: _buildSupervisorDropdown(
                  label: 'القسم',
                  value: _supervisorDept,
                  items: [
                    const DropdownMenuItem(value: 'ALL', child: Text('كافة الأقسام 🌐', overflow: TextOverflow.ellipsis)),
                    ...AppConstants.departments.map((d) => DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _supervisorDept = val);
                      _loadSchedules();
                    }
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 3,
                child: _buildSupervisorDropdown(
                  label: 'المرحلة',
                  value: _supervisorStage,
                  items: [
                    const DropdownMenuItem(value: 'ALL', child: Text('كل المراحل', overflow: TextOverflow.ellipsis)),
                    ...AppConstants.stages.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _supervisorStage = val);
                      _loadSchedules();
                    }
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 3,
                child: _buildSupervisorDropdown(
                  label: 'الشعبة',
                  value: _supervisorSection,
                  items: const [
                    DropdownMenuItem(value: 'ALL', child: Text('كل الشُعب', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'A', child: Text('شعبة A')),
                    DropdownMenuItem(value: 'B', child: Text('شعبة B')),
                    DropdownMenuItem(value: 'C', child: Text('شعبة C')),
                    DropdownMenuItem(value: 'D', child: Text('شعبة D')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _supervisorSection = val);
                      _loadSchedules();
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSupervisorDropdown({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: const Color(0xFF1E293B),
          icon: const Icon(Icons.arrow_drop_down_rounded, color: Colors.white70, size: 18),
          style: GoogleFonts.cairo(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // تبويبات الجداول (عرض مباشر ملء الشاشة)
  // ══════════════════════════════════════════════════════════════
  Widget _buildLecturesScheduleTab() => _buildScheduleTabContent('lectures');
  Widget _buildExamsScheduleTab() => _buildScheduleTabContent('exams');

  Widget _buildScheduleTabContent(String type) {
    final schedules = _getFilteredSchedules(type);

    return RefreshIndicator(
      onRefresh: _loadSchedules,
      color: AppTheme.primary,
      child: Column(
        children: [
          // شريط أزرار تصفية الشُعب لفصل منشورات الكروبات
          Container(
            height: 38,
            margin: const EdgeInsets.fromLTRB(0, 10, 0, 4),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildScheduleSectionChip(type, 'ALL', 'الكل 🌐', _countSchedulesForSection(type, 'ALL')),
                const SizedBox(width: 6),
                _buildScheduleSectionChip(type, 'A', 'شعبة A', _countSchedulesForSection(type, 'A')),
                const SizedBox(width: 6),
                _buildScheduleSectionChip(type, 'B', 'شعبة B', _countSchedulesForSection(type, 'B')),
                const SizedBox(width: 6),
                _buildScheduleSectionChip(type, 'C', 'شعبة C', _countSchedulesForSection(type, 'C')),
                const SizedBox(width: 6),
                _buildScheduleSectionChip(type, 'D', 'شعبة D', _countSchedulesForSection(type, 'D')),
                const SizedBox(width: 6),
                _buildScheduleSectionChip(type, 'UNIFIED', 'موحد لجميع الشُعب 📋', _countSchedulesForSection(type, 'UNIFIED')),
              ],
            ),
          ),

          Expanded(
            child: schedules.isEmpty
                ? SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: MediaQuery.of(context).size.height * 0.6,
                      child: _buildEmptyScheduleState(isExam: type == 'exams'),
                    ),
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                    itemCount: schedules.length,
                    itemBuilder: (context, index) => _buildScheduleFileCard(schedules[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleSectionChip(String type, String sectionKey, String label, int count) {
    final isSelected = _selectedScheduleSection == sectionKey;
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
      onSelected: (s) => setState(() => _selectedScheduleSection = sectionKey),
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

  Widget _buildEmptyScheduleState({required bool isExam}) {
    final canPublish = _user?.canManageLectures == true || _user?.isAdmin == true;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppTheme.primarySubtle,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isExam ? Icons.assignment_outlined : Icons.calendar_month_outlined,
                size: 42,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isExam ? 'لا يوجد جدول امتحانات' : 'لا يوجد جدول محاضرات',
              style: GoogleFonts.cairo(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            if (canPublish) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _showUploadScheduleDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.add_photo_alternate_rounded, color: Colors.white, size: 18),
                label: Text(
                  'رفع جدول',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleFileCard(ScheduleModel schedule) {
    final isExam = schedule.isExam;
    final isPdf = schedule.isPdf;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.lightBorder),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // رأس البطاقة الأنيق مع إخفاء اسم الناشر
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // أيقونة شارة مستند مميزة
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isPdf
                        ? const Color(0xFFFEF2F2)
                        : (isExam ? const Color(0xFFFFFBEB) : const Color(0xFFEEF2FF)),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isPdf
                          ? const Color(0xFFFCA5A5)
                          : (isExam ? const Color(0xFFFCD34D) : const Color(0xFFC7D2FE)),
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      isPdf ? Icons.picture_as_pdf_rounded : Icons.image_rounded,
                      color: isPdf
                          ? const Color(0xFFEF4444)
                          : (isExam ? const Color(0xFFD97706) : AppTheme.primary),
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // تفاصيل الجدول (القسم والمرحلة والتاريخ حصراً بدون أسماء شخصية)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              schedule.title,
                              style: GoogleFonts.cairo(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          // شارة الشعبة الملونة
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: schedule.isUnified
                                  ? const Color(0xFFECFDF5)
                                  : (schedule.section.toUpperCase() == 'A'
                                      ? const Color(0xFFEFF6FF)
                                      : (schedule.section.toUpperCase() == 'B'
                                          ? const Color(0xFFFAF5FF)
                                          : (schedule.section.toUpperCase() == 'C'
                                              ? const Color(0xFFFFFBEB)
                                              : const Color(0xFFF0FDFA)))),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: schedule.isUnified
                                    ? const Color(0xFFA7F3D0)
                                    : (schedule.section.toUpperCase() == 'A'
                                        ? const Color(0xFFBFDBFE)
                                        : (schedule.section.toUpperCase() == 'B'
                                            ? const Color(0xFFE9D5FF)
                                            : (schedule.section.toUpperCase() == 'C'
                                                ? const Color(0xFFFDE68A)
                                                : const Color(0xFF99F6E4)))),
                              ),
                            ),
                            child: Text(
                              schedule.sectionLabel,
                              style: GoogleFonts.cairo(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: schedule.isUnified
                                    ? const Color(0xFF047857)
                                    : (schedule.section.toUpperCase() == 'A'
                                        ? const Color(0xFF1D4ED8)
                                        : (schedule.section.toUpperCase() == 'B'
                                            ? const Color(0xFF7E22CE)
                                            : (schedule.section.toUpperCase() == 'C'
                                                ? const Color(0xFFB45309)
                                                : const Color(0xFF0F766E)))),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          // شارة نوع الجدول الرسمية
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: isExam ? const Color(0xFFFFF7ED) : AppTheme.primarySubtle,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isExam ? const Color(0xFFFDBA74) : AppTheme.primary.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Text(
                              isExam ? 'جدول امتحانات' : 'جدول أسبوعي',
                              style: GoogleFonts.cairo(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isExam ? const Color(0xFFC2410C) : AppTheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),

                      // سطر القسم والمرحلة والتاريخ (محمي من كشف هوية الناشر)
                      Row(
                        children: [
                          const Icon(Icons.school_outlined, size: 13, color: AppTheme.textMuted),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${schedule.department} • ${schedule.stage}',
                              style: GoogleFonts.cairo(
                                fontSize: 11,
                                color: AppTheme.textSecondary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            schedule.formattedDate,
                            style: GoogleFonts.cairo(
                              fontSize: 10.5,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // زر الحذف للمشرفين وممثلي الدفعة
                if (_user?.canManageLectures == true || _user?.isAdmin == true)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.danger, size: 20),
                    tooltip: 'حذف',
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    onPressed: () async {
                      final ok = await SupabaseService().deleteSchedule(schedule.id);
                      if (ok && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('تم حذف الجدول', style: GoogleFonts.cairo()),
                            backgroundColor: AppTheme.success,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                        _loadSchedules();
                      }
                    },
                  ),
              ],
            ),
          ),

          const Divider(color: AppTheme.lightBorder, height: 1),

          // صف الأزرار: زر معاينة سريعة وزر تنزيل رسمي
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(
              children: [
                // زر معاينة
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: OutlinedButton.icon(
                      onPressed: schedule.fileUrl != null
                          ? () {
                              AppMediaPreviewModal.show(
                                context: context,
                                title: schedule.title,
                                subtitle: '${schedule.department} • ${schedule.stage}',
                                url: _resolveUrl(schedule.fileUrl!),
                                downloadUrl: _resolveUrl(schedule.fileUrl!),
                                fileName: schedule.fileName ?? schedule.title,
                                mimeType: schedule.isPdf ? 'application/pdf' : 'image/jpeg',
                              );
                            }
                          : null,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: const BorderSide(color: AppTheme.primary, width: 1.2),
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.visibility_rounded, size: 16),
                      label: Text(
                        'معاينة سريعة',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // زر تنزيل
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: ElevatedButton.icon(
                      onPressed: () => _launchUrl(_resolveUrl(schedule.fileUrl)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.download_rounded, size: 16, color: Colors.white),
                      label: Text(
                        'تنزيل رسمي',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
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
