import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../models/app_user_model.dart';
import '../services/supabase_service.dart';
import 'onboarding_screen.dart';
import 'dashboard_screen.dart';
import '../services/admin_preview_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  AppUserModel? _user;

  bool get _isMujtabaAdmin =>
      _user?.isAdmin == true ||
      _user?.studentId == 'ST-NUST-001630760-413' ||
      (_user?.name.contains('مجتبى') ?? false);

  @override
  void initState() {
    super.initState();
    _user = SupabaseService().currentUser;
  }

  Future<void> _openTelegramBot() async {
    final uri = Uri.parse(AppConstants.telegramBotUrl);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  Future<void> _openSupportTelegram() async {
    final uri = Uri.parse(AppConstants.supportTelegramUrl);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'تسجيل الخروج',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        content: Text(
          'هل تريد تسجيل الخروج؟',
          style: GoogleFonts.cairo(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('إلغاء', style: GoogleFonts.cairo(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('تسجيل الخروج', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await SupabaseService().logout();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const OnboardingScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_user == null) {
      return const Center(child: Text('غير مسجل'));
    }

    return Scaffold(
      backgroundColor: AppTheme.lightBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'حسابي',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 17, color: AppTheme.textPrimary),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          children: [
            // صورة ومعلومات الطالب
            Center(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(3.5),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFF8B5CF6), Color(0xFF0EA5E9)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 44,
                      backgroundColor: Colors.white,
                      backgroundImage: (_user!.photoUrl != null && _user!.photoUrl!.isNotEmpty)
                          ? NetworkImage(_user!.photoUrl!)
                          : null,
                      child: (_user!.photoUrl == null || _user!.photoUrl!.isEmpty)
                          ? const Icon(Icons.person, size: 50, color: Color(0xFF8B5CF6))
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _user!.name,
                    style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F3FF),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFDDD6FE)),
                    ),
                    child: Text(
                      _user!.roleLabel,
                      style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF7C3AED)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // بطاقة الدخول إلى لوحة التحكم والإدارة الأكاديمية (للمشرف العام والممثلين)
            if (_user!.isAdmin || _user!.canManageLectures || _user!.canManageAnnouncements) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const DashboardScreen()),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (_user!.studentId == 'ST-NUST-001630760-413' || _user!.name.contains('مجتبى') || _user!.isAdmin)
                                      ? 'داش بورد مجتبى (المشرف العام)'
                                      : 'لوحة ممثل الدفعة',
                                  style: GoogleFonts.cairo(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  (_user!.studentId == 'ST-NUST-001630760-413' || _user!.name.contains('مجتبى') || _user!.isAdmin)
                                      ? 'مراقبة نشاط الممثلين وإدارة كافة تفاصيل النظام'
                                      : 'إدارة المحاضرات والتبليغات',
                                  style: GoogleFonts.cairo(
                                    fontSize: 10.5,
                                    color: const Color(0xFFE0E7FF),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 14),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],

            // بطاقة محاكاة شُعب الممثلين (خاصة بالمشرف العام مجتبى)
            if (_isMujtabaAdmin) _buildAdminSimulationCard(),

            // تفاصيل القيد
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppTheme.lightBorder),
                boxShadow: AppTheme.cardShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.badge_rounded, color: AppTheme.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'بياناتي',
                        style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                    ],
                  ),
                  const Divider(color: AppTheme.lightBorder, height: 20),
                  _buildProfileRow('المعرف:', _user!.studentId),
                  _buildProfileRow('القسم:', _user!.department),
                  _buildProfileRow('المرحلة:', _user!.stage),
                  if (_user!.section != null) _buildProfileRow('الشعبة:', _user!.section!),
                  if (_user!.phone != null) _buildProfileRow('الهاتف:', _user!.phone!),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // خدمات وتكامل البوت والدعم
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppTheme.lightBorder),
                boxShadow: AppTheme.cardShadow,
              ),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF229ED9).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send_rounded, color: Color(0xFF229ED9), size: 20),
                    ),
                    title: Text(
                      'بوت تيليجرام',
                      style: GoogleFonts.cairo(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '@${AppConstants.telegramBotUsername}',
                      style: GoogleFonts.cairo(color: AppTheme.textMuted, fontSize: 11),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF94A3B8)),
                    onTap: _openTelegramBot,
                  ),
                  const Divider(color: AppTheme.lightBorder, height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.support_agent_rounded, color: AppTheme.accent, size: 20),
                    ),
                    title: Text(
                      'الدعم والمساعدة الفنية',
                      style: GoogleFonts.cairo(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '@${AppConstants.supportTelegramUsername} • تواصل مباشر',
                      style: GoogleFonts.cairo(color: AppTheme.textMuted, fontSize: 11),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF94A3B8)),
                    onTap: _openSupportTelegram,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // زر تسجيل الخروج
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.danger,
                side: const BorderSide(color: AppTheme.danger, width: 1.2),
                padding: const EdgeInsets.symmetric(vertical: 14),
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.logout_rounded, size: 20),
              label: Text('تسجيل الخروج', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
              onPressed: _logout,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textSecondary)),
          Text(
            value,
            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminSimulationCard() {
    final preview = AdminPreviewService();
    preview.initialize(_user);

    return AnimatedBuilder(
      animation: preview,
      builder: (context, _) {
        final isCustom = preview.isCustomActive;
        final currentDept = preview.department;
        final currentStage = preview.stage;
        final currentSection = preview.section;

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isCustom ? const Color(0xFFF59E0B).withValues(alpha: 0.6) : AppTheme.lightBorder,
              width: isCustom ? 1.5 : 1,
            ),
            boxShadow: [
              if (isCustom)
                BoxShadow(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                )
              else
                ...AppTheme.cardShadow,
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // رأس البطاقة
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isCustom
                          ? const Color(0xFFFEF3C7)
                          : const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.swap_horiz_rounded,
                      color: isCustom ? const Color(0xFFD97706) : const Color(0xFF4F46E5),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'محاكاة شُعب الممثلين',
                              style: GoogleFonts.cairo(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: isCustom ? const Color(0xFFF59E0B) : const Color(0xFF4F46E5),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isCustom ? 'مفعلة الآن ⚡' : 'المشرف العام',
                                style: GoogleFonts.cairo(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'تخصيص العرض ليفتح التطبيق كما يظهر لممثل الشعبة تماماً',
                          style: GoogleFonts.cairo(fontSize: 10.5, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(color: AppTheme.lightBorder, height: 20),

              // 1. اختيار القسم
              Text(
                'القسم الأكاديمي المستهدف:',
                style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 6),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _showDepartmentSelector(context, preview),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.lightSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.lightBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.account_balance_rounded, size: 18, color: AppTheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          currentDept,
                          style: GoogleFonts.cairo(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.textSecondary, size: 20),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // 2. اختيار المرحلة
              Text(
                'المرحلة الدراسية:',
                style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: AppConstants.stages.map((stg) {
                  final isSelected = currentStage == stg;
                  return ChoiceChip(
                    label: Text(stg),
                    selected: isSelected,
                    onSelected: (val) {
                      if (val) preview.setStage(stg);
                    },
                    selectedColor: const Color(0xFF4F46E5),
                    backgroundColor: AppTheme.lightSurface,
                    labelStyle: GoogleFonts.cairo(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : AppTheme.textPrimary,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: isSelected ? const Color(0xFF4F46E5) : AppTheme.lightBorder,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),

              // 3. اختيار الشعبة
              Text(
                'الشعبة المستهدفة:',
                style: GoogleFonts.cairo(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: ['A', 'B', 'C', 'D', 'E', 'F'].map((sec) {
                  final isSelected = currentSection == sec;
                  return ChoiceChip(
                    label: Text('شعبة $sec'),
                    selected: isSelected,
                    onSelected: (val) {
                      if (val) preview.setSection(sec);
                    },
                    selectedColor: isCustom ? const Color(0xFFD97706) : const Color(0xFF4F46E5),
                    backgroundColor: AppTheme.lightSurface,
                    labelStyle: GoogleFonts.cairo(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : AppTheme.textPrimary,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: isSelected
                            ? (isCustom ? const Color(0xFFD97706) : const Color(0xFF4F46E5))
                            : AppTheme.lightBorder,
                      ),
                    ),
                  );
                }).toList(),
              ),

              // حالة المحاكاة وزر إعادة التعيين
              if (isCustom) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.visibility_rounded, color: Color(0xFFD97706), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'أنت الآن تتصفح وتدير التطبيق كممثل لشعبة $currentSection (${currentDept.split(" ").take(2).join(" ")} - $currentStage)',
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF92400E),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF475569),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.restart_alt_rounded, size: 18),
                    label: Text(
                      'إلغاء المحاكاة والرجوع لوضعي الأصلي',
                      style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      preview.reset(_user);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'تمت العودة إلى قيدك الجامعي الأصلي',
                            style: GoogleFonts.cairo(),
                          ),
                          backgroundColor: AppTheme.primary,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _showDepartmentSelector(BuildContext context, AdminPreviewService preview) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.85,
          minChildSize: 0.4,
          expand: false,
          builder: (_, scrollController) {
            return Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.school_rounded, color: AppTheme.primary, size: 22),
                      const SizedBox(width: 10),
                      Text(
                        'اختر القسم للمحاكاة',
                        style: GoogleFonts.cairo(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppTheme.lightBorder),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: AppConstants.departments.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.lightBorder),
                    itemBuilder: (_, index) {
                      final dept = AppConstants.departments[index];
                      final isSelected = preview.department == dept;
                      return ListTile(
                        leading: Icon(
                          isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                          color: isSelected ? AppTheme.primary : const Color(0xFF94A3B8),
                        ),
                        title: Text(
                          dept,
                          style: GoogleFonts.cairo(
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? AppTheme.primary : AppTheme.textPrimary,
                          ),
                        ),
                        trailing: isSelected
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.primarySubtle,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'المحدد',
                                  style: GoogleFonts.cairo(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              )
                            : null,
                        onTap: () {
                          preview.setDepartment(dept);
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
