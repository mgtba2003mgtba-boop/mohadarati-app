import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// ── خدمة التحديث التلقائي الإجباري (Auto-Update Service) ────────────────
/// ترصد دورة حياة التطبيق عند كل فتح وعند العودة إليه من الخلفية،
/// وتقوم بفحص رقم البناء في السيرفر ومقارنته مع المحفوظ في الجهاز.
/// إذا وُجد تحديث، تعيد تحميل الصفحة فورياً وبشكل إجباري بالنسخة الأحدث.
class AutoUpdateService with WidgetsBindingObserver {
  static final AutoUpdateService _instance = AutoUpdateService._internal();
  factory AutoUpdateService() => _instance;
  AutoUpdateService._internal();

  bool _initialized = false;
  String? _currentBuildNumber;
  DateTime _lastCheckTime = DateTime.fromMillisecondsSinceEpoch(0);

  /// مؤشر لمنع أي إعادة تحميل إجبارية أثناء تفاعل المستخدم، كتابة التبليغات، أو اختيار الملفات
  static bool isUserBusy = false;

  void initialize() {
    if (_initialized) return;
    _initialized = true;
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {}
    // فحص هادئ عند بدء تشغيل التطبيق
    checkUpdate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // فحص بهدوء دون إجبار على التحديث الفوري إذا كان المستخدم يعمل
      if (!isUserBusy) {
        checkUpdate();
      }
    }
  }

  Future<void> checkUpdate() async {
    if (!kIsWeb) return;
    if (isUserBusy) return;

    // منع تكرار الفحص في فترات أقل من 30 ثانية لتوفير استهلاك الشبكة
    final now = DateTime.now();
    if (now.difference(_lastCheckTime).inSeconds < 30) return;
    _lastCheckTime = now;

    try {
      final prefs = await SharedPreferences.getInstance();
      _currentBuildNumber ??= prefs.getString('nust_build_number');

      final url = Uri.parse('/version.json?_t=${now.millisecondsSinceEpoch}');
      final response = await http.get(url).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final serverBuild = data['build_number']?.toString();

        if (serverBuild != null && serverBuild.isNotEmpty) {
          if (_currentBuildNumber == null) {
            // أول مرة يتم تشغيل التطبيق
            _currentBuildNumber = serverBuild;
            await prefs.setString('nust_build_number', serverBuild);
          } else if (_currentBuildNumber != serverBuild) {
            // وُجد تحديث جديد تم رفعه!
            debugPrint('[+] New version detected: $serverBuild (was: $_currentBuildNumber)');
            await prefs.setString('nust_build_number', serverBuild);
            // لا نعيد تحميل المتصفح إطلاقاً إذا كان المستخدم داخل جلسة عمل نشطة
            if (!isUserBusy) {
              debugPrint('[*] Version registered quietly for next session.');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[-] Error checking for updates: $e');
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
}
