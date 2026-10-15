import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../models/app_user_model.dart';
import '../services/supabase_service.dart';
import 'onboarding_screen.dart';
import 'dashboard_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  AppUserModel? _user;

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
                  CircleAvatar(
                    radius: 44,
                    backgroundColor: AppTheme.primarySubtle,
                    backgroundImage: (_user!.photoUrl != null && _user!.photoUrl!.isNotEmpty)
                        ? NetworkImage(_user!.photoUrl!)
                        : null,
                    child: (_user!.photoUrl == null || _user!.photoUrl!.isEmpty)
                        ? const Icon(Icons.person, size: 50, color: AppTheme.primary)
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _user!.name,
                    style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primarySubtle,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _user!.roleLabel,
                      style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primary),
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
                    colors: [Color(0xFF4F46E5), Color(0xFF3730A3)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4F46E5).withValues(alpha: 0.25),
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
                      'الدعم والمساعدة',
                      style: GoogleFonts.cairo(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'الاستفسارات والمساعدة الفنية',
                      style: GoogleFonts.cairo(color: AppTheme.textMuted, fontSize: 11),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF94A3B8)),
                    onTap: _openTelegramBot,
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
}
