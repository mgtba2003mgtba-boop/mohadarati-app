import 'package:flutter/foundation.dart';

/// ثوابت وإعدادات المنظومة الجامعية الموحدة
class AppConstants {
  static const String appName = 'محاضراتي';
  static const String appVersion = '1.0.0';
  static const String universityName = 'الجامعة الوطنية للعلوم والتكنولوجيا';
  static const String collegeName = 'الكلية التقنية الهندسية (NUST)';

  // ── 1. سيرفر البوابة الجديد (Master Portal & Users & Lectures & PIN) ──
  static const String portalSupabaseUrl = 'https://mrubdzgcjofjwirkdfwo.supabase.co';
  static const String portalSupabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1ydWJkemdjam9mandpcmtkZndvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE4MjA4NTEsImV4cCI6MjEwNzM5Njg1MX0.s-_UoJiRgb-84_5WhrQt0cSmFECU7ns1yCvk0XGCABQ';

  // ── 2. سيرفر البصمة ونظام الحضور القديم (Read-Only Data Source) ────────
  static const String attendanceSupabaseUrl = 'https://rlupqsmqwvidmwrvqrcc.supabase.co';
  static const String attendanceSupabaseAnonKey = 'sb_publishable_sJM5JiXGzn-jif8EYqXC-g_5_HdADJ4';

  // التوافق القديم
  static const String supabaseUrl = portalSupabaseUrl;
  static const String supabaseAnonKey = portalSupabaseAnonKey;

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

  // ── Telegram Bots ───────────────────────────────────────────────────
  // بوت نظام البصمة والحضور (لأكواد التحقق والاستعادة وتأكيد الحسابات)
  static const String attendanceBotUsername = 'UnivercityAttendance_mujtba_Bot';
  static const String attendanceBotUrl = 'https://t.me/UnivercityAttendance_mujtba_Bot';
  static const String attendanceBotToken = '8760017532:AAGPiVBa6-TPnSnwuxGWGiR8wTJlKYT8vSM';

  // التوافق المباشر مع واجهات الدخول والربط
  static const String telegramBotUsername = attendanceBotUsername;
  static const String telegramBotUrl = attendanceBotUrl;
  static const String telegramBotToken = attendanceBotToken;

  // بوت المحاضرات والـ CDN (لرفع وبث الفيديوهات والملفات عبر تيليجرام)
  static const String lecturesBotToken = '8816281220:AAFAduddee7N8mD-UNgQIgfQ1yiFaGbdHU8';
  static const String lecturesBotUsername = 'NUST_ETC_ATT_LEC_BOT';
  static const int lecturesChannelId = -1003875986734;

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

  // ── الشُعب الدراسية ───────────────────────────────────────────────
  static const List<String> sections = ['A', 'B', 'C', 'D'];

  // ── الخطة الدراسية والمقررات الرسمية لكل قسم ومرحلة ───────────────
  static const Map<String, Map<String, List<String>>> curriculumMap = {
    'هندسة تقنيات الأجهزة الطبية': {
      'المرحلة الأولى': [
        'الرياضيات الهندسية',
        'الدوائر الكهربائية',
        'التشريح ووظائف الأعضاء',
        'البرمجة والحاسوب',
        'الكيمياء والفيزياء الطبية',
        'اللغة الإنجليزية',
        'حقوق الإنسان والديمقراطية',
      ],
      'المرحلة الثانية': [
        'الإلكترونيات الطبية',
        'معالجة الإشارات الطبية',
        'الميكانيكا الحيوية',
        'الرياضيات المتقدمة',
        'القياسات والأجهزة الطبية',
        'المجالات الكهرومغناطيسية',
      ],
      'المرحلة الثالثة': [
        'أجهزة التصوير الطبي',
        'المعالجات الدقيقة والمتحكمات',
        'الأجهزة التشخيصية والمخبرية',
        'الأجهزة العلاجية',
        'الاتصالات والشبكات الطبية',
        'تطبيقات الذكاء الاصطناعي الطبي',
      ],
      'المرحلة الرابعة': [
        'أنظمة الليزر الطبية',
        'نظم السيطرة',
        'أجهزة الرنين والمفراس (CT & MRI)',
        'الأطراف الصناعية والأجهزة التعويضية',
        'إدارة وصيانة الأجهزة الطبية',
        'مشروع التخرج II',
      ],
    },
    'هندسة تقنيات الحاسوب': {
      'المرحلة الأولى': [
        'أساسيات البرمجة (C++)',
        'الرياضيات الهندسية I',
        'التصميم المنطقي والدوائر الرقمية',
        'تراكيب وهياكل البيانات',
        'مبادئ تكنولوجيا المعلومات',
        'اللغة الإنجليزية الأكاديمية',
      ],
      'المرحلة الثانية': [
        'شبكات الحاسوب I',
        'معمارية وتنظيم الحاسوب',
        'نظم التشغيل (OS)',
        'البرمجة كائنية التوجه (OOP)',
        'الإلكترونيات والدوائر المدمجة',
        'الرياضيات المتقدمة والهندسة العددية',
      ],
      'المرحلة الثالثة': [
        'الذكاء الاصطناعي (AI)',
        'قواعد البيانات وإدارتها (DBMS)',
        'الشبكات المتقدمة واللاسلكية',
        'تطوير برمجيات الويب والموبايل',
        'المتحكمات والمعالجات المدمجة',
        'أمن نظم الحاسوب',
      ],
      'المرحلة الرابعة': [
        'الحوسبة السحابية والنظم الموزعة',
        'إنترنت الأشياء (IoT)',
        'تعلم الآلة والبيانات الضخمة',
        'إدارة مشاريع تكنولوجيا المعلومات',
        'أمن الشبكات والمعلومات',
        'مشروع التخرج II',
      ],
    },
    'هندسة تقنيات الأمن السيبراني': {
      'المرحلة الأولى': [
        'مبادئ الأمن السيبراني',
        'أساسيات البرمجة والخوارزميات',
        'الرياضيات المتقطعة والتشفير الأولي',
        'التصميم الرقمي والأنظمة المنطقية',
        'بنية الحاسوب ونظم التشغيل',
        'اللغة الإنجليزية التخصصية',
      ],
      'المرحلة الثانية': [
        'أمن الشبكات والبروتوكولات',
        'التشفير وأمن البيانات (Cryptography)',
        'أمن نظم التشغيل ولينكس المتقدم',
        'هياكل البيانات والبرمجة الآمنة',
        'شبكات الحاسوب المتقدمة',
        'إدارة وتأمين الخوادم',
      ],
      'المرحلة الثالثة': [
        'اختبار الاختراق والتقييم الأخلاقي',
        'التحقيق الجنائي الرقمي (Digital Forensics)',
        'أمن تطبيقات الويب وقواعد البيانات',
        'تحليل البرمجيات الخبيثة والهندسة العكسية',
        'الدفاع السيبراني والمراقبة الأمنية (SOC)',
        'أمن الحوسبة السحابية',
      ],
      'المرحلة الرابعة': [
        'الاستجابة للحوادث وإدارة التهديدات',
        'حوكمة الأمن السيبراني والامتثال',
        'أمن إنترنت الأشياء والأنظمة الصناعية (ICS/SCADA)',
        'الذكاء الاصطناعي في الدفاع السيبراني',
        'التشفير المتقدم وبلوك تشين',
        'مشروع التخرج II',
      ],
    },
  };

  /// استرجاع المقررات الدراسية الرسمية لقسم ومرحلة محددة
  static List<String> getCurriculumSubjects(String department, String stage) {
    final deptData = curriculumMap[department];
    if (deptData != null) {
      final stageData = deptData[stage];
      if (stageData != null && stageData.isNotEmpty) {
        return List<String>.from(stageData);
      }
    }
    // المقررات الافتراضية العامة في حال عدم التطابق التام
    return [
      'أنظمة الليزر الطبية',
      'نظم السيطرة',
      'مشروع التخرج II',
      'الأجهزة التشخيصية',
      'المعالجات الدقيقة',
      'الرياضيات الهندسية',
    ];
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
  static const String roleProfessor = 'professor';
  static const String roleAdmin = 'admin';

  static String getRoleLabel(String role) {
    switch (role) {
      case roleAdmin:
        return 'مشرف عام / إدارة الكلية';
      case roleProfessor:
        return 'أستاذ مادة';
      case roleRepresentative:
        return 'ممثل الدفعة / المرحلة';
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
}
