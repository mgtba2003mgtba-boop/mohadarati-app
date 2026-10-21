import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../models/app_user_model.dart';
import '../models/announcement_model.dart';
import '../services/supabase_service.dart';
import '../services/telegram_uploader_service.dart';
import '../services/image_optimizer_service.dart';
import 'app_network_image.dart';
import 'app_fullscreen_modal.dart';

/// ── بنل إدارة البوسترات المصورة (خاص بالمشرف العام مجتبى عواد) ────────────────
class DashboardBannersPanel extends StatefulWidget {
  final AppUserModel? currentUser;
  final void Function(String message, {bool isError})? onShowSnackbar;
  final VoidCallback? onBannerChanged;

  const DashboardBannersPanel({
    super.key,
    required this.currentUser,
    this.onShowSnackbar,
    this.onBannerChanged,
  });

  @override
  State<DashboardBannersPanel> createState() => _DashboardBannersPanelState();
}

class _DashboardBannersPanelState extends State<DashboardBannersPanel> {
  final _bannerTitleController = TextEditingController();
  final _bannerContentController = TextEditingController();
  PlatformFile? _selectedBannerImage;
  int _selectedBannerImageSize = 0;
  bool _isPickingBannerImage = false;
  bool _isLoading = false;
  String _selectedBannerDept = 'ALL';
  String _selectedBannerStage = 'ALL';
  List<AnnouncementModel> _existingBanners = [];
  bool _isLoadingBanners = false;
  OptimizedImageResult? _optimizedBanner;
  bool _isOptimizing = false;

  String _formatFileSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
  }

  bool get _isMujtaba {
    final user = widget.currentUser;
    if (user == null) return false;
    return user.studentId == 'ST-NUST-001630760-413' ||
        user.name.contains('مجتبى') ||
        user.isAdmin;
  }

  @override
  void initState() {
    super.initState();
    if (_isMujtaba) {
      _loadBanners();
    }
  }

  @override
  void dispose() {
    _bannerTitleController.dispose();
    _bannerContentController.dispose();
    super.dispose();
  }

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
          _optimizedBanner = null;
          _isOptimizing = true;
          if (_bannerTitleController.text.trim().isEmpty) {
            final nameWithoutExt = file.name.contains('.')
                ? file.name.substring(0, file.name.lastIndexOf('.'))
                : file.name;
            final lower = nameWithoutExt.toLowerCase().trim();
            if (!lower.contains('home_banner') &&
                !lower.contains('home banner') &&
                lower != 'banner' &&
                lower != 'image') {
              _bannerTitleController.text = nameWithoutExt;
            }
          }
        });

        // ضغط وتحسين الصورة محلياً في الذاكرة لمنع أي بطء أو ثقل
        try {
          final rawBytes = await file.readAsBytes();
          final opt = await ImageOptimizerService.optimizeBannerImage(
            rawBytes: rawBytes,
            originalFileName: file.name,
          );
          if (mounted) {
            setState(() {
              _optimizedBanner = opt;
              _isOptimizing = false;
            });
          }
        } catch (e) {
          debugPrint('[-] Error optimizing banner image: $e');
          if (mounted) {
            setState(() => _isOptimizing = false);
          }
        }
      } else {
        setState(() => _isPickingBannerImage = false);
      }
    }
  }

  Future<void> _submitBanner() async {
    if (_selectedBannerImage == null) {
      widget.onShowSnackbar?.call('يرجى اختيار صورة البوستر أولاً', isError: true);
      return;
    }
    String title = _bannerTitleController.text.trim();
    if (title.isEmpty) {
      if (_selectedBannerImage != null) {
        final nameWithoutExt = _selectedBannerImage!.name.contains('.')
            ? _selectedBannerImage!.name.substring(0, _selectedBannerImage!.name.lastIndexOf('.'))
            : _selectedBannerImage!.name;
        final clean = nameWithoutExt.replaceAll(RegExp(r'[_-]'), ' ').trim();
        title = clean.isNotEmpty ? clean : 'بوستر رسمي';
      } else {
        title = 'بوستر رسمي';
      }
    }

    setState(() => _isLoading = true);

    final res = await TelegramUploaderService().uploadFileToTelegram(
      file: _selectedBannerImage!,
      overrideBytes: _optimizedBanner?.bytes,
      overrideFileName: _optimizedBanner?.fileName,
      caption: title,
      fileType: 'banner',
    );

    if (!res.success || res.fileUrl == null) {
      if (mounted) {
        setState(() => _isLoading = false);
        widget.onShowSnackbar?.call(res.message, isError: true);
      }
      return;
    }

    final baseContent = _bannerContentController.text.trim();
    final tgTag = res.telegramMessageId != null ? ' [TG_MSG_ID:${res.telegramMessageId}]' : '';

    final newBanner = AnnouncementModel(
      id: '',
      title: title,
      content: '$baseContent [HOME_BANNER]$tgTag',
      authorId: widget.currentUser?.studentId ?? 'ST-NUST-001630760-413',
      authorName: widget.currentUser?.name ?? 'مجتبى عواد',
      authorRole: 'admin',
      department: _selectedBannerDept,
      stage: _selectedBannerStage,
      category: 'banner',
      subjectName: 'BANNER',
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
        _optimizedBanner = null;
        _isOptimizing = false;
      });
      widget.onShowSnackbar?.call('تم رفع ونشر البوستر في الواجهة الرئيسية بنجاح عبر سيرفر تيليجرام');
      _loadBanners();
      widget.onBannerChanged?.call();
    } else {
      widget.onShowSnackbar?.call('حدث خطأ أثناء حفظ بيانات البوستر', isError: true);
    }
  }

  Future<void> _deleteBanner(String id) async {
    final ok = await SupabaseService().deleteAnnouncement(id);
    if (ok && mounted) {
      widget.onShowSnackbar?.call('تم حذف البوستر بنجاح');
      _loadBanners();
      widget.onBannerChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
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

          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _selectedBannerImage != null ? AppTheme.success : AppTheme.lightBorder,
                width: _selectedBannerImage != null ? 1.5 : 1,
              ),
            ),
            child: _isOptimizing
                ? Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.primary),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'جاري ضغط وتحسين الصورة محلياً في الذاكرة...',
                                style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
                              ),
                              Text(
                                'تجهيز أبعاد البانر لسرعة تحميل فائقة على هواتف الطلبة',
                                style: GoogleFonts.cairo(fontSize: 10, color: const Color(0xFF94A3B8)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : _selectedBannerImage == null
                    ? InkWell(
                        onTap: _isPickingBannerImage ? null : _pickBannerImage,
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            children: [
                              const Icon(Icons.add_photo_alternate_rounded, size: 42, color: AppTheme.primaryLight),
                              const SizedBox(height: 8),
                              Text(
                                _isPickingBannerImage ? 'جاري فتح المعرض...' : 'اضغط لاختيار صورة البوستر أو الإعلان',
                                style: GoogleFonts.cairo(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppTheme.primary),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'ضغط ذكي تلقائي مدمج يضمن سرعة التحميل الفورية للطلبة',
                                style: GoogleFonts.cairo(fontSize: 10, color: const Color(0xFF94A3B8)),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // معاينة حية وفورية للصورة المضغوطة
                            if (_optimizedBanner != null) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  height: 140,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Image.memory(
                                    _optimizedBanner!.bytes,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],

                            Row(
                              children: [
                                const Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 24),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _selectedBannerImage!.name,
                                    style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close_rounded, color: AppTheme.danger, size: 20),
                                  tooltip: 'إلغاء واختيار صورة أخرى',
                                  onPressed: () => setState(() {
                                    _selectedBannerImage = null;
                                    _selectedBannerImageSize = 0;
                                    _optimizedBanner = null;
                                    _isOptimizing = false;
                                  }),
                                ),
                              ],
                            ),

                            // شريط مؤشرات التحسين والضغط
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppTheme.success.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
                                  ),
                                  child: Text(
                                    'الحجم المحسّن: ${_formatFileSize(_optimizedBanner?.optimizedSizeBytes ?? _selectedBannerImageSize)} ⚡',
                                    style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.success),
                                  ),
                                ),
                                if (_optimizedBanner != null && _optimizedBanner!.savedPercentage > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'توفير ${_optimizedBanner!.savedPercentage.toStringAsFixed(0)}% من سرعة التحميل 🚀',
                                      style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primary),
                                    ),
                                  ),
                                if (_optimizedBanner != null && _optimizedBanner!.width > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${_optimizedBanner!.width} × ${_optimizedBanner!.height} px',
                                      style: GoogleFonts.cairo(fontSize: 10, color: const Color(0xFF64748B)),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _bannerTitleController,
            style: GoogleFonts.cairo(fontSize: 13, color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'عنوان البوستر (مثال: جدول الامتحانات النهائية، تهنئة بالعام الجديد...)',
              hintStyle: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFF94A3B8)),
              prefixIcon: const Icon(Icons.title_rounded, color: AppTheme.primary, size: 20),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.lightBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.lightBorder)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
            ),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _bannerContentController,
            maxLines: 2,
            style: GoogleFonts.cairo(fontSize: 13, color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'وصف أو تفاصيل إضافية للبوستر (اختياري)',
              hintStyle: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFF94A3B8)),
              prefixIcon: const Icon(Icons.notes_rounded, color: AppTheme.primary, size: 20),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.lightBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.lightBorder)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
            ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedBannerDept,
                  dropdownColor: Colors.white,
                  style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'القسم المستهدف',
                    labelStyle: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFF94A3B8)),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.lightBorder)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: ['ALL', ...AppConstants.departments].map((d) => DropdownMenuItem(
                    value: d,
                    child: Text(d == 'ALL' ? 'كافة الأقسام' : d, style: GoogleFonts.cairo(fontSize: 11)),
                  )).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedBannerDept = val);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedBannerStage,
                  dropdownColor: Colors.white,
                  style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'المرحلة المستهدفة',
                    labelStyle: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFF94A3B8)),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.lightBorder)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: ['ALL', ...AppConstants.stages].map((s) => DropdownMenuItem(
                    value: s,
                    child: Text(s == 'ALL' ? 'كافة المراحل' : s, style: GoogleFonts.cairo(fontSize: 11)),
                  )).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedBannerStage = val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          ElevatedButton.icon(
            onPressed: _isLoading ? null : _submitBanner,
            icon: _isLoading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.cloud_upload_rounded, color: Colors.white, size: 20),
            label: Text(
              _isLoading ? 'جاري الرفع والنشر عبر سيرفر تيليجرام...' : 'نشر البوستر في الواجهة الرئيسية',
              style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                icon: const Icon(Icons.refresh_rounded, color: AppTheme.primary, size: 20),
                tooltip: 'تحديث قائمة البوسترات',
                onPressed: () => _loadBanners(forceRefresh: true),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (_isLoadingBanners)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else if (_existingBanners.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.lightBorder),
              ),
              child: Center(
                child: Text(
                  'لا توجد بوسترات منشورة حالياً في الواجهة الرئيسية',
                  style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFF94A3B8)),
                ),
              ),
            )
          else
            ..._existingBanners.map(_buildBannerItem),
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
