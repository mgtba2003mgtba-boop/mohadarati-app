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
  PlatformFile? _selectedFile;
  int _selectedFileSize = 0;
  bool _isPickingFile = false;

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
      if (_selectedFile == null) {
        _showSnack('يرجى اختيار ملف المحاضرة (PDF / مستند / صورة)', isError: true);
        return;
      }

      if (_selectedFileSize > 50 * 1024 * 1024) {
        _showSnack(
          'حجم الملف (${_formatFileSize(_selectedFileSize)}) يتجاوز حد تيليجرام المباشر (50MB). يرجى التبديل لخيار "رابط سحابي / Google Drive".',
          isError: true,
        );
        return;
      }
    }

    // ── نمط Optimistic UI الفائق: إغلاق النافذة فوراً ونقل المهمة للخلفية ──
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
        driveUrl: _isDriveLinkMode ? (driveUrl ?? '') : '',
        description: _descController.text.trim().isNotEmpty ? _descController.text.trim() : null,
        uploaderId: widget.currentUser?.studentId ?? 'ADMIN',
        uploaderName: widget.currentUser?.name ?? 'ممثل الشعبة',
        uploaderRole: widget.currentUser?.role ?? 'representative',
        fileName: _selectedFile?.name,
        fileSizeBytes: _selectedFileSize > 0 ? _selectedFileSize : null,
        createdAt: DateTime.now(),
      );

      Navigator.pop(context);
      widget.onOptimisticLecture!(optimisticLecture, _selectedFile, _isDriveLinkMode ? driveUrl : null);
      return;
    }

    if (_isDriveLinkMode) {
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
    } else {
      setState(() => _isSubmitting = true);
      try {
        final res = await TelegramUploaderService().uploadLecture(
          file: _selectedFile!,
          title: title,
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
        );

        if (!res.success) {
          throw Exception(res.message);
        }

        if (mounted) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم رفع ونشر المحاضرة بنجاح')),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isSubmitting = false);
          _showSnack(
            'خطأ أثناء النشر: $e. يمكنك استخدام خيار "رابط سحابي / Google Drive" كبديل مباشر.',
            isError: true,
          );
        }
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
    return Container(
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
                  onPressed: () => Navigator.pop(context),
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
                      ? 'جاري النشر والمزامنة...'
                      : (_isDriveLinkMode ? 'نشر رابط المحاضرة السحابي للمادة' : 'نشر المحاضرة للمادة'),
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
    );
  }
}

// ══════════════════════════════════════════════════════════════
// نافذة الاستفسارات والملاحظات الأكاديمية للمحاضرة
