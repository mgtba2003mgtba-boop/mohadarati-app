import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../models/app_user_model.dart';
import '../models/schedule_model.dart';
import '../services/supabase_service.dart';
import '../widgets/study_book_animation.dart';
import '../widgets/app_fullscreen_modal.dart';
import '../widgets/app_icon_badge.dart';
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSchedules();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSchedules() async {
    setState(() => _isLoading = true);
    final service = SupabaseService();
    _user = service.currentUser;

    if (_user != null) {
      _schedules = await service.fetchSchedules(
        department: _user!.department,
        stage: _user!.stage,
      );
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
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
    final clean = url.trim();
    if (clean.startsWith('https://api.telegram.org')) {
      return clean;
    }
    if (kIsWeb) {
      if (clean.contains('/api/file/')) {
        final pathPart = clean.substring(clean.indexOf('/api/file/'));
        final host = Uri.base.host;
        final port = Uri.base.port;
        final portStr = (port == 80 || port == 443 || port == 0) ? '' : ':$port';
        return '${Uri.base.scheme}://$host$portStr$pathPart';
      }
    }
    return clean;
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
                      }

                      final schedule = ScheduleModel(
                        id: '',
                        title: title,
                        type: type,
                        department: _user?.department ?? 'ALL',
                        stage: _user?.stage ?? 'ALL',
                        fileUrl: finalFileUrl,
                        fileName: selectedFile?.name ?? title,
                        uploaderName: _user?.name ?? 'المشرف',
                        uploaderId: _user?.studentId,
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
            onPressed: _loadSchedules,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primary,
          unselectedLabelColor: const Color(0xFF94A3B8),
          indicatorColor: AppTheme.primary,
          labelStyle: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(icon: Icon(Icons.calendar_today_rounded, size: 18), text: 'المحاضرات الأسبوعية'),
            Tab(icon: Icon(Icons.assignment_rounded, size: 18), text: 'جدول الامتحانات'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildLecturesScheduleTab(),
                _buildExamsScheduleTab(),
              ],
            ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // تبويبات الجداول (عرض مباشر ملء الشاشة)
  // ══════════════════════════════════════════════════════════════
  Widget _buildLecturesScheduleTab() => _buildScheduleTabContent('lectures');
  Widget _buildExamsScheduleTab() => _buildScheduleTabContent('exams');

  Widget _buildScheduleTabContent(String type) {
    final schedules = _schedules.where((s) => s.type == type).toList();

    return RefreshIndicator(
      onRefresh: _loadSchedules,
      color: AppTheme.primary,
      child: schedules.isEmpty
          ? SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: _buildEmptyScheduleState(isExam: type == 'exams'),
              ),
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: schedules.length,
              itemBuilder: (context, index) => _buildScheduleFileCard(schedules[index]),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.lightBorder),
        boxShadow: AppTheme.cardShadow,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    AppIconBadge.indigo(
                      icon: schedule.isPdf ? Icons.picture_as_pdf_rounded : Icons.image_rounded,
                      size: 42,
                      iconSize: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            schedule.title,
                            style: GoogleFonts.cairo(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'بواسطة: ${schedule.uploaderName ?? 'العمادة'}',
                            style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_user?.canManageLectures == true || _user?.isAdmin == true)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.danger, size: 20),
                  tooltip: 'حذف',
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
          const SizedBox(height: 14),

          // صف الأزرار: زر معاينة وزر تنزيل
          Row(
            children: [
              // زر معاينة
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: schedule.fileUrl != null
                      ? () {
                          if (schedule.isPdf) {
                            _launchUrl(_resolveUrl(schedule.fileUrl!));
                          } else {
                            _openFullscreenViewer(schedule.fileUrl!, schedule.title);
                          }
                        }
                      : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.primary, width: 1.2),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.visibility_rounded, size: 18),
                  label: Text(
                    'معاينة',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // زر تنزيل
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _launchUrl(_resolveUrl(schedule.fileUrl)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.download_rounded, size: 18, color: Colors.white),
                  label: Text(
                    'تنزيل',
                    style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
