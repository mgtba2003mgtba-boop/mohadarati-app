import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/app_theme.dart';
import '../models/announcement_model.dart';
import '../models/app_user_model.dart';
import '../services/supabase_service.dart';

/// نافذة إنشاء استطلاع رأي طلابي بنمط تيليجرام المرن
class CreatePollSheet extends StatefulWidget {
  final AppUserModel currentUser;
  final String? department;
  final String? stage;
  final String? section;
  final String? subjectName;
  final Function(AnnouncementModel)? onSuccess;

  const CreatePollSheet({
    super.key,
    required this.currentUser,
    this.department,
    this.stage,
    this.section,
    this.subjectName,
    this.onSuccess,
  });

  static Future<void> show({
    required BuildContext context,
    required AppUserModel currentUser,
    String? department,
    String? stage,
    String? section,
    String? subjectName,
    Function(AnnouncementModel)? onSuccess,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: CreatePollSheet(
          currentUser: currentUser,
          department: department,
          stage: stage,
          section: section,
          subjectName: subjectName,
          onSuccess: onSuccess,
        ),
      ),
    );
  }

  @override
  State<CreatePollSheet> createState() => _CreatePollSheetState();
}

class _CreatePollSheetState extends State<CreatePollSheet> {
  final _questionController = TextEditingController();
  final List<TextEditingController> _optionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];

  bool _isSubmitting = false;
  late String _targetSection;

  @override
  void initState() {
    super.initState();
    _targetSection = widget.section ??
        (widget.currentUser.isAdmin
            ? 'ALL'
            : (widget.currentUser.section ?? 'ALL'));
  }

  @override
  void dispose() {
    _questionController.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_optionControllers.length >= 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الحد الأقصى للخيارات هو 10 خيارات')),
      );
      return;
    }
    setState(() {
      _optionControllers.add(TextEditingController());
    });
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= 2) return;
    setState(() {
      final c = _optionControllers.removeAt(index);
      c.dispose();
    });
  }

  Future<void> _submitPoll() async {
    final question = _questionController.text.trim();
    if (question.isEmpty) {
      _showError('يرجى كتابة سؤال الاستطلاع');
      return;
    }

    final options = _optionControllers
        .map((c) => c.text.trim())
        .where((text) => text.isNotEmpty)
        .toList();

    if (options.length < 2) {
      _showError('يرجى إدخال خيارين على الأقل للاستطلاع');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final pollData = PollData(
        question: question,
        options: options,
        votes: {},
        isClosed: false,
        allowsMultiple: false,
      );

      final dept = widget.department ?? widget.currentUser.department;
      final stg = widget.stage ?? widget.currentUser.stage;

      final pollContent = AnnouncementModel.embedPoll(question, pollData);

      final newPoll = AnnouncementModel(
        id: '',
        title: question.length > 50 ? '${question.substring(0, 47)}...' : question,
        content: pollContent,
        authorId: widget.currentUser.studentId,
        authorName: widget.currentUser.name,
        authorRole: widget.currentUser.role,
        department: dept,
        stage: stg,
        section: _targetSection,
        category: 'academic',
        subjectName: widget.subjectName,
        createdAt: DateTime.now(),
      );

      final ok = await SupabaseService().createAnnouncement(newPoll);
      if (!ok) throw Exception('تعذر حفظ الاستطلاع في السيرفر');

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم نشر الاستطلاع بنجاح! 📊')),
        );
        widget.onSuccess?.call(newPoll);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        _showError('خطأ أثناء النشر: $e');
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppTheme.danger),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // مقبض النافذة
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // رأس النافذة
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primarySubtle,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.poll_rounded, color: AppTheme.primary, size: 22),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'إنشاء استطلاع رأي طلابي',
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    widget.subjectName != null ? 'خاص بمقرر: ${widget.subjectName}' : 'تصويت للدفعة والشعبة',
                    style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 18),

          // 1. سؤال الاستطلاع
          TextField(
            controller: _questionController,
            maxLines: 2,
            style: GoogleFonts.cairo(fontSize: 13, color: AppTheme.textPrimary),
            decoration: InputDecoration(
              labelText: 'سؤال الاستطلاع',
              hintText: 'مثال: هل تؤيدون تأجيل كويز الرياضيات للأسبوع القادم؟',
              labelStyle: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textSecondary),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              alignLabelWithHint: true,
              prefixIcon: const Padding(
                padding: EdgeInsets.only(bottom: 24),
                child: Icon(Icons.help_outline_rounded, size: 20, color: AppTheme.primary),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 2. خيارات التصويت المرنة
          Row(
            children: [
              Text(
                'خيارات التصويت (${_optionControllers.length})',
                style: GoogleFonts.cairo(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              if (_optionControllers.length < 10)
                TextButton.icon(
                  onPressed: _addOption,
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 16, color: AppTheme.primary),
                  label: Text(
                    'إضافة خيار',
                    style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 6),

          ...List.generate(_optionControllers.length, (idx) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _optionControllers[idx],
                      style: GoogleFonts.cairo(fontSize: 13, color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        hintText: idx == 0 ? 'الخيار الأول (مثال: نعم متفق)' : (idx == 1 ? 'الخيار الثاني (مثال: لا غير متفق)' : 'خيار ${idx + 1}'),
                        hintStyle: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textMuted),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        prefixIcon: Icon(
                          Icons.radio_button_unchecked_rounded,
                          size: 16,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ),
                  ),
                  if (_optionControllers.length > 2) ...[
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline_rounded, color: Colors.redAccent, size: 20),
                      onPressed: () => _removeOption(idx),
                      tooltip: 'حذف الخيار',
                    ),
                  ],
                ],
              ),
            );
          }),

          const SizedBox(height: 6),

          // 4. الشعبة المستهدفة (إذا كان مسؤولاً)
          if (widget.currentUser.isAdmin) ...[
            DropdownButtonFormField<String>(
              value: _targetSection,
              dropdownColor: Colors.white,
              style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: 'الشعبة المستهدفة بالتصويت',
                labelStyle: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textSecondary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.groups_rounded, size: 20, color: AppTheme.primary),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: const [
                DropdownMenuItem(value: 'ALL', child: Text('🌐 جميع الشعب (عام لكافة الطلاب)')),
                DropdownMenuItem(value: 'A', child: Text('🏷️ شعبة A')),
                DropdownMenuItem(value: 'B', child: Text('🏷️ شعبة B')),
                DropdownMenuItem(value: 'C', child: Text('🏷️ شعبة C')),
                DropdownMenuItem(value: 'D', child: Text('🏷️ شعبة D')),
                DropdownMenuItem(value: 'E', child: Text('🏷️ شعبة E')),
                DropdownMenuItem(value: 'F', child: Text('🏷️ شعبة F')),
              ],
              onChanged: (val) => setState(() => _targetSection = val ?? 'ALL'),
            ),
            const SizedBox(height: 14),
          ],

          // زر النشر
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _isSubmitting ? null : _submitPoll,
            icon: _isSubmitting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.how_to_vote_rounded, size: 18),
            label: Text(
              _isSubmitting ? 'جاري إنشاء الاستطلاع...' : 'نشر الاستطلاع للطلاب 📊',
              style: GoogleFonts.cairo(fontSize: 13.5, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
