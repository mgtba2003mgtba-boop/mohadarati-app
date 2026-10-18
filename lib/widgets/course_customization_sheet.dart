import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/app_theme.dart';
import '../models/app_user_model.dart';
import '../models/course_override_model.dart';
import '../services/course_customization_service.dart';
import 'app_tactile_bounce.dart';

/// ورقة سفلية لتخصيص المقرر الدراسي (تعديل الاسم المعروض، الرمز الأكاديمي، وإخفاء المقرر)
class CourseCustomizationSheet extends StatefulWidget {
  final String originalName;
  final String? defaultCode;
  final String department;
  final String stage;
  final AppUserModel user;
  final CourseOverrideModel? currentOverride;
  final VoidCallback? onSaved;

  const CourseCustomizationSheet({
    super.key,
    required this.originalName,
    this.defaultCode,
    required this.department,
    required this.stage,
    required this.user,
    this.currentOverride,
    this.onSaved,
  });

  static Future<void> show({
    required BuildContext context,
    required String originalName,
    String? defaultCode,
    required String department,
    required String stage,
    required AppUserModel user,
    CourseOverrideModel? currentOverride,
    VoidCallback? onSaved,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: CourseCustomizationSheet(
          originalName: originalName,
          defaultCode: defaultCode,
          department: department,
          stage: stage,
          user: user,
          currentOverride: currentOverride,
          onSaved: onSaved,
        ),
      ),
    );
  }

  @override
  State<CourseCustomizationSheet> createState() => _CourseCustomizationSheetState();
}

class _CourseCustomizationSheetState extends State<CourseCustomizationSheet> {
  late final TextEditingController _displayNameController;
  late final TextEditingController _codeController;
  late bool _isHidden;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController(
      text: widget.currentOverride?.displayName ?? widget.originalName,
    );
    _codeController = TextEditingController(
      text: widget.currentOverride?.customCode ?? widget.defaultCode ?? '',
    );
    _isHidden = widget.currentOverride?.isHidden ?? false;
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final customName = _displayNameController.text.trim();
    final customCode = _codeController.text.trim();

    if (customName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'يرجى إدخال اسم المقرر المعروض',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    final override = CourseOverrideModel(
      originalName: widget.originalName,
      displayName: customName,
      customCode: customCode.isNotEmpty ? customCode : null,
      isHidden: _isHidden,
      department: widget.department,
      stage: widget.stage,
      updatedAt: DateTime.now(),
      updatedBy: widget.user.name,
    );

    final success = await CourseCustomizationService().saveOverride(
      override,
      user: widget.user,
    );

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        widget.onSaved?.call();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم حفظ تخصيصات المقرر بنجاح',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
            backgroundColor: AppTheme.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تعذر حفظ التخصيصات، يرجى المحاولة لاحقاً',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  Future<void> _handleReset() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Text(
          'استعادة الافتراضي',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Text(
          'هل أنت متأكد من إلغاء كافة التخصيصات واستعادة الاسم والرمز الأصلي وإظهار المقرر لجميع الطلبة؟',
          style: GoogleFonts.cairo(fontSize: 13, color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('إلغاء', style: GoogleFonts.cairo(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('استعادة الافتراضي', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isSaving = true);
    final success = await CourseCustomizationService().resetOverride(
      originalName: widget.originalName,
      department: widget.department,
      stage: widget.stage,
      user: widget.user,
    );

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        widget.onSaved?.call();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تمت استعادة الإعدادات الأصلية للمقرر',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
            backgroundColor: AppTheme.primary,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasOverride = widget.currentOverride != null;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // شريط السحب العلوي
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // عنوان الورقة
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primarySubtle,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.tune_rounded, color: AppTheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تخصيص المقرر الدراسي',
                      style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      'الاسم المرجعي بالبصمة: ${widget.originalName}',
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (hasOverride)
                IconButton(
                  tooltip: 'استعادة الافتراضي',
                  icon: const Icon(Icons.restart_alt_rounded, color: AppTheme.danger),
                  onPressed: _isSaving ? null : _handleReset,
                ),
            ],
          ),
          const SizedBox(height: 18),

          // حقل اسم المقرر المعروض
          Text(
            'اسم المقرر المعروض للطلبة',
            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _displayNameController,
            style: AppTypography.body(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: widget.originalName,
              prefixIcon: const Icon(Icons.title_rounded, color: AppTheme.primary, size: 20),
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
          ),
          const SizedBox(height: 14),

          // حقل رمز المقرر
          Text(
            'رمز المقرر الأكاديمي (اختياري)',
            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _codeController,
            style: AppTypography.body(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: widget.defaultCode ?? 'مثال: CET1101',
              prefixIcon: const Icon(Icons.tag_rounded, color: AppTheme.primary, size: 20),
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
          ),
          const SizedBox(height: 14),

          // مفتاح إخفاء المقرر عن الطلاب
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _isHidden ? const Color(0xFFFEF2F2) : AppTheme.lightSurface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: _isHidden ? const Color(0xFFFCA5A5) : AppTheme.lightBorder,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _isHidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  color: _isHidden ? AppTheme.danger : AppTheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'إخفاء المقرر عن الطلبة',
                        style: GoogleFonts.cairo(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _isHidden ? AppTheme.danger : AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        _isHidden
                            ? 'المقرر مخفي حالياً ولن يظهر في شاشة الطلبة'
                            : 'المقرر مرئي ومتاح لجميع طلبة المرحلة',
                        style: GoogleFonts.cairo(
                          fontSize: 10.5,
                          color: _isHidden ? const Color(0xFFB91C1C) : AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: _isHidden,
                  activeThumbColor: AppTheme.danger,
                  onChanged: (val) => setState(() => _isHidden = val),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // زر حفظ التغييرات
          AppTactileBounce(
            onTap: _isSaving ? null : _handleSave,
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(AppRadius.md),
                boxShadow: AppShadows.primaryGlow,
              ),
              alignment: Alignment.center,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      'حفظ التعديلات',
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
