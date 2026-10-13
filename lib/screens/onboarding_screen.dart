import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../models/student_model.dart';
import '../services/supabase_service.dart';
import '../widgets/study_book_animation.dart';
import '../widgets/app_loading_overlay.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _codeController = TextEditingController();
  final _pinController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _isLoading = false;
  bool _isPasswordVisible = false;
  String? _errorMessage;
  StudentModel? _verifiedStudent;
  bool _isAccountAlreadyRegistered = false;

  @override
  void dispose() {
    _codeController.dispose();
    _pinController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  /// فتح بوت التليجرام الرسمي للحصول على الكود فوراً
  Future<void> _openTelegramBot() async {
    final directBotUrl = AppConstants.telegramBotUrl;
    final tgAppUrl = 'tg://resolve?domain=${AppConstants.telegramBotUsername}';

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.send_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'جارٍ فتح البوت... اضغط بدء (Start) لنسخ معرفك ولصقه هنا',
                  style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF229ED9),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }

    try {
      final tgUri = Uri.parse(tgAppUrl);
      if (await canLaunchUrl(tgUri)) {
        await launchUrl(tgUri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {}

    try {
      final webUri = Uri.parse(directBotUrl);
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تعذر فتح الرابط تلقائياً. ابحث عن @${AppConstants.telegramBotUsername} في تيليجرام',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  /// التحقق من كود المعرف الجامعي
  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _errorMessage = 'يرجى إدخال الرقم الجامعي أو المعرف أولاً');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final student = await SupabaseService().verifyTelegramStudentCode(code);

    if (!mounted) return;

    if (student != null) {
      // فحص هل الحساب مسجل ومفعّل مسبقاً ولديه رمز مرور
      final existingUser = await SupabaseService().getAppUserByStudentId(student.id);
      final hasPin = existingUser != null &&
          existingUser.pinCode != null &&
          existingUser.pinCode!.trim().isNotEmpty;

      setState(() {
        _isLoading = false;
        _verifiedStudent = student;
        _isAccountAlreadyRegistered = hasPin;
        _pinController.clear();
      });
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = 'لم يتم العثور على قيد مطابق. يرجى التأكد من صحة المعرف.';
      });
    }
  }

  /// تسجيل الدخول الصارم للحساب المفعّل مسبقاً
  Future<void> _handleExistingLogin() async {
    if (_verifiedStudent == null) return;

    final pin = _pinController.text.trim();
    if (pin.isEmpty) {
      setState(() => _errorMessage = 'يرجى إدخال رمز المرور الخاص بحسابك');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final user = await SupabaseService().loginWithStudentIdAndPin(
      studentId: _verifiedStudent!.id,
      pinCode: pin,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (user != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      setState(() {
        _errorMessage = 'رمز المرور غير صحيح! يرجى إدخال الرمز الذي حددته مسبقاً، أو استخدام خيار الاستعادة عبر تيليجرام.';
      });
    }
  }

  /// نافذة استعادة رمز المرور عبر بوت تيليجرام
  Future<void> _showForgotPasswordDialog() async {
    if (_verifiedStudent == null) return;

    final chatId = _verifiedStudent!.telegramChatId;
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
              onPressed: () {
                Navigator.pop(ctx);
                _openTelegramBot();
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
    final sent = await SupabaseService().sendTelegramPasswordResetCode(student: _verifiedStudent!);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!sent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فشل الإرسال للبوت. تأكد من تشغيل البوت.')),
      );
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
                        studentId: _verifiedStudent!.id,
                        otpCode: otp,
                        newPin: newPin,
                      );

                      if (ok) {
                        final user = await SupabaseService().loginWithStudentIdAndPin(
                          studentId: _verifiedStudent!.id,
                          pinCode: newPin,
                        );
                        if (!mounted) return;
                        Navigator.pop(dlgCtx);
                        if (user != null) {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (_) => const HomeScreen()),
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

  /// إتمام التسجيل وفتح الحساب باسم الطالب لأول مرة
  Future<void> _completeRegistration() async {
    if (_verifiedStudent == null) return;

    final pin = _pinController.text.trim();
    if (pin.isEmpty) {
      setState(() => _errorMessage = 'يرجى تعيين رمز المرور للمتابعة');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final user = await SupabaseService().registerOrLinkStudentAccount(
      student: _verifiedStudent!,
      pinCode: pin,
      phone: _phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : null,
    );

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (user != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      setState(() {
        _errorMessage = 'حدث خطأ أثناء حفظ الحساب، يرجى إعادة المحاولة';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.lightBg,
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
                  // رأس الصفحة مع أنيميشن الدراسة
                  const Center(
                    child: StudyBookAnimation(size: 60),
                  ),
                  const SizedBox(height: 14),

                  Text(
                    'تفعيل الحساب',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.cairo(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 22),

                  // إذا لم يتم التحقق من الطالب بعد: إدخال الكود
                  if (_verifiedStudent == null) ...[
                    TextField(
                      controller: _codeController,
                      style: GoogleFonts.cairo(color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'المعرف الجامعي',
                        prefixIcon: const Icon(Icons.qr_code_2_rounded, color: AppTheme.primary),
                        filled: true,
                        fillColor: AppTheme.lightSurface,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // زر التحقق
                    ElevatedButton(
                      onPressed: _isLoading ? null : _verifyCode,
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
                          : Text('التحقق', style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 10),

                    // زر التوجيه الفوري لبوت التيليجرام
                    ElevatedButton.icon(
                      onPressed: _openTelegramBot,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF229ED9),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.send_rounded, size: 16),
                      label: Text(
                        'طلب المعرف من بوت تيليجرام ⚡',
                        style: GoogleFonts.cairo(fontSize: 12.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ] else ...[
                    // تم التحقق بنجاح من بيانات الطالب
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.lightSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'تم العثور على القيد',
                                style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.success,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          const Divider(color: AppTheme.lightBorder, height: 20),
                          _buildInfoRow('الاسم:', _verifiedStudent!.name, isBold: true),
                          _buildInfoRow('المعرف:', _verifiedStudent!.id),
                          _buildInfoRow('القسم:', _verifiedStudent!.department),
                          _buildInfoRow('المرحلة:', '${_verifiedStudent!.stage} ${_verifiedStudent!.section != null ? '(${_verifiedStudent!.section})' : ''}'),
                          _buildInfoRow(
                            'بصمة الوجه:',
                            _verifiedStudent!.hasFace ? 'موثقة' : 'قيد التسجيل',
                            valueColor: _verifiedStudent!.hasFace ? AppTheme.success : AppTheme.warning,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    if (_isAccountAlreadyRegistered) ...[
                      // ── حالة 1: الحساب مفعّل مسبقاً ولديه رمز مرور محدد ──
                      Text(
                        'الحساب مفعّل. أدخل الرمز للمتابعة:',
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),

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
                      const SizedBox(height: 14),

                      ElevatedButton(
                        onPressed: _isLoading ? null : _handleExistingLogin,
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
                            : Text('دخول', style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 8),

                      TextButton(
                        onPressed: _isLoading ? null : _showForgotPasswordDialog,
                        child: Text(
                          'نسيت الرمز؟',
                          style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 4),

                      TextButton(
                        onPressed: () => setState(() {
                          _verifiedStudent = null;
                          _isAccountAlreadyRegistered = false;
                          _pinController.clear();
                          _errorMessage = null;
                        }),
                        child: Text(
                          'معرف آخر',
                          style: GoogleFonts.cairo(color: AppTheme.textSecondary, fontSize: 12),
                        ),
                      ),
                    ] else ...[
                      // ── حالة 2: حساب جديد يُفعّل لأول مرة ──
                      Text(
                        'تعيين رمز المرور:',
                        style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _pinController,
                        obscureText: !_isPasswordVisible,
                        style: GoogleFonts.cairo(color: AppTheme.textPrimary),
                        decoration: InputDecoration(
                          labelText: 'الرمز الجديد',
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
                      const SizedBox(height: 10),

                      TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        style: GoogleFonts.cairo(color: AppTheme.textPrimary),
                        decoration: InputDecoration(
                          labelText: 'الهاتف (اختياري)',
                          prefixIcon: const Icon(Icons.phone_android_rounded, color: AppTheme.textMuted),
                          filled: true,
                          fillColor: AppTheme.lightSurface,
                        ),
                      ),
                      const SizedBox(height: 16),

                      ElevatedButton(
                        onPressed: _isLoading ? null : _completeRegistration,
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
                            : Text('تفعيل', style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 6),

                      TextButton(
                        onPressed: () => setState(() {
                          _verifiedStudent = null;
                          _isAccountAlreadyRegistered = false;
                          _pinController.clear();
                          _errorMessage = null;
                        }),
                        child: Text(
                          'معرف آخر',
                          style: GoogleFonts.cairo(color: AppTheme.textSecondary, fontSize: 12),
                        ),
                      ),
                    ],
                  ],

                  // رسالة الخطأ
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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

                  const SizedBox(height: 18),
                  // رابط الانتقال لتسجيل الدخول السريع
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'لديك حساب؟ ',
                        style: GoogleFonts.cairo(color: AppTheme.textSecondary, fontSize: 12),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const LoginScreen()),
                          );
                        },
                        child: Text(
                          'دخول',
                          style: GoogleFonts.cairo(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      if (_isLoading)
        const AppLoadingOverlay(
          title: 'جاري المعالجة...',
        ),
    ],
  ),
);
  }

  Widget _buildInfoRow(String label, String value, {bool isBold = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.cairo(
                fontSize: 13,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                color: valueColor ?? AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
