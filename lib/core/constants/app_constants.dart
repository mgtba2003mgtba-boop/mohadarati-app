import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'biometric_subjects.dart';

/// ثوابت وإعدادات المنظومة الجامعية الموحدة
class AppConstants {
  static const String appName = 'محاضراتي';
  static const String appVersion = '1.0.0';
  static const String universityName = 'الجامعة الوطنية للعلوم والتكنولوجيا';
  static const String collegeName = 'الكلية التقنية الهندسية (NUST)';

  // ── 1. سيرفر البوابة الجديد (Master Portal & Users & Lectures & PIN) ──
  static const String portalSupabaseUrl = 'https://mrubdzgcjofjwirkdfwo.supabase.co';
  static String get portalSupabaseAnonKey =>
      utf8.decode(base64Decode('ZXlKaGJHY2lPaUpJVXpJMU5pSXNJblI1Y0NJNklrcFhWQ0o5LmV5SnBjM01pT2lKemRYQmhZbUZ6WlNJc0luSmxaaUk2SW0xeWRXSmtlbWRqYW05bWFuZHBjbXRrWm5kdklpd2ljbTlzWlNJNkltRnViMjRpTENKcFlYUWlPakUzT1RFNE1qQTROVEVzSW1WNGNDSTZNakV3TnpNNU5qZzFNWDAucy1fVW9KaVJnYi04NF81V2hyUXQwY1NtRkVDVTduczF5Q3ZrMFhHQ0FCUQ=='));

  // ── 2. سيرفر البصمة ونظام الحضور القديم (Read-Only Data Source) ────────
  static const String attendanceSupabaseUrl = 'https://rlupqsmqwvidmwrvqrcc.supabase.co';
  static const String attendanceSupabaseAnonKey = 'sb_publishable_sJM5JiXGzn-jif8EYqXC-g_5_HdADJ4';

  // التوافق القديم
  static const String supabaseUrl = portalSupabaseUrl;
  static String get supabaseAnonKey => portalSupabaseAnonKey;

  // ── 3. سيرفر تيليجرام لبث وتحميل المحاضرات (Telegram Video Streamer CDN) ──
  static String get telegramStreamerBaseUrl {
    if (kIsWeb) {
      final host = Uri.base.host;
      final port = Uri.base.port;
      final portStr = (port == 80 || port == 443 || port == 0) ? '' : ':$port';
      if (host.isNotEmpty) return '${Uri.base.scheme}://$host$portStr';
    }
    return 'http://192.168.100.25:8050';
  }

  /// تحويل أي رابط صورة سحابي (تيليجرام أو خارجي) إلى رابط مدعوم بـ CORS ومحمي من حجب مزودي الشبكة في الهواتف
  static String resolveImageUrl(String? url) {
    if (url == null || url.trim().isEmpty) return '';
    final clean = url.trim();

    // إذا كان الرابط base64، يُرجع كما هو
    if (clean.startsWith('data:image')) return clean;

    // الروابط النسبية للبروكسي: إكمالها برابط النطاق الكامل إذا كنا على الهواتف أو الويب
    if (clean.startsWith('/api/proxy') || clean.startsWith('/api/file/')) {
      if (kIsWeb) {
        final host = Uri.base.host;
        final port = Uri.base.port;
        final portStr = (port == 80 || port == 443 || port == 0) ? '' : ':$port';
        if (host.isNotEmpty) {
          return '${Uri.base.scheme}://$host$portStr$clean';
        }
      }
      return 'https://mohadarati.vercel.app$clean';
    }

    // روابط سحابة تيليجرام: تمريرها عبر البروكسي السحابي الموثوق لتجاوز حظر CORS على الويب وحجب تيليجرام في شبكات الهاتف
    if (clean.contains('api.telegram.org/file/')) {
      final encoded = Uri.encodeComponent(clean);
      if (kIsWeb) {
        final host = Uri.base.host;
        final port = Uri.base.port;
        final portStr = (port == 80 || port == 443 || port == 0) ? '' : ':$port';
        if (host.isNotEmpty) {
          return '${Uri.base.scheme}://$host$portStr/api/proxy?url=$encoded';
        }
      }
      return 'https://mohadarati.vercel.app/api/proxy?url=$encoded';
    }

    return clean;
  }

  // ── Telegram Bots ───────────────────────────────────────────────────
  // بوت نظام البصمة والحضور (لأكواد التحقق والاستعادة وتأكيد الحسابات)
  static const String attendanceBotUsername = 'UnivercityAttendance_mujtba_Bot';
  static const String attendanceBotUrl = 'https://t.me/UnivercityAttendance_mujtba_Bot';
  static String get attendanceBotToken =>
      utf8.decode(base64Decode('ODc2MDAxNzUzMjpBQUhjb2NvYkQxLU1jTVpYcV9Yc2VMUmZqRHNQUWhZbUsxQQ=='));

  // التوافق المباشر مع واجهات الدخول والربط
  static const String telegramBotUsername = attendanceBotUsername;
  static const String telegramBotUrl = attendanceBotUrl;
  static String get telegramBotToken => attendanceBotToken;

  // بوت المحاضرات والـ CDN (لرفع وبث الفيديوهات والملفات عبر تيليجرام)
  static String get lecturesBotToken =>
      utf8.decode(base64Decode('ODgxNjI4MTIyMDpBQUZBZHVkZGVlN044bUQtVU5nUUlnZlExeWlGYUdiZEhVOA=='));
  static const String lecturesBotUsername = 'NUST_ETC_ATT_LEC_BOT';
  static const int lecturesChannelId = -1003875986734;

  // الدعم الفني المباشر
  static const String supportTelegramUsername = 'ii6689';
  static const String supportTelegramUrl = 'https://t.me/ii6689';

  /// ── حماية وتشفير رموز الدخول (Cryptographic PIN Hashing) ─────────
  static String hashPin(String pin) {
    final clean = pin.trim();
    if (clean.isEmpty) return '';
    final salted = 'nust_pin_sec_2026_$clean';
    return sha256.convert(utf8.encode(salted)).toString();
  }

  /// التحقق المزدوج الذكي: يقبل الرمز القديم أو المشفر مع تفعيل الترقية التلقائية
  static bool verifyPin(String inputPin, String? storedPin) {
    if (storedPin == null || storedPin.trim().isEmpty) return false;
    final cleanInput = inputPin.trim();
    final cleanStored = storedPin.trim();

    // 1. المطابقة المباشرة للنصوص القديمة (e.g. '1234')
    if (cleanInput == cleanStored) return true;

    // 2. المطابقة مع التشفير الرياضي SHA-256
    final hashed = hashPin(cleanInput);
    if (hashed == cleanStored) return true;

    return false;
  }

  // ── الأقسام الأكاديمية الرسمية ───────────────────────────────────
  static const List<String> departments = [
    'هندسة تقنيات الأجهزة الطبية',
    'هندسة تقنيات الحاسوب',
    'هندسة تقنيات الأمن السيبراني',
  ];

  // ── المراحل الدراسية ──────────────────────────────────────────────
  static const List<String> stages = [
    'المرحلة الأولى',
    'المرحلة الثانية',
    'المرحلة الثالثة',
    'المرحلة الرابعة',
  ];

  /// توحيد مسميات المراحل الدراسية لمعالجة تباين أنظمة البصمة ('السنة الثانية' -> 'المرحلة الثانية')
  static String normalizeStage(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'المرحلة الأولى';
    final clean = raw.trim();
    if (clean.contains('ثانية') || clean.contains('الثانية') || clean.contains('2')) {
      return 'المرحلة الثانية';
    }
    if (clean.contains('ثالثة') || clean.contains('الثالثة') || clean.contains('3')) {
      return 'المرحلة الثالثة';
    }
    if (clean.contains('رابعة') || clean.contains('الرابعة') || clean.contains('4')) {
      return 'المرحلة الرابعة';
    }
    if (clean.contains('أولى') || clean.contains('الاولى') || clean.contains('الأولى') || clean.contains('1')) {
      return 'المرحلة الأولى';
    }
    return clean;
  }

  /// استرجاع كافة التسميات المحتملة للمرحلة في نظام البصمة للاستعلام الآمن
  static List<String> getStageAliases(String? stage) {
    final norm = normalizeStage(stage);
    switch (norm) {
      case 'المرحلة الأولى':
        return ['المرحلة الأولى', 'السنة الأولى', 'المرحلة 1', 'السنة 1'];
      case 'المرحلة الثانية':
        return ['المرحلة الثانية', 'السنة الثانية', 'المرحلة 2', 'السنة 2'];
      case 'المرحلة الثالثة':
        return ['المرحلة الثالثة', 'السنة الثالثة', 'المرحلة 3', 'السنة 3'];
      case 'المرحلة الرابعة':
        return ['المرحلة الرابعة', 'السنة الرابعة', 'المرحلة 4', 'السنة 4'];
      default:
        return [norm];
    }
  }

  /// فحص والتحقق من صحة المعرف الجامعي للطالب (ST-... أو أرقام جامعية)
  static bool isValidStudentId(String? raw) {
    if (raw == null) return false;
    final clean = raw.trim();
    if (clean.isEmpty) return false;
    return RegExp(r'^(ST-[A-Z0-9-]+|[0-9]{5,})$', caseSensitive: false).hasMatch(clean);
  }

  // ── الشُعب الدراسية ───────────────────────────────────────────────
  static const List<String> sections = ['A', 'B', 'C', 'D'];

  // ── الخطة الدراسية والمقررات الرسمية المعتمدة حصراً من نظام البصمة الجامعي ──
  static Map<String, Map<String, List<String>>> get curriculumMap => BiometricSubjects.buildCurriculumMap();

  /// استرجاع المقررات الدراسية الرسمية المعتمدة حصراً من نظام البصمة الجامعي (الكورس الأول افتراضياً)
  static List<String> getCurriculumSubjects(String department, String stage, {int semester = 1}) {
    return BiometricSubjects.getSubjectNames(
      department: department,
      stage: stage,
      semester: semester,
    );
  }

  // ── تصنيفات الإعلانات ────────────────────────────────────────────
  static const Map<String, String> announcementCategories = {
    'academic': 'أكاديمي وتدريسي',
    'exam': 'جداول وامتحانات',
    'urgent': 'تبليغ عاجل وهام',
    'activity': 'نشاطات وفعاليات',
  };

  // ── الأدوار والصلاحيات ────────────────────────────────────────────
  static const String roleStudent = 'student';
  static const String roleRepresentative = 'representative';
  @deprecated
  static const String roleProfessor = 'professor';
  static const String roleAdmin = 'admin';

  static String getRoleLabel(String role) {
    switch (role) {
      case roleAdmin:
        return 'مشرف عام';
      case roleRepresentative:
        return 'ممثل الشعبة';
      case roleStudent:
      default:
        return 'طالب';
    }
  }

  // ── معايير الإنذار الأكاديمي للغياب (وفق التعليم العالي) ────────
  static const double firstWarningThreshold = 0.05; // 5% غياب: إنذار أولي
  static const double secondWarningThreshold = 0.07; // 7% غياب: إنذار ثاني
  static const double finalWarningThreshold = 0.10; // 10% غياب: إنذار نهائي
  static const double failureThreshold = 0.15; // 15% غياب: فصل بالغياب

  /// تطبيع النصوص العربية لتوحيد المقارنات ومنع أخطاء الحروف (أ/إ/آ -> ا, ة -> ه, ى -> ي)
  static String normalizeArabic(String? str) {
    if (str == null) return '';
    return str
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '') // حذف حركات التشكيل
        .replaceAll('\u0640', '') // حذف التطويل
        .replaceAll(RegExp(r'[أإآٱ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  /// مطابقة نصين عربيين بمرونة كاملة
  static bool arabicEquals(String? a, String? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return normalizeArabic(a) == normalizeArabic(b);
  }

  /// هل يحتوي النص العربي على نص آخر بمرونة
  static bool arabicContains(String? source, String? target) {
    if (source == null || target == null) return false;
    final normSource = normalizeArabic(source);
    final normTarget = normalizeArabic(target);
    if (normTarget.isEmpty) return true;
    return normSource.contains(normTarget);
  }
}

