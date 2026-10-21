import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants/app_constants.dart';
import '../core/constants/biometric_subjects.dart';
import '../core/theme/app_theme.dart';
import '../models/app_user_model.dart';
import '../services/course_customization_service.dart';
import 'app_icon_badge.dart';
import 'app_tactile_bounce.dart';
import 'course_customization_sheet.dart';

/// ── تبويب إدارة وتخصيص وإخفاء المقررات الدراسية ───────────────────
class DashboardCourseManagementTab extends StatefulWidget {
  final AppUserModel? currentUser;
  final VoidCallback? onCourseChanged;

  const DashboardCourseManagementTab({
    super.key,
    required this.currentUser,
    this.onCourseChanged,
  });

  @override
  State<DashboardCourseManagementTab> createState() => _DashboardCourseManagementTabState();
}

class _DashboardCourseManagementTabState extends State<DashboardCourseManagementTab> {
  String _courseMgmtDept = AppConstants.departments.first;
  String _courseMgmtStage = AppConstants.stages.first;
  int _courseMgmtSemester = 1;
  String _courseMgmtSearchQuery = '';

  @override
  Widget build(BuildContext context) {
    final allBiometric = BiometricSubjects.getSubjectNames(
      department: _courseMgmtDept,
      stage: _courseMgmtStage,
      semester: _courseMgmtSemester,
    );

    final customService = CourseCustomizationService();

    final filteredSubjects = allBiometric.where((name) {
      if (_courseMgmtSearchQuery.isEmpty) return true;
      final q = _courseMgmtSearchQuery.toLowerCase().trim();
      final override = customService.getOverrideFor(
        name,
        department: _courseMgmtDept,
        stage: _courseMgmtStage,
        semester: _courseMgmtSemester,
      );
      final disp = override?.displayName ?? name;
      final code = override?.customCode ?? BiometricSubjects.findSubject(
        name,
        department: _courseMgmtDept,
        stage: _courseMgmtStage,
        semester: _courseMgmtSemester,
      )?.code;
      return disp.toLowerCase().contains(q) || name.toLowerCase().contains(q) || (code != null && code.toLowerCase().contains(q));
    }).toList();

    int hiddenCount = 0;
    for (final name in allBiometric) {
      if (customService.getOverrideFor(
        name,
        department: _courseMgmtDept,
        stage: _courseMgmtStage,
        semester: _courseMgmtSemester,
      )?.isHidden == true) {
        hiddenCount++;
      }
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // لوحة اختيار القسم والمرحلة
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppTheme.lightBorder),
              boxShadow: AppShadows.card,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.school_rounded, color: AppTheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'نطاق المقررات الدراسية',
                      style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        value: _courseMgmtDept,
                        dropdownColor: Colors.white,
                        style: AppTypography.body(color: AppTheme.textPrimary),
                        decoration: InputDecoration(
                          labelText: 'القسم الأكاديمي',
                          labelStyle: AppTypography.caption(color: AppTheme.textSecondary),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                        items: AppConstants.departments.map((d) {
                          return DropdownMenuItem(
                            value: d,
                            child: Text(d, style: GoogleFonts.cairo(fontSize: 12)),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _courseMgmtDept = val);
                            CourseCustomizationService().getOverrides(
                              department: _courseMgmtDept,
                              stage: _courseMgmtStage,
                              semester: _courseMgmtSemester,
                              forceRefresh: true,
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: _courseMgmtStage,
                        dropdownColor: Colors.white,
                        style: AppTypography.body(color: AppTheme.textPrimary),
                        decoration: InputDecoration(
                          labelText: 'المرحلة',
                          labelStyle: AppTypography.caption(color: AppTheme.textSecondary),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                        items: AppConstants.stages.map((s) {
                          return DropdownMenuItem(
                            value: s,
                            child: Text(s, style: GoogleFonts.cairo(fontSize: 12)),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _courseMgmtStage = val);
                            CourseCustomizationService().getOverrides(
                              department: _courseMgmtDept,
                              stage: _courseMgmtStage,
                              semester: _courseMgmtSemester,
                              forceRefresh: true,
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // محدد الفصل الدراسي الأول / الفصل الدراسي الثاني
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppTheme.lightSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.lightBorder),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: AppTactileBounce(
                          lowerBound: 0.94,
                          onTap: () {
                            if (_courseMgmtSemester != 1) {
                              HapticFeedback.selectionClick();
                              setState(() => _courseMgmtSemester = 1);
                              CourseCustomizationService().getOverrides(
                                department: _courseMgmtDept,
                                stage: _courseMgmtStage,
                                semester: 1,
                                forceRefresh: true,
                              );
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            decoration: BoxDecoration(
                              color: _courseMgmtSemester == 1 ? Colors.white : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: _courseMgmtSemester == 1 ? AppShadows.subtle : null,
                            ),
                            child: Center(
                              child: Text(
                                'الفصل الدراسي الأول',
                                style: GoogleFonts.cairo(
                                  fontSize: 11.5,
                                  fontWeight: _courseMgmtSemester == 1 ? FontWeight.bold : FontWeight.w600,
                                  color: _courseMgmtSemester == 1 ? AppTheme.primary : AppTheme.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: AppTactileBounce(
                          lowerBound: 0.94,
                          onTap: () {
                            if (_courseMgmtSemester != 2) {
                              HapticFeedback.selectionClick();
                              setState(() => _courseMgmtSemester = 2);
                              CourseCustomizationService().getOverrides(
                                department: _courseMgmtDept,
                                stage: _courseMgmtStage,
                                semester: 2,
                                forceRefresh: true,
                              );
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            decoration: BoxDecoration(
                              color: _courseMgmtSemester == 2 ? Colors.white : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: _courseMgmtSemester == 2 ? AppShadows.subtle : null,
                            ),
                            child: Center(
                              child: Text(
                                'الفصل الدراسي الثاني',
                                style: GoogleFonts.cairo(
                                  fontSize: 11.5,
                                  fontWeight: _courseMgmtSemester == 2 ? FontWeight.bold : FontWeight.w600,
                                  color: _courseMgmtSemester == 2 ? AppTheme.primary : AppTheme.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // شريط البحث وإحصائيات سريعة
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppTheme.lightBorder),
              boxShadow: AppShadows.card,
            ),
            child: Column(
              children: [
                TextField(
                  style: AppTypography.body(color: AppTheme.textPrimary),
                  onChanged: (val) => setState(() => _courseMgmtSearchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'بحث في المقررات أو الرمز...',
                    hintStyle: AppTypography.body(color: AppTheme.textMuted),
                    prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.primary, size: 20),
                    suffixIcon: _courseMgmtSearchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () => setState(() => _courseMgmtSearchQuery = ''),
                          )
                        : null,
                    filled: true,
                    fillColor: AppTheme.lightSurface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'إجمالي المقررات: ${allBiometric.length}',
                      style: GoogleFonts.cairo(fontSize: 11.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w600),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: hiddenCount > 0 ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: hiddenCount > 0 ? const Color(0xFFFCA5A5) : const Color(0xFF86EFAC),
                        ),
                      ),
                      child: Text(
                        '$hiddenCount مخفي عن الطلاب',
                        style: GoogleFonts.cairo(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: hiddenCount > 0 ? AppTheme.danger : const Color(0xFF16A34A),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // قائمة المقررات الدراسية
          if (filteredSubjects.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: AppTheme.lightBorder),
              ),
              child: Center(
                child: Text(
                  'لا توجد مواد مطابقة للبحث في هذا القسم والمرحلة',
                  style: GoogleFonts.cairo(color: AppTheme.textMuted, fontSize: 13),
                ),
              ),
            )
          else
            ...filteredSubjects.map((origName) {
              final override = customService.getOverrideFor(
                origName,
                department: _courseMgmtDept,
                stage: _courseMgmtStage,
                semester: _courseMgmtSemester,
              );
              final subModel = BiometricSubjects.findSubject(
                origName,
                department: _courseMgmtDept,
                stage: _courseMgmtStage,
                semester: _courseMgmtSemester,
              );
              final isHidden = override?.isHidden ?? false;
              final dispName = override?.displayName ?? origName;
              final code = override?.customCode ?? subModel?.code;
              final hasOverride = override != null;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isHidden ? const Color(0xFFF8FAFC) : Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(
                    color: isHidden ? const Color(0xFFCBD5E1) : AppTheme.lightBorder,
                    width: isHidden ? 1.2 : 1.0,
                  ),
                  boxShadow: isHidden ? [] : AppShadows.card,
                ),
                child: Row(
                  children: [
                    AppIconBadge.indigo(
                      icon: BiometricSubjects.getIconForSubject(origName),
                      size: 42,
                      iconSize: 20,
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
                                  dispName,
                                  style: AppTypography.h3(
                                    color: isHidden ? const Color(0xFF64748B) : AppTheme.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (code != null) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: Text(
                                    code,
                                    style: GoogleFonts.cairo(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (dispName != origName) ...[
                            const SizedBox(height: 2),
                            Text(
                              'الاسم المرجعي بالبصمة: $origName',
                              style: AppTypography.tiny(color: AppTheme.textMuted),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: isHidden ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isHidden ? 'مخفي عن الطلاب' : 'مرئي للطلاب',
                                  style: GoogleFonts.cairo(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: isHidden ? AppTheme.danger : const Color(0xFF16A34A),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch.adaptive(
                      value: !isHidden,
                      activeColor: AppTheme.primary,
                      onChanged: (visible) async {
                        if (widget.currentUser != null) {
                          await CourseCustomizationService().toggleHideCourse(
                            originalName: origName,
                            isHidden: !visible,
                            department: _courseMgmtDept,
                            stage: _courseMgmtStage,
                            semester: _courseMgmtSemester,
                            user: widget.currentUser!,
                            currentCustomName: override?.displayName,
                            currentCustomCode: override?.customCode,
                          );
                          setState(() {});
                          widget.onCourseChanged?.call();
                        }
                      },
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.edit_note_rounded,
                        color: hasOverride ? AppTheme.primary : AppTheme.textSecondary,
                        size: 22,
                      ),
                      tooltip: 'تخصيص المقرر',
                      onPressed: () {
                        if (widget.currentUser != null) {
                          CourseCustomizationSheet.show(
                            context: context,
                            originalName: origName,
                            defaultCode: subModel?.code,
                            department: _courseMgmtDept,
                            stage: _courseMgmtStage,
                            semester: _courseMgmtSemester,
                            user: widget.currentUser!,
                            currentOverride: override,
                            onSaved: () {
                              setState(() {});
                              widget.onCourseChanged?.call();
                            },
                          );
                        }
                      },
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
