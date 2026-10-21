import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants/app_constants.dart';
import '../core/constants/biometric_subjects.dart';
import '../core/theme/app_theme.dart';
import '../models/app_user_model.dart';
import '../models/lecture_model.dart';
import '../services/supabase_service.dart';
import '../services/telegram_uploader_service.dart';
import '../services/web_file_saver.dart';
import '../widgets/app_media_preview_modal.dart';
import 'package:file_picker/file_picker.dart';

class LecturesScreen extends StatefulWidget {
  const LecturesScreen({super.key});

  @override
  State<LecturesScreen> createState() => _LecturesScreenState();
}

class _LecturesScreenState extends State<LecturesScreen> {
  bool _isLoading = true;
  List<LectureModel> _lectures = [];
  AppUserModel? _user;

  String _selectedDept = 'ALL';
  String _selectedStage = 'ALL';
  String _selectedSection = 'ALL';
  int _selectedSemester = 1;
  String _selectedType = 'ALL'; // 'ALL', 'theory', 'practical'
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _initFiltersAndLoad();
  }

  void _initFiltersAndLoad() {
    final service = SupabaseService();
    _user = service.currentUser;

    if (_user != null) {
      _selectedDept = _user!.isAdmin ? 'ALL' : _user!.department;
      _selectedStage = _user!.isAdmin ? 'ALL' : _user!.stage;
      _selectedSection = _user!.isAdmin ? 'ALL' : (_user!.section ?? 'ALL');
      _selectedSemester = _user!.semester;
    }

    _loadLectures();
  }

  Future<void> _loadLectures({bool forceRefresh = false}) async {
    setState(() => _isLoading = true);

    final service = SupabaseService();
    final list = await service.fetchLectures(
      department: _selectedDept == 'ALL' ? null : _selectedDept,
      stage: _selectedStage == 'ALL' ? null : _selectedStage,
      section: (_user?.isAdmin == true && _selectedSection != 'ALL')
          ? _selectedSection
          : (_user?.isAdmin == true ? null : _user?.section),
      semester: _selectedSemester,
      forceRefresh: forceRefresh,
    );

    if (mounted) {
      setState(() {
        _lectures = list;
        _isLoading = false;
      });
    }
  }

  List<LectureModel> get _filteredLectures {
    final cleanQuery = _searchQuery.trim().toLowerCase();
    return _lectures.where((l) {
      final matchesType = _selectedType == 'ALL' || l.type == _selectedType;
      final matchesSearch = cleanQuery.isEmpty ||
          l.searchToken.contains(cleanQuery) ||
          l.section.toLowerCase().contains(cleanQuery);
      return matchesType && matchesSearch;
    }).toList();
  }

  /// فتح أو بث المحاضرة مباشرة عبر مشغل الفيديو أو السحابة
  Future<void> _openMediaStream(dynamic target) async {
    if (target is LectureModel) {
      final partsDesc = (target.telegramFileId != null && target.telegramFileId!.startsWith('telegram:parts:'))
          ? target.telegramFileId!
          : (target.driveUrl.startsWith('telegram:parts:') ? target.driveUrl : null);
      if (partsDesc != null) {
        await _downloadChunkedLecture(target, partsDesc, isPreview: true);
        return;
      }
    }

    String? url;
    if (target is LectureModel) {
      if (target.telegramFileId != null && target.telegramFileId!.isNotEmpty) {
        final fresh = await TelegramUploaderService().resolveFileUrl(target.telegramFileId!);
        if (fresh != null && fresh.isNotEmpty) url = fresh;
      }
      if (url == null || url.isEmpty) {
        if (target.driveUrl.startsWith('http')) {
          url = target.driveUrl;
        } else {
          url = target.streamUrl;
        }
      }
    } else if (target is String) {
      url = target;
    }

    if (url == null || url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('رابط البث أو الملف غير متوفر')),
        );
      }
      return;
    }

    if (!mounted) return;
    AppMediaPreviewModal.show(
      context: context,
      title: target is LectureModel ? target.title : 'معاينة المحاضرة',
      subtitle: target is LectureModel ? '${target.subjectName} • ${target.typeLabel}' : null,
      url: url,
      downloadUrl: target is LectureModel ? target.downloadUrl : null,
      fileName: target is LectureModel ? (target.fileName ?? target.title) : null,
      mimeType: target is LectureModel ? target.mimeType : null,
    );
  }

  /// تحميل المحاضرة مباشرة من سحابة تيليجرام
  Future<void> _openMediaDownload(dynamic target) async {
    if (target is LectureModel) {
      final partsDesc = (target.telegramFileId != null && target.telegramFileId!.startsWith('telegram:parts:'))
          ? target.telegramFileId!
          : (target.driveUrl.startsWith('telegram:parts:') ? target.driveUrl : null);
      if (partsDesc != null) {
        await _downloadChunkedLecture(target, partsDesc);
        return;
      }
    }

    String? url;
    if (target is LectureModel) {
      url = target.downloadUrl;
      if (target.telegramFileId != null && target.telegramFileId!.isNotEmpty) {
        final fresh = await TelegramUploaderService().resolveFileUrl(target.telegramFileId!);
        if (fresh != null && fresh.isNotEmpty) url = fresh;
      }
      if (url == null || url.isEmpty) {
        if (target.hasDriveUrl) url = target.cleanDriveViewUrl;
      }
    } else if (target is String) {
      url = target;
    }

    if (url == null || url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('رابط التحميل غير متوفر')),
        );
      }
      return;
    }

    final uri = Uri.parse(url);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر بدء التحميل')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في التحميل: $e')),
        );
      }
    }
  }

  /// تنزيل أو معاينة المحاضرات الكبيرة المجزأة وتجميعها بسلاسة للطلبة
  Future<void> _downloadChunkedLecture(
    LectureModel lecture,
    String partsDescriptor, {
    bool isPreview = false,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final fileName = lecture.fileName ?? '${lecture.title}.pdf';

    double dlProgress = 0.05;
    String dlStatus = isPreview
        ? 'جاري تجهيز وتجميع المحاضرة للمعاينة الفورية...'
        : 'جاري الاتصال بسحابة تيليجرام وتجهيز الأجزاء...';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return PopScope(
            canPop: false,
            child: AlertDialog(
              backgroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isPreview ? Icons.visibility_rounded : Icons.downloading_rounded,
                      color: AppTheme.primaryLight,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isPreview ? 'معاينة وتجميع المحاضرة' : 'تنزيل وتجميع المحاضرة',
                      style: GoogleFonts.cairo(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: dlProgress.clamp(0.0, 1.0),
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryLight),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          dlStatus,
                          style: GoogleFonts.cairo(color: Colors.white60, fontSize: 11),
                        ),
                      ),
                      Text(
                        '${(dlProgress * 100).toInt()}%',
                        style: GoogleFonts.cairo(color: AppTheme.primaryLight, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
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
          dlStatus = status;
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
                subtitle: '${lecture.subjectName} • ${lecture.formattedFileSize}',
                url: blobUrl,
                fileName: fileName,
                mimeType: lecture.mimeType,
              );
              return;
            }
          }
          saveFileInBrowser(bytes, fileName);
          messenger.showSnackBar(
            SnackBar(
              content: Text('تم تحميل $fileName بنجاح 🚀'),
              backgroundColor: AppTheme.primary,
            ),
          );
        } else {
          if (kIsWeb) {
            saveFileInBrowser(bytes, fileName);
            messenger.showSnackBar(
              SnackBar(
                content: Text('تم تنزيل وتجميع $fileName بنجاح 🚀'),
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
    final canPublish = _user?.canManageLectures == true ||
        _user?.isAdmin == true ||
        _user?.isRepresentative == true;

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        title: const Text('المحاضرات والمقررات الدراسية'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadLectures,
          ),
        ],
      ),
      floatingActionButton: canPublish
          ? FloatingActionButton.extended(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.upload_file_rounded),
              label: Text('نشر محاضرة جديدة 🚀', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
              onPressed: () => _showPublishLectureSheet(context),
            )
          : null,
      body: Column(
        children: [
          // شريط الرقابة والإشراف العام (خاص بالمشرف العام لمراقبة كافة الأقسام والشُعب)
          if (_user?.isAdmin == true) _buildSupervisorBar(),

          // شريط البحث
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: TextField(
              style: GoogleFonts.cairo(color: Colors.white),
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'ابحث باسم المحاضرة، المادة، أو الأستاذ...',
                prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.primaryLight),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, color: Color(0xFF64748B)),
                        onPressed: () => setState(() => _searchQuery = ''),
                      )
                    : null,
              ),
            ),
          ),

          // محدد الفصل الدراسي والنوع (الكورس الأول / الثاني - نظري / عملي)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: Row(
              children: [
                InkWell(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _selectedSemester = _selectedSemester == 1 ? 2 : 1;
                    });
                    _loadLectures(forceRefresh: true);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.swap_horiz_rounded, color: AppTheme.primaryLight, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          _selectedSemester == 2 ? 'الفصل الثاني (الكورس 2) 📙' : 'الفصل الأول (الكورس 1) 📘',
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Container(width: 1, height: 24, color: AppTheme.darkBorder),
                const SizedBox(width: 14),
                _buildTypeChip('الكل', 'ALL'),
                const SizedBox(width: 6),
                _buildTypeChip('نظري', 'theory'),
                const SizedBox(width: 6),
                _buildTypeChip('عملي', 'practical'),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // قائمة المحاضرات
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryLight))
                : _filteredLectures.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.folder_open_rounded, size: 54, color: Color(0xFF475569)),
                            const SizedBox(height: 12),
                            Text(
                              'لا توجد محاضرات منشورة لهذا الفصل حالياً',
                              style: GoogleFonts.cairo(color: const Color(0xFF94A3B8), fontSize: 13),
                            ),
                            if (canPublish) ...[
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: () => _showPublishLectureSheet(context),
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('كن أول من ينشر محاضرة'),
                              ),
                            ],
                          ],
                        ),
                      )
                    : ListView.builder(
                        cacheExtent: 800,
                        addAutomaticKeepAlives: true,
                        addRepaintBoundaries: true,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                        itemCount: _filteredLectures.length,
                        itemBuilder: (context, index) {
                          return _buildLectureCard(_filteredLectures[index]);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeChip(String label, String typeKey) {
    final isSelected = _selectedType == typeKey;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) setState(() => _selectedType = typeKey);
      },
      selectedColor: AppTheme.accent,
      backgroundColor: AppTheme.darkCard,
      labelStyle: GoogleFonts.cairo(
        fontSize: 11,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        color: isSelected ? Colors.black : const Color(0xFF94A3B8),
      ),
      side: BorderSide(color: isSelected ? AppTheme.accent : AppTheme.darkBorder),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  Widget _buildLectureCard(LectureModel lecture) {
    return RepaintBoundary(
      key: ValueKey('lec_card_${lecture.id}'),
      child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
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
                    'جاري النشر والمزامنة السحابية للطلبة... ⚡',
                    style: GoogleFonts.cairo(fontSize: 10.5, fontWeight: FontWeight.bold, color: const Color(0xFFFBBF24)),
                  ),
                ],
              ),
            ),
          ],

          // الرأس: نوع المحاضرة وتاريخ الإضافة
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: lecture.isPractical
                      ? AppTheme.accent.withValues(alpha: 0.15)
                      : AppTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  lecture.typeLabel,
                  style: GoogleFonts.cairo(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: lecture.isPractical ? AppTheme.accent : AppTheme.primaryLight,
                  ),
                ),
              ),
              Text(
                '${lecture.createdAt.year}/${lecture.createdAt.month.toString().padLeft(2, '0')}/${lecture.createdAt.day.toString().padLeft(2, '0')}',
                style: GoogleFonts.cairo(fontSize: 10, color: const Color(0xFF64748B)),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // عنوان المحاضرة
          Text(
            lecture.title,
            style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 2),

          // اسم المادة
          Text(
            'المادة: ${lecture.subjectName}',
            style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFF94A3B8)),
          ),

          if (lecture.displayDescription.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              lecture.displayDescription,
              style: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFFCBD5E1), height: 1.4),
            ),
          ],
          const SizedBox(height: 12),

          // إذا كانت المحاضرة رابطاً سحابياً / Google Drive
          if (lecture.hasDriveUrl && !lecture.hasTelegramMedia) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1E3A8A).withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cloud_done_rounded, size: 16, color: Color(0xFF60A5FA)),
                  const SizedBox(width: 6),
                  Text(
                    'رابط سحابي مباشر (Google Drive)',
                    style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF93C5FD)),
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
                      backgroundColor: const Color(0xFF2563EB),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18, color: Colors.white),
                    label: Text(
                      'فتح المحاضرة على Google Drive',
                      style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    onPressed: () => _openMediaStream(lecture),
                  ),
                ),
              ],
            ),
          ],

          // إذا كانت المحاضرة متوفرة عبر سيرفر تيليجرام
          if (lecture.hasTelegramMedia) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF0D9488).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bolt_rounded, size: 16, color: Color(0xFF2DD4BF)),
                  const SizedBox(width: 6),
                  Text(
                    'متوفرة عبر سيرفر التيليجرام السريع (CDN)',
                    style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF2DD4BF)),
                  ),
                  const Spacer(),
                  if (lecture.formattedFileSize.isNotEmpty)
                    Text(
                      lecture.formattedFileSize,
                      style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                // زر المعاينة المباشرة
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D9488),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.visibility_rounded, size: 18, color: Colors.white),
                    label: Text(
                      'معاينة المحاضرة',
                      style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    onPressed: () => _openMediaStream(lecture),
                  ),
                ),
                const SizedBox(width: 8),
                // زر التحميل المباشر
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF0D9488)),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 18, color: Color(0xFF2DD4BF)),
                    label: Text(
                      'تحميل المحاضرة',
                      style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2DD4BF)),
                    ),
                    onPressed: () => _openMediaDownload(lecture),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
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
                          'مراقبة المحاضرات والمقررات (إشراف عام)',
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
                      'استعراض المحاضرات والمقررات المرفوعة لكافة الأقسام والمراحل والشُعب',
                      style: GoogleFonts.cairo(color: Colors.white70, fontSize: 10),
                    ),
                  ],
                ),
              ),
              if (_selectedDept != 'ALL' || _selectedStage != 'ALL' || _selectedSection != 'ALL')
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedDept = 'ALL';
                      _selectedStage = 'ALL';
                      _selectedSection = 'ALL';
                    });
                    _loadLectures();
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
                  value: _selectedDept,
                  items: [
                    const DropdownMenuItem(value: 'ALL', child: Text('كافة الأقسام 🌐', overflow: TextOverflow.ellipsis)),
                    ...AppConstants.departments.map((d) => DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedDept = val);
                      _loadLectures();
                    }
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 3,
                child: _buildSupervisorDropdown(
                  label: 'المرحلة',
                  value: _selectedStage,
                  items: [
                    const DropdownMenuItem(value: 'ALL', child: Text('كل المراحل', overflow: TextOverflow.ellipsis)),
                    ...AppConstants.stages.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedStage = val);
                      _loadLectures();
                    }
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 3,
                child: _buildSupervisorDropdown(
                  label: 'الشعبة',
                  value: _selectedSection,
                  items: const [
                    DropdownMenuItem(value: 'ALL', child: Text('كل الشُعب', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'A', child: Text('شعبة A')),
                    DropdownMenuItem(value: 'B', child: Text('شعبة B')),
                    DropdownMenuItem(value: 'C', child: Text('شعبة C')),
                    DropdownMenuItem(value: 'D', child: Text('شعبة D')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedSection = val);
                      _loadLectures();
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

  void _showPublishLectureSheet(BuildContext context) async {
    if (_user == null) return;
    final res = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _DirectPublishLectureSheet(
        currentUser: _user!,
        initialDepartment: _selectedDept == 'ALL' ? (_user!.department.isNotEmpty ? _user!.department : AppConstants.departments.first) : _selectedDept,
        initialStage: _selectedStage == 'ALL' ? (_user!.stage.isNotEmpty ? _user!.stage : AppConstants.stages.first) : _selectedStage,
        initialSemester: _selectedSemester,
        onOptimisticSubmit: (optimisticLecture, file, driveUrl) {
          setState(() {
            _lectures.insert(0, optimisticLecture);
          });
        },
      ),
    );

    if (res == true && mounted) {
      _loadLectures(forceRefresh: true);
    }
  }
}

// ══════════════════════════════════════════════════════════════
// نافذة النشر المباشر السلسة للمحاضرات (Optimistic UI - بدون إعادة تحميل)
// ══════════════════════════════════════════════════════════════
class _DirectPublishLectureSheet extends StatefulWidget {
  final AppUserModel currentUser;
  final String initialDepartment;
  final String initialStage;
  final int initialSemester;
  final Function(LectureModel optimisticLecture, PlatformFile? file, String? driveUrl) onOptimisticSubmit;

  const _DirectPublishLectureSheet({
    required this.currentUser,
    required this.initialDepartment,
    required this.initialStage,
    required this.initialSemester,
    required this.onOptimisticSubmit,
  });

  @override
  State<_DirectPublishLectureSheet> createState() => _DirectPublishLectureSheetState();
}

class _DirectPublishLectureSheetState extends State<_DirectPublishLectureSheet> {
  late String _dept;
  late String _stage;
  late int _semester;
  late String _section;
  String _lectureType = 'theory'; // 'theory', 'practical'
  bool _isDriveMode = false;

  final _titleController = TextEditingController();
  final _customSubjectController = TextEditingController();
  final _driveUrlController = TextEditingController();
  final _descController = TextEditingController();

  List<String> _availableSubjects = [];
  String? _selectedSubject;
  bool _isCustomSubject = false;

  PlatformFile? _selectedFile;
  int _selectedFileSize = 0;
  bool _isPickingFile = false;
  bool _isSubmitting = false;
  double _uploadProgress = 0.0;
  String _uploadStatus = '';
  int _bytesSent = 0;
  int _totalBytes = 0;

  @override
  void initState() {
    super.initState();
    _dept = widget.initialDepartment;
    _stage = widget.initialStage;
    _semester = widget.initialSemester;

    if (widget.currentUser.isAdmin) {
      _section = 'ALL';
    } else if (widget.currentUser.assignedSections.isNotEmpty) {
      _section = widget.currentUser.assignedSections.first;
    } else if (widget.currentUser.section != null && widget.currentUser.section!.isNotEmpty) {
      _section = widget.currentUser.section!;
    } else {
      _section = 'ALL';
    }

    _loadSubjectNames();
  }

  void _loadSubjectNames() {
    final names = BiometricSubjects.getSubjectNames(
      department: _dept,
      stage: _stage,
      semester: _semester,
    );
    setState(() {
      _availableSubjects = names;
      if (names.isNotEmpty) {
        _selectedSubject = names.first;
        _isCustomSubject = false;
      } else {
        _selectedSubject = null;
        _isCustomSubject = true;
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _customSubjectController.dispose();
    _driveUrlController.dispose();
    _descController.dispose();
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

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى كتابة عنوان المحاضرة'), backgroundColor: AppTheme.danger),
      );
      return;
    }

    final subject = _isCustomSubject
        ? _customSubjectController.text.trim()
        : (_selectedSubject ?? _customSubjectController.text.trim());

    if (subject.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار المادة أو كتابة اسمها'), backgroundColor: AppTheme.danger),
      );
      return;
    }

    String? driveUrl;
    if (_isDriveMode) {
      driveUrl = _driveUrlController.text.trim();
      if (driveUrl.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى إدخال رابط Google Drive أو الرابط السحابي'), backgroundColor: AppTheme.danger),
        );
        return;
      }
      final parsed = Uri.tryParse(driveUrl);
      if (parsed == null || !parsed.hasScheme || (!driveUrl.startsWith('http://') && !driveUrl.startsWith('https://'))) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى إدخال رابط ويب صالح يبدأ بـ https://'), backgroundColor: AppTheme.danger),
        );
        return;
      }
    } else {
      if (_selectedFile == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى اختيار ملف المحاضرة (PDF / مستند / صورة)'), backgroundColor: AppTheme.danger),
        );
        return;
      }

    }

    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final optimisticLecture = LectureModel(
      id: tempId,
      title: title,
      subjectName: subject,
      department: _dept,
      stage: _stage,
      section: _section,
      semester: _semester,
      type: _lectureType,
      driveUrl: _isDriveMode ? (driveUrl ?? '') : '',
      description: _descController.text.trim().isNotEmpty ? _descController.text.trim() : null,
      uploaderId: widget.currentUser.studentId.isNotEmpty ? widget.currentUser.studentId : 'ADMIN',
      uploaderName: widget.currentUser.name.isNotEmpty ? widget.currentUser.name : 'ممثل الشعبة',
      uploaderRole: widget.currentUser.role,
      fileName: _selectedFile?.name,
      fileSizeBytes: _selectedFileSize > 0 ? _selectedFileSize : null,
      createdAt: DateTime.now(),
    );

    if (_isDriveMode) {
      Navigator.pop(context, true);
      widget.onOptimisticSubmit(optimisticLecture, null, driveUrl);
      return;
    }

    // وضع رفع الملف المباشر مع تتبع حي لنسبة التحميل وبايتات التدفق
    setState(() {
      _isSubmitting = true;
      _uploadProgress = 0.05;
      _uploadStatus = 'جاري قراءة وتجهيز ملف المحاضرة...';
      _bytesSent = 0;
      _totalBytes = _selectedFileSize;
    });

    try {
      final res = await TelegramUploaderService().uploadLecture(
        file: _selectedFile!,
        title: title,
        subjectName: subject,
        department: _dept,
        stage: _stage,
        section: _section,
        semester: _semester,
        lectureType: _lectureType,
        description: _descController.text.trim().isNotEmpty ? _descController.text.trim() : null,
        uploaderId: widget.currentUser.studentId.isNotEmpty ? widget.currentUser.studentId : 'ADMIN',
        uploaderName: widget.currentUser.name.isNotEmpty ? widget.currentUser.name : 'ممثل الشعبة',
        uploaderRole: widget.currentUser.role,
        onProgress: (status, prog) {
          if (mounted) {
            setState(() {
              _uploadStatus = status;
              if (prog != null) _uploadProgress = prog;
            });
          }
        },
        onDetailedProgress: (sent, total, prog, status) {
          if (mounted) {
            setState(() {
              _bytesSent = sent;
              _totalBytes = total;
              _uploadProgress = prog;
              _uploadStatus = status;
            });
          }
        },
      );

      if (!res.success) {
        throw Exception(res.message);
      }

      if (mounted) {
        setState(() {
          _uploadProgress = 1.0;
          _uploadStatus = 'تم رفع ونشر المحاضرة بنجاح 🚀';
        });
        await Future.delayed(const Duration(milliseconds: 900));
        if (mounted) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم رفع ونشر المحاضرة بنجاح 🚀'),
              backgroundColor: AppTheme.primary,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر إكمال النشر: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.currentUser.isAdmin;

    return PopScope(
      canPop: !_isSubmitting,
      child: Container(
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
                    child: const Icon(Icons.upload_file_rounded, color: AppTheme.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'نشر محاضرة دراسية جديدة',
                          style: GoogleFonts.cairo(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          '$_dept • $_stage • الفصل $_semester',
                          style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
                    onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

            // عنوان المحاضرة
            TextField(
              controller: _titleController,
              style: GoogleFonts.cairo(fontSize: 13, color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: 'عنوان المحاضرة',
                hintText: 'مثال: المحاضرة 1 - مقدمة عامة',
                labelStyle: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textSecondary),
                hintStyle: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textMuted),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.title_rounded, size: 20, color: AppTheme.primary),
              ),
            ),
            const SizedBox(height: 12),

            // المادة الدراسية
            if (!_isCustomSubject && _availableSubjects.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                value: _selectedSubject,
                dropdownColor: Colors.white,
                style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'المادة الدراسية الرسمية',
                  labelStyle: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textSecondary),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.menu_book_rounded, size: 20, color: AppTheme.primary),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: [
                  ..._availableSubjects.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                  const DropdownMenuItem(value: '__CUSTOM__', child: Text('✍️ مادة أخرى... (إدخال يدوي)')),
                ],
                onChanged: (val) {
                  if (val == '__CUSTOM__') {
                    setState(() {
                      _isCustomSubject = true;
                      _selectedSubject = null;
                    });
                  } else if (val != null) {
                    setState(() => _selectedSubject = val);
                  }
                },
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _customSubjectController,
                      style: GoogleFonts.cairo(fontSize: 13, color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'اسم المادة الدراسية',
                        hintText: 'اكتب اسم المادة هنا...',
                        labelStyle: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textSecondary),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        prefixIcon: const Icon(Icons.edit_note_rounded, size: 20, color: AppTheme.primary),
                      ),
                    ),
                  ),
                  if (_availableSubjects.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.list_alt_rounded, color: AppTheme.primary),
                      tooltip: 'العودة للقائمة الرسمية',
                      onPressed: () {
                        setState(() {
                          _isCustomSubject = false;
                          _selectedSubject = _availableSubjects.first;
                        });
                      },
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 12),

            // نوع المحاضرة ونمط الرفع
            Row(
              children: [
                Text('نوع المحاضرة: ', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold)),
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

            // التبديل بين رفع ملف مباشر ورابط سحابي / درايف
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: !_isDriveMode ? AppTheme.primary.withValues(alpha: 0.12) : Colors.transparent,
                      side: BorderSide(color: !_isDriveMode ? AppTheme.primary : Colors.grey.shade300, width: !_isDriveMode ? 1.5 : 1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onPressed: () => setState(() => _isDriveMode = false),
                    icon: Icon(Icons.attach_file_rounded, size: 16, color: !_isDriveMode ? AppTheme.primary : AppTheme.textSecondary),
                    label: Text(
                      'ملف مباشر من الجهاز',
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: !_isDriveMode ? AppTheme.primary : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: _isDriveMode ? AppTheme.accent.withValues(alpha: 0.15) : Colors.transparent,
                      side: BorderSide(color: _isDriveMode ? AppTheme.accent : Colors.grey.shade300, width: _isDriveMode ? 1.5 : 1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onPressed: () => setState(() => _isDriveMode = true),
                    icon: Icon(Icons.link_rounded, size: 16, color: _isDriveMode ? AppTheme.accent : AppTheme.textSecondary),
                    label: Text(
                      'رابط سحابي / Drive',
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _isDriveMode ? AppTheme.accent : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // محتوى الملف أو الرابط السحابي
            if (_isDriveMode) ...[
              TextField(
                controller: _driveUrlController,
                style: GoogleFonts.cairo(fontSize: 13, color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'رابط Google Drive أو الرابط السحابي للمحاضرة',
                  hintText: 'https://drive.google.com/file/d/... أو أي رابط ويب',
                  labelStyle: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textSecondary),
                  hintStyle: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textMuted),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.cloud_done_rounded, color: AppTheme.accent, size: 20),
                  helperText: 'يدعم الفيديوهات والملفات الكبيرة ومصادر المحاضرات الخارجية بكل سهولة وبدون قيود حجم',
                  helperStyle: GoogleFonts.cairo(fontSize: 10, color: AppTheme.textSecondary),
                ),
              ),
            ] else ...[
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
            ],
            const SizedBox(height: 12),

            // الشعبة المستهدفة
            if (isAdmin || widget.currentUser.assignedSections.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                value: (isAdmin || widget.currentUser.assignedSections.contains(_section) || _section == 'ALL')
                    ? _section
                    : (widget.currentUser.assignedSections.isNotEmpty ? widget.currentUser.assignedSections.first : 'ALL'),
                dropdownColor: Colors.white,
                style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'الشعبة المستهدفة بالمحاضرة',
                  labelStyle: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textSecondary),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.groups_rounded, size: 20, color: AppTheme.primary),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: [
                  const DropdownMenuItem(value: 'ALL', child: Text('🌐 جميع الشعب (عام لكافة الطلاب)')),
                  if (isAdmin) ...const [
                    DropdownMenuItem(value: 'A', child: Text('🏷️ شعبة A')),
                    DropdownMenuItem(value: 'B', child: Text('🏷️ شعبة B')),
                    DropdownMenuItem(value: 'C', child: Text('🏷️ شعبة C')),
                    DropdownMenuItem(value: 'D', child: Text('🏷️ شعبة D')),
                    DropdownMenuItem(value: 'E', child: Text('🏷️ شعبة E')),
                    DropdownMenuItem(value: 'F', child: Text('🏷️ شعبة F')),
                  ] else ...[
                    for (final s in widget.currentUser.assignedSections.where((s) => s != 'ALL'))
                      DropdownMenuItem(value: s, child: Text('🏷️ شعبة $s')),
                  ],
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _section = val);
                },
              ),
              const SizedBox(height: 12),
            ],

            // ملاحظات وتفاصيل إضافية
            TextField(
              controller: _descController,
              maxLines: 2,
              style: GoogleFonts.cairo(fontSize: 13, color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: 'ملاحظات وتفاصيل إضافية (اختياري)',
                hintText: 'مثال: ملخص الفصل أو واجبات وملاحظات للأستاذ...',
                labelStyle: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textSecondary),
                hintStyle: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textMuted),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.notes_rounded, size: 20),
              ),
            ),
            const SizedBox(height: 16),

            if (_isSubmitting) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.3)),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.25),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.25),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.cloud_upload_rounded,
                            color: AppTheme.primaryLight,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'جاري رفع المحاضرة إلى سحابة تيليجرام',
                                style: GoogleFonts.cairo(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (_selectedFile != null)
                                Text(
                                  _selectedFile!.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.cairo(color: Colors.white70, fontSize: 11),
                                ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryLight.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            '${(_uploadProgress * 100).toInt()}%',
                            style: GoogleFonts.cairo(
                              color: AppTheme.primaryLight,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: _uploadProgress.clamp(0.0, 1.0),
                        backgroundColor: Colors.white.withValues(alpha: 0.12),
                        valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryLight),
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _uploadStatus.isNotEmpty ? _uploadStatus : 'جاري تدفق البيانات...',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.cairo(color: Colors.white60, fontSize: 11),
                          ),
                        ),
                        if (_totalBytes > 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            '${_formatFileSize(_bytesSent)} / ${_formatFileSize(_totalBytes)}',
                            style: GoogleFonts.cairo(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],

            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isSubmitting ? null : _submit,
              icon: _isSubmitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 18),
              label: Text(
                _isSubmitting
                    ? (_uploadStatus.isNotEmpty ? _uploadStatus : 'جاري النشر والمزامنة...')
                    : (_isDriveMode ? 'نشر رابط المحاضرة السحابي 🚀' : 'نشر المحاضرة للطلبة 🚀'),
                style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    ),);
  }
}
