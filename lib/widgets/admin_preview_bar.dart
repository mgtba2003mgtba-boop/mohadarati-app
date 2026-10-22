import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../models/app_user_model.dart';
import '../services/admin_preview_service.dart';

/// ── شريط المعاينة والتبديل السريع للآدمن (Admin Section & Stage Switcher) ──
/// يتيح للمشرف العام التنقل الفوري بين كافة الأقسام والمراحل والشُعب
/// وتحديث كافة بيانات الشاشة الحالية فورياً
class AdminPreviewBar extends StatelessWidget {
  final AppUserModel? currentUser;
  final VoidCallback onContextChanged;

  const AdminPreviewBar({
    super.key,
    required this.currentUser,
    required this.onContextChanged,
  });

  bool get _isAdmin {
    if (currentUser == null) return false;
    return currentUser!.isAdmin ||
        currentUser!.studentId == 'ST-NUST-001630760-413' ||
        currentUser!.studentId == 'ST-NUST-001630760-413';
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: AdminPreviewService(),
      builder: (context, _) {
        final service = AdminPreviewService();
        final currentDept = service.department;
        final currentStage = service.stage;
        final currentSec = service.section ?? 'ALL';
        final isCustom = service.isCustomActive;

        return Container(
          margin: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF1E293B),
                isCustom ? AppTheme.accent.withValues(alpha: 0.15) : const Color(0xFF0F172A),
              ],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isCustom ? AppTheme.accent.withValues(alpha: 0.6) : Colors.white12,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // العنوان والشارة وزر إعادة التعيين
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.remove_red_eye_rounded, color: AppTheme.accent, size: 14),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'معاينة كطالب (خاص بالآدمن)',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accent,
                        ),
                      ),
                      if (isCustom) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'مُخصّص',
                            style: GoogleFonts.cairo(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (isCustom)
                    InkWell(
                      onTap: () {
                        service.reset(currentUser);
                        onContextChanged();
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Row(
                          children: [
                            const Icon(Icons.restart_alt_rounded, size: 13, color: Color(0xFF94A3B8)),
                            const SizedBox(width: 3),
                            Text(
                              'الافتراضي',
                              style: GoogleFonts.cairo(fontSize: 10, color: const Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),

              // شرائح التبديل السريع (القسم، المرحلة، الشعبة)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // شريحة القسم
                    _buildFilterChip(
                      context: context,
                      label: _shortenDept(currentDept),
                      icon: Icons.account_balance_rounded,
                      isActive: true,
                      onTap: () => _showDeptPicker(context, service),
                    ),
                    const SizedBox(width: 6),

                    // شريحة المرحلة
                    _buildFilterChip(
                      context: context,
                      label: currentStage,
                      icon: Icons.layers_rounded,
                      isActive: true,
                      onTap: () => _showStagePicker(context, service),
                    ),
                    const SizedBox(width: 6),

                    // شريحة الشعبة
                    _buildFilterChip(
                      context: context,
                      label: currentSec == 'ALL' ? 'كل الشُعب' : 'شعبة $currentSec',
                      icon: Icons.groups_rounded,
                      isActive: true,
                      onTap: () => _showSectionPicker(context, service),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterChip({
    required BuildContext context,
    required String label,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: AppTheme.accent),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.cairo(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.arrow_drop_down_rounded, size: 16, color: Colors.white54),
          ],
        ),
      ),
    );
  }

  String _shortenDept(String dept) {
    if (dept.contains('الحاسوب')) return 'تقنيات الحاسوب';
    if (dept.contains('السيبراني')) return 'الأمن السيبراني';
    if (dept.contains('الطبية')) return 'الأجهزة الطبية';
    return dept;
  }

  void _showDeptPicker(BuildContext context, AdminPreviewService service) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'اختر القسم للمعاينة',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 12),
                ...AppConstants.departments.map((dept) {
                  final isSelected = service.department == dept;
                  return ListTile(
                    dense: true,
                    title: Text(
                      dept,
                      style: GoogleFonts.cairo(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? AppTheme.accent : Colors.white70,
                      ),
                    ),
                    trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: AppTheme.accent, size: 18) : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      service.setDepartment(dept);
                      onContextChanged();
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showStagePicker(BuildContext context, AdminPreviewService service) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'اختر المرحلة للمعاينة',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 12),
                ...AppConstants.stages.map((stage) {
                  final isSelected = service.stage == stage;
                  return ListTile(
                    dense: true,
                    title: Text(
                      stage,
                      style: GoogleFonts.cairo(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? AppTheme.accent : Colors.white70,
                      ),
                    ),
                    trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: AppTheme.accent, size: 18) : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      service.setStage(stage);
                      onContextChanged();
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSectionPicker(BuildContext context, AdminPreviewService service) {
    final sections = ['A', 'B', 'C', 'D', 'ALL'];
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'اختر الشعبة للمعاينة',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 12),
                ...sections.map((sec) {
                  final isAll = sec == 'ALL';
                  final isSelected = isAll ? service.section == null : service.section == sec;
                  return ListTile(
                    dense: true,
                    title: Text(
                      isAll ? 'عرض كل الشُعب (ALL)' : 'الشعبة $sec',
                      style: GoogleFonts.cairo(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? AppTheme.accent : Colors.white70,
                      ),
                    ),
                    trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: AppTheme.accent, size: 18) : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      service.setSection(isAll ? null : sec);
                      onContextChanged();
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}
