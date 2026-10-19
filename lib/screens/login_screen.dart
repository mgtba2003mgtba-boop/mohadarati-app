import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../services/supabase_service.dart';
import '../widgets/study_book_animation.dart';
import '../widgets/app_loading_overlay.dart';
import '../widgets/ios_install_dialog.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _idController = TextEditingController();
  final _pinController = TextEditingController();

  bool _isLoading = false;
  bool _isPasswordVisible = false;
  int _failedAttempts = 0;
  DateTime? _lockoutUntil;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkLockoutStatus();
  }

  Future<void> _checkLockoutStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lockoutMillis = prefs.getInt('login_lockout_until') ?? 0;
      if (lockoutMillis > 0) {
        final lockTime = DateTime.fromMillisecondsSinceEpoch(lockoutMillis);
        if (DateTime.now().isBefore(lockTime)) {
          if (!mounted) return;
          setState(() {
            _lockoutUntil = lockTime;
            _failedAttempts = 5;
            final sec = lockTime.difference(DateTime.now()).inSeconds + 1;
            _errorMessage = 'الحساب مقفل مؤقتاً بسبب تكرار المحاولات الخاطئة. يرجى الانتظار $sec ثانية.';
          });
        } else {
          await prefs.remove('login_lockout_until');
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _idController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    // 1. فحص حظر التخمين العنيف (Brute Force Rate Limiting)
    if (_lockoutUntil != null) {
      if (DateTime.now().isBefore(_lockoutUntil!)) {
        final sec = _lockoutUntil!.difference(DateTime.now()).inSeconds + 1;
        setState(() => _errorMessage = 'تم تجاوز عدد المحاولات المسموح بها. يرجى الانتظار $sec ثانية.');
        return;
      } else {
        _lockoutUntil = null;
        _failedAttempts = 0;
        SharedPreferences.getInstance().then((p) => p.remove('login_lockout_until')).catchError((_) => null);
      }
    }

    final id = _idController.text.trim();
    final pin = _pinController.text.trim();

    if (id.isEmpty) {
      setState(() => _errorMessage = 'يرجى إدخال الرقم الجامعي');
      return;
    }
    if (pin.isEmpty) {
      setState(() => _errorMessage = 'يرجى إدخال رمز المرور');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final user = await SupabaseService().loginWithStudentIdAndPin(
      studentId: id,
      pinCode: pin,
    );

    if (!mounted) return;

    if (user != null) {
      _failedAttempts = 0;
      _lockoutUntil = null;
      SharedPreferences.getInstance().then((p) => p.remove('login_lockout_until')).catchError((_) => null);
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    } else {
      _failedAttempts++;
      if (_failedAttempts >= 5) {
        final lockTime = DateTime.now().add(const Duration(seconds: 30));
        _lockoutUntil = lockTime;
        SharedPreferences.getInstance().then((p) => p.setInt('login_lockout_until', lockTime.millisecondsSinceEpoch)).catchError((_) => null);
        setState(() {
          _isLoading = false;
          _errorMessage = 'تم قفل محاولات تسجيل الدخول مؤقتاً لمدة 30 ثانية لحماية الحساب من التخمين.';
        });
      } else {
        final left = 5 - _failedAttempts;
        setState(() {
          _isLoading = false;
          _errorMessage = 'بيانات الدخول غير صحيحة. متبقي $left محاولات قبل القفل المؤقت.';
        });
      }
    }
  }

  Future<void> _handleForgotPassword() async {
    final id = _idController.text.trim();
    if (id.isEmpty) {
      setState(() => _errorMessage = 'يرجى كتابة الرقم الجامعي أولاً لتتمكن من استعادة رمز المرور');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final student = await SupabaseService().verifyTelegramStudentCode(id);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (student == null) {
      setState(() => _errorMessage = 'لم يتم العثور على المعرف.');
      return;
    }

    final chatId = student.telegramChatId;
    if (chatId == null || chatId.trim().isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('ربط تيليجرام', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 15)),
          content: Text(
            'حسابك غير مرتبط بالبوت.\nاضغط لفتح البوت والربط: @${AppConstants.telegramBotUsername}',
            style: GoogleFonts.cairo(color: AppTheme.textSecondary, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء', style: GoogleFonts.cairo(color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final uri = Uri.parse(AppConstants.telegramBotUrl);
                try {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } catch (_) {}
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              child: Text('فتح البوت', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    final sent = await SupabaseService().sendTelegramPasswordResetCode(student: student);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!sent) {
      setState(() => _errorMessage = 'فشل الإرسال للبوت. تأكد من تشغيل البوت.');
      return;
    }

    final otpController = TextEditingController();
    final newPinController = TextEditingController();
    String? dialogError;
    bool isResetting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(
            'استعادة الرمز',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textPrimary),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'أدخل الكود المرسل للبوت:',
                style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: otpController,
                keyboardType: TextInputType.number,
                style: GoogleFonts.cairo(color: AppTheme.textPrimary, letterSpacing: 3, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  labelText: 'كود التحقق',
                  filled: true,
                  fillColor: AppTheme.lightSurface,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: newPinController,
                obscureText: true,
                style: GoogleFonts.cairo(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'الرمز الجديد',
                  filled: true,
                  fillColor: AppTheme.lightSurface,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                ),
              ),
              if (dialogError != null) ...[
                const SizedBox(height: 8),
                Text(
                  dialogError!,
                  style: GoogleFonts.cairo(color: AppTheme.danger, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: isResetting ? null : () => Navigator.pop(dlgCtx),
              child: Text('إلغاء', style: GoogleFonts.cairo(color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              onPressed: isResetting
                  ? null
                  : () async {
                      final otp = otpController.text.trim();
                      final newPin = newPinController.text.trim();
                      if (otp.length != 6) {
                        setDlgState(() => dialogError = 'أدخل كود التحقق (6 أرقام)');
                        return;
                      }
                      if (newPin.isEmpty) {
                        setDlgState(() => dialogError = 'أدخل الرمز الجديد');
                        return;
                      }

                      setDlgState(() {
                        isResetting = true;
                        dialogError = null;
                      });

                      final ok = await SupabaseService().verifyOtpAndResetPin(
                        studentId: student.id,
                        otpCode: otp,
                        newPin: newPin,
                      );

                      if (ok) {
                        final user = await SupabaseService().loginWithStudentIdAndPin(
                          studentId: student.id,
                          pinCode: newPin,
                        );
                        if (!mounted) return;
                        Navigator.pop(dlgCtx);
                        if (user != null) {
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(builder: (_) => const HomeScreen()),
                            (route) => false,
                          );
                        }
                      } else {
                        setDlgState(() {
                          isResetting = false;
                          dialogError = 'كود التحقق غير صحيح أو منتهي';
                        });
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: isResetting
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text('تأكيد', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.lightBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'تسجيل الدخول الأكاديمي',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 17, color: AppTheme.textPrimary),
        ),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppTheme.lightBorder),
                boxShadow: AppTheme.cardShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(
                    child: StudyBookAnimation(size: 60),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'الجامعة الوطنية (NUST)',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.cairo(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 22),

                  TextField(
                    controller: _idController,
                    style: GoogleFonts.cairo(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'المعرف الجامعي',
                      prefixIcon: const Icon(Icons.badge_outlined, color: AppTheme.primary),
                      filled: true,
                      fillColor: AppTheme.lightSurface,
                    ),
                  ),
                  const SizedBox(height: 14),

                  TextField(
                    controller: _pinController,
                    obscureText: !_isPasswordVisible,
                    style: GoogleFonts.cairo(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'رمز المرور',
                      prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppTheme.primary),
                      filled: true,
                      fillColor: AppTheme.lightSurface,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isPasswordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          color: AppTheme.textMuted,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: AppTheme.dangerSubtle,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: GoogleFonts.cairo(color: AppTheme.danger, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],

                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : Text(
                            'دخول',
                            style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                  ),
                  const SizedBox(height: 10),

                  TextButton(
                    onPressed: _isLoading ? null : _handleForgotPassword,
                    child: Text(
                      'نسيت الرمز؟',
                      style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'حساب جديد؟ ',
                        style: GoogleFonts.cairo(color: AppTheme.textSecondary, fontSize: 12),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                          );
                        },
                        child: Text(
                          'تفعيل',
                          style: GoogleFonts.cairo(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: AppTheme.lightBorder, height: 1),
                  const SizedBox(height: 14),
                  InkWell(
                    onTap: () => IosInstallDialog.show(context),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.primarySubtle,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.18)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.apple, color: AppTheme.textPrimary, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'تثبيت التطبيق على الآيفون 📱 (بدون متصفح)',
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      if (_isLoading)
        const AppLoadingOverlay(
          title: 'جاري الدخول...',
        ),
    ],
  ),
);
  }
}
