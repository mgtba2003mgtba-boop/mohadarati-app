import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import '../core/theme/app_theme.dart';
import '../models/app_user_model.dart';
import '../models/lecture_model.dart';
import '../models/announcement_model.dart';
import '../services/supabase_service.dart';
import '../services/telegram_uploader_service.dart';

class PublishToSubjectSheet extends StatefulWidget {
  final String subjectName;
  final String department;
  final String stage;
  final String? section;
  final int semester;
  final AppUserModel? currentUser;
  final String initialMode;
  final Function(LectureModel optimisticLecture, PlatformFile? file, String? driveUrl)? onOptimisticLecture;
  final Function(AnnouncementModel optimisticAnnounce, PlatformFile? image)? onOptimisticAnnouncement;

  const PublishToSubjectSheet({super.key, 
    required this.subjectName,
    required this.department,
    required this.stage,
    this.section,
    this.semester = 1,
    required this.currentUser,
    this.initialMode = 'lecture',
    this.onOptimisticLecture,
    this.onOptimisticAnnouncement,
  });

  @override
  State<PublishToSubjectSheet> createState() => PublishToSubjectSheetState();
}

class PublishToSubjectSheetState extends State<PublishToSubjectSheet> {
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
    } else if (widget.currentUser?.assignedSections.isNotEmpty == true) {
      _targetSection = widget.currentUser!.assignedSections.first;
    } else {
      _targetSection = 'ALL';
    }
  }

  // حقول المحاضرة
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _driveUrlController = TextEditingController();
  String _lectureType = 'theory'; // 'theory', 'practical'
  String _targetSection = 'ALL';
  bool _isDriveLinkMode = false;
  List<PlatformFile> _selectedFiles = [];
  Map<String, int> _fileSizes = {};
  bool _isPickingFile = false;
  String _uploadStatus = '';
  double _uploadProgress = 0.0;
  int _currentFileBytesSent = 0;
  int _currentFileTotalBytes = 0;
  int _currentFileIndex = 0;
  String _currentFileName = '';

  // حقول التبليغ
  final _announceContentController = TextEditingController();
  PlatformFile? _selectedAnnouncementImage;
  int _selectedAnnouncementImageSize = 0;
  bool _isPickingAnnouncementImage = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _driveUrlController.dispose();
    _announceContentController.dispose();
    super.dispose();
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

  Future<void> _pickFile() async {
    setState(() => _isPickingFile = true);
    final files = await TelegramUploaderService().pickLectureFiles();
    if (mounted) {
      if (files.isNotEmpty) {
        final Map<String, int> newSizes = Map.from(_fileSizes);
        for (final f in files) {
          final size = await TelegramUploaderService().getFileSize(f);
          newSizes[f.name] = size;
        }
        setState(() {
          _isPickingFile = false;
          for (final f in files) {
            if (!_selectedFiles.any((existing) => existing.name == f.name)) {
              _selectedFiles.add(f);
            }
          }
          _fileSizes = newSizes;
          if (_titleController.text.trim().isEmpty && _selectedFiles.isNotEmpty) {
            final firstFile = _selectedFiles.first;
            final nameWithoutExt = firstFile.name.contains('.')
                ? firstFile.name.substring(0, firstFile.name.lastIndexOf('.'))
                : firstFile.name;
            _titleController.text = nameWithoutExt;
          }
        });
      } else {
        setState(() => _isPickingFile = false);
      }
    }
  }

  int get _totalSelectedSize {
    return _selectedFiles.fold<int>(0, (int sum, PlatformFile f) => sum + (_fileSizes[f.name] ?? (f.lengthSync() ?? 0)));
  }

  IconData _getFileIcon(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf_rounded;
    if (lower.endsWith('.mp4') || lower.endsWith('.mkv') || lower.endsWith('.avi') || lower.endsWith('.mov') || lower.endsWith('.webm')) {
      return Icons.video_collection_rounded;
    }
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) return Icons.description_rounded;
    if (lower.endsWith('.ppt') || lower.endsWith('.pptx')) return Icons.slideshow_rounded;
    if (lower.endsWith('.zip') || lower.endsWith('.rar') || lower.endsWith('.7z')) return Icons.folder_zip_rounded;
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png') || lower.endsWith('.webp')) {
      return Icons.image_rounded;
    }
    return Icons.insert_drive_file_rounded;
  }

  String _formatFileSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} غيغابايت';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} ميغابايت';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} كيلوبايت';
    } else {
      return '$bytes بايت';
    }
  }

  Future<void> _submitLecture() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _showSnack('يرجى كتابة عنوان المحاضرة', isError: true);
      return;
    }

    String? driveUrl;
    if (_isDriveLinkMode) {
      driveUrl = _driveUrlController.text.trim();
      if (driveUrl.isEmpty) {
        _showSnack('يرجى إدخال رابط Google Drive أو الرابط السحابي للمحاضرة', isError: true);
        return;
      }
      final parsedUri = Uri.tryParse(driveUrl);
      if (parsedUri == null || !parsedUri.hasScheme || (!driveUrl.startsWith('https://') && !driveUrl.startsWith('http://'))) {
        _showSnack('يرجى إدخال رابط ويب صالح يبدأ بـ https://', isError: true);
        return;
      }
    } else {
      if (_selectedFiles.isEmpty) {
        _showSnack('يرجى اختيار ملف المحاضرة (أو عدة ملفات)', isError: true);
        return;
      }
    }

    // ── في حال وضع الرابط السحابي (Google Drive): نشر فوري سريع ──
    if (_isDriveLinkMode) {
      if (widget.onOptimisticLecture != null) {
        final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
        final optimisticLecture = LectureModel(
          id: tempId,
          title: title,
          subjectName: widget.subjectName,
          department: widget.department,
          stage: widget.stage,
          section: _targetSection,
          semester: widget.semester,
          type: _lectureType,
          driveUrl: driveUrl!,
          description: _descController.text.trim().isNotEmpty ? _descController.text.trim() : null,
          uploaderId: widget.currentUser?.studentId ?? 'ADMIN',
          uploaderName: widget.currentUser?.name ?? 'ممثل الشعبة',
          uploaderRole: widget.currentUser?.role ?? 'representative',
          createdAt: DateTime.now(),
        );

        Navigator.pop(context, true);
        widget.onOptimisticLecture!(optimisticLecture, null, driveUrl);
        return;
      }

      setState(() => _isSubmitting = true);
      try {
        final newLecture = LectureModel(
          id: '',
          title: title,
          subjectName: widget.subjectName,
          department: widget.department,
          stage: widget.stage,
          section: _targetSection,
          semester: widget.semester,
          type: _lectureType,
          driveUrl: driveUrl!,
          description: _descController.text.trim().isNotEmpty ? _descController.text.trim() : null,
          uploaderId: widget.currentUser?.studentId ?? 'ADMIN',
          uploaderName: widget.currentUser?.name ?? 'ممثل الشعبة',
          uploaderRole: widget.currentUser?.role ?? 'representative',
          createdAt: DateTime.now(),
        );

        final ok = await SupabaseService().createLecture(newLecture);
        if (!ok) throw Exception('تعذر حفظ بيانات المحاضرة في السحابة');

        if (mounted) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم نشر رابط المحاضرة السحابي بنجاح')),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isSubmitting = false);
          _showSnack('خطأ أثناء النشر: $e', isError: true);
        }
      }
      return;
    }

    // ── وضع رفع الملفات المباشر: تتبع حي للبايتات ونسبة التقدم حتى 100% ──
    setState(() {
      _isSubmitting = true;
      _uploadProgress = 0.05;
      _currentFileIndex = 0;
      _uploadStatus = _selectedFiles.length > 1
          ? 'جاري تجهيز رفع ${_selectedFiles.length} ملفات...'
          : 'جاري قراءة وتجهيز ملف المحاضرة...';
    });

    int successCount = 0;
    List<String> failedFiles = [];

    for (int i = 0; i < _selectedFiles.length; i++) {
      final file = _selectedFiles[i];
      final fileTitle = _selectedFiles.length == 1
          ? title
          : (_selectedFiles.length > 1 && title.isNotEmpty
              ? '$title (${i + 1}/${_selectedFiles.length})'
              : file.name);

      final fileSize = _fileSizes[file.name] ?? (file.lengthSync() ?? 0);

      if (mounted) {
        setState(() {
          _currentFileIndex = i;
          _currentFileName = file.name;
          _currentFileBytesSent = 0;
          _currentFileTotalBytes = fileSize;
          _uploadProgress = 0.05;
          _uploadStatus = 'جاري رفع (${i + 1}/${_selectedFiles.length}): ${file.name}';
        });
      }

      try {
        final res = await TelegramUploaderService().uploadLecture(
          file: file,
          title: fileTitle,
          subjectName: widget.subjectName,
          department: widget.department,
          stage: widget.stage,
          section: _targetSection,
          semester: widget.semester,
          lectureType: _lectureType,
          description: _descController.text.trim().isNotEmpty ? _descController.text.trim() : null,
          uploaderId: widget.currentUser?.studentId ?? 'ADMIN',
          uploaderName: widget.currentUser?.name ?? 'ممثل الشعبة',
          uploaderRole: widget.currentUser?.role ?? 'representative',
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
                _currentFileBytesSent = sent;
                _currentFileTotalBytes = total;
                _uploadProgress = prog;
                _uploadStatus = status;
              });
            }
          },
        );

        if (!res.success) {
          throw Exception(res.message);
        }
        successCount++;
      } catch (err) {
        debugPrint('[-] Error uploading file ${file.name}: $err');
        failedFiles.add(file.name);
      }
    }

    if (mounted) {
      if (successCount > 0) {
        setState(() {
          _uploadProgress = 1.0;
          _uploadStatus = _selectedFiles.length == 1
              ? 'تم رفع ونشر المحاضرة بنجاح 🚀'
              : 'تم رفع بنجاح $successCount من أصل ${_selectedFiles.length} محاضرات 🚀';
        });
        await Future.delayed(const Duration(milliseconds: 900));
        if (mounted) {
          Navigator.pop(context, true);
          final msg = _selectedFiles.length == 1
              ? 'تم رفع ونشر المحاضرة بنجاح 🚀'
              : 'تم رفع بنجاح $successCount من أصل ${_selectedFiles.length} محاضرات 🚀';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: AppTheme.primary,
            ),
          );
        }
      } else {
        setState(() => _isSubmitting = false);
        _showSnack('فشل رفع الملفات: ${failedFiles.join(", ")}', isError: true);
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
        : (firstLine.isNotEmpty ? firstLine : widget.subjectName);

    // ── نمط Optimistic UI الفائق للتبليغات: إغلاق فوري للنافذة ونقل الرفع للخلفية ──
    if (widget.onOptimisticAnnouncement != null) {
      final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
      final announceSection = _targetSection.isNotEmpty ? _targetSection : (widget.currentUser?.section ?? 'ALL');
      final optimisticAnnounce = AnnouncementModel(
        id: tempId,
        title: autoTitle,
        content: content,
        authorId: widget.currentUser?.studentId ?? 'ADMIN',
        authorName: widget.currentUser?.name ?? 'ممثل الشعبة',
        authorRole: widget.currentUser?.role ?? 'representative',
        department: widget.department,
        stage: widget.stage,
        section: announceSection,
        category: 'academic',
        imageUrl: null,
        subjectName: widget.subjectName,
        createdAt: DateTime.now(),
      );

      Navigator.pop(context);
      widget.onOptimisticAnnouncement!(optimisticAnnounce, _selectedAnnouncementImage);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      String? uploadedImageUrl;

      if (_selectedAnnouncementImage != null) {
        final uploadRes = await TelegramUploaderService().uploadFileToTelegram(
          file: _selectedAnnouncementImage!,
          caption: '$autoTitle • ${widget.subjectName}',
          fileType: 'announcement',
        );

        if (!uploadRes.success || uploadRes.fileUrl == null) {
          throw Exception(uploadRes.message.isNotEmpty ? uploadRes.message : 'فشل رفع صورة التبليغ إلى سحابة تيليجرام');
        }
        uploadedImageUrl = uploadRes.fileUrl;
      }

      final announceSection = _targetSection.isNotEmpty ? _targetSection : (widget.currentUser?.section ?? 'ALL');

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
        imageUrl: uploadedImageUrl,
        subjectName: widget.subjectName,
        createdAt: DateTime.now(),
      );

      final ok = await SupabaseService().createAnnouncement(newAnnounce);
      if (!ok) throw Exception('تعذر حفظ التبليغ');

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم نشر التبليغ بنجاح')),
        );
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
                    onPressed: _isSubmitting ? null : () => Navigator.pop(context),
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

              // الشعبة الدراسية المستهدفة بالمحاضرة
              if (widget.currentUser?.isAdmin == true || (widget.currentUser?.assignedSections.isNotEmpty == true)) ...[
                DropdownButtonFormField<String>(
                  value: (widget.currentUser?.isAdmin == true || widget.currentUser?.assignedSections.contains(_targetSection) == true || _targetSection == 'ALL')
                      ? _targetSection
                      : (widget.currentUser?.assignedSections.first ?? 'ALL'),
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
                    const DropdownMenuItem(value: 'ALL', child: Text('جميع الشعب')),
                    if (widget.currentUser?.isAdmin == true) ...const [
                      DropdownMenuItem(value: 'A', child: Text('شعبة A')),
                      DropdownMenuItem(value: 'B', child: Text('شعبة B')),
                      DropdownMenuItem(value: 'C', child: Text('شعبة C')),
                      DropdownMenuItem(value: 'D', child: Text('شعبة D')),
                      DropdownMenuItem(value: 'E', child: Text('شعبة E')),
                      DropdownMenuItem(value: 'F', child: Text('شعبة F')),
                    ] else ...[
                      for (final sec in widget.currentUser!.assignedSections.where((s) => s != 'ALL'))
                        DropdownMenuItem(value: sec, child: Text('شعبة $sec')),
                    ],
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _targetSection = val);
                  },
                ),
                const SizedBox(height: 12),
              ],

              // التبديل بين رفع ملف مباشر ورابط سحابي / درايف
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        backgroundColor: !_isDriveLinkMode ? AppTheme.primary.withValues(alpha: 0.12) : Colors.transparent,
                        side: BorderSide(color: !_isDriveLinkMode ? AppTheme.primary : Colors.grey.shade300, width: !_isDriveLinkMode ? 1.5 : 1),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onPressed: () => setState(() => _isDriveLinkMode = false),
                      icon: Icon(Icons.attach_file_rounded, size: 16, color: !_isDriveLinkMode ? AppTheme.primary : AppTheme.textSecondary),
                      label: Text(
                        'ملف مباشر',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: !_isDriveLinkMode ? AppTheme.primary : AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        backgroundColor: _isDriveLinkMode ? AppTheme.accent.withValues(alpha: 0.15) : Colors.transparent,
                        side: BorderSide(color: _isDriveLinkMode ? AppTheme.accent : Colors.grey.shade300, width: _isDriveLinkMode ? 1.5 : 1),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onPressed: () => setState(() => _isDriveLinkMode = true),
                      icon: Icon(Icons.link_rounded, size: 16, color: _isDriveLinkMode ? AppTheme.accent : AppTheme.textSecondary),
                      label: Text(
                        'رابط سحابي',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _isDriveLinkMode ? AppTheme.accent : AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // مساحة الإدخال بناءً على الوضع المختار
              if (_isDriveLinkMode) ...[
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
                if (_selectedFiles.isEmpty) ...[
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
                      'اختر ملفات المحاضرة (ملازم، PDF، عروض، فيديوهات)',
                      style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
                    ),
                    onPressed: _isPickingFile ? null : _pickFile,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, right: 4),
                    child: Text(
                      '💡 يمكنك اختيار ملف واحد أو عدة ملفات معاً دفعة واحدة وبأي حجم',
                      style: GoogleFonts.cairo(fontSize: 10, color: AppTheme.textSecondary),
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.folder_copy_rounded, color: AppTheme.primary, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_selectedFiles.length} ملفات محددة • الحجم الإجمالي: ${_formatFileSize(_totalSelectedSize)}',
                            style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primary),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _isPickingFile ? null : _pickFile,
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: Text('إضافة ملفات', style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold)),
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(_selectedFiles.length, (idx) {
                    final file = _selectedFiles[idx];
                    final size = _fileSizes[file.name] ?? (file.lengthSync() ?? 0);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.lightBorder),
                      ),
                      child: Row(
                        children: [
                          Icon(_getFileIcon(file.name), color: AppTheme.primary, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  file.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  _formatFileSize(size),
                                  style: GoogleFonts.cairo(fontSize: 9.5, color: AppTheme.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 16, color: AppTheme.danger),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => setState(() {
                              _selectedFiles.removeAt(idx);
                              _fileSizes.remove(file.name);
                            }),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
              const SizedBox(height: 12),

              // ملاحظات وتفاصيل إضافية للمحاضرة
              TextField(
                controller: _descController,
                maxLines: 2,
                style: GoogleFonts.cairo(fontSize: 13, color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'ملاحظات وتفاصيل إضافية للطلبة (اختياري)',
                  hintText: 'مثال: ملخص الفصل أو واجبات مطلوبة...',
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
                                  _selectedFiles.length > 1
                                      ? 'جاري رفع المحاضرة (${_currentFileIndex + 1} من ${_selectedFiles.length})'
                                      : 'جاري رفع المحاضرة إلى سحابة تيليجرام',
                                  style: GoogleFonts.cairo(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (_currentFileName.isNotEmpty)
                                  Text(
                                    _currentFileName,
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
                          if (_currentFileTotalBytes > 0) ...[
                            const SizedBox(width: 8),
                            Text(
                              '${_formatFileSize(_currentFileBytesSent)} / ${_formatFileSize(_currentFileTotalBytes)}',
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
                onPressed: _isSubmitting ? null : _submitLecture,
                icon: _isSubmitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 18),
                label: Text(
                  _isSubmitting
                      ? (_uploadStatus.isNotEmpty ? _uploadStatus : 'جاري النشر والمزامنة...')
                      : (_isDriveLinkMode
                          ? 'نشر رابط المحاضرة السحابي للمادة'
                          : (_selectedFiles.length > 1
                              ? 'نشر ${_selectedFiles.length} محاضرات للمادة دفعة واحدة 🚀'
                              : 'نشر المحاضرة للمادة')),
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

              // مساحة إرفاق صورة للتبليغ (اختياري)
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
                    'إرفاق صورة (اختياري)',
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
                              '${_formatFileSize(_selectedAnnouncementImageSize)} • جاهز للنشر',
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

              // الشعبة المستهدفة بالتبليغ
              if (widget.currentUser?.isAdmin == true || (widget.currentUser?.hasMultipleSections == true)) ...[
                DropdownButtonFormField<String>(
                  value: (widget.currentUser?.isAdmin == true || widget.currentUser?.assignedSections.contains(_targetSection) == true || _targetSection == 'ALL')
                      ? _targetSection
                      : (widget.currentUser?.assignedSections.first ?? 'ALL'),
                  dropdownColor: Colors.white,
                  style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'الشعبة المستهدفة بالتبليغ',
                    labelStyle: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textSecondary),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.groups_rounded, size: 20, color: AppTheme.accent),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: [
                    const DropdownMenuItem(value: 'ALL', child: Text('جميع الشعب')),
                    if (widget.currentUser?.isAdmin == true) ...const [
                      DropdownMenuItem(value: 'A', child: Text('شعبة A')),
                      DropdownMenuItem(value: 'B', child: Text('شعبة B')),
                      DropdownMenuItem(value: 'C', child: Text('شعبة C')),
                      DropdownMenuItem(value: 'D', child: Text('شعبة D')),
                      DropdownMenuItem(value: 'E', child: Text('شعبة E')),
                      DropdownMenuItem(value: 'F', child: Text('شعبة F')),
                    ] else ...[
                      for (final sec in widget.currentUser!.assignedSections.where((s) => s != 'ALL'))
                        DropdownMenuItem(value: sec, child: Text('شعبة $sec')),
                    ],
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
                  _isSubmitting ? 'جاري النشر...' : 'نشر التبليغ',
                  style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ],
          ],
        ),
      ),
    ),);
  }
}

// ══════════════════════════════════════════════════════════════
// نافذة الاستفسارات والملاحظات الأكاديمية للمحاضرة
