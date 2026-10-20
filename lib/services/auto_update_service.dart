import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Directory;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';
import '../main.dart';
import '../widgets/in_app_update_dialog.dart';

/// ── خدمة التحديث التلقائي والذاتي (In-App Auto-Update Engine) ───────────────
/// تقوم بمقارنة رقم versionCode الحقيقي من نظام أندرويد مع السيرفر السحابي،
/// وتُظهر نافذة التحديث الإجباري المباشرة بشريط تقدم ونسبة مئوية لمنع أي تكرار أو حلقة مفرغة.
class AutoUpdateService with WidgetsBindingObserver {
  static final AutoUpdateService _instance = AutoUpdateService._internal();
  factory AutoUpdateService() => _instance;
  AutoUpdateService._internal();

  static const MethodChannel _updaterChannel = MethodChannel('iq.edu.nust.mohadarati/updater');

  bool _initialized = false;
  String? _currentBuildNumber;
  DateTime _lastCheckTime = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isShowingDialog = false;

  /// مؤشر لمنع أي إعادة تحميل إجبارية أثناء تفاعل المستخدم
  static bool isUserBusy = false;

  static Future<String?> getCacheDir() async {
    try {
      return await _updaterChannel.invokeMethod<String>('getCacheDir');
    } catch (e) {
      debugPrint('[-] Error getting cache dir: $e');
      return null;
    }
  }

  static Future<void> installApkFile(String path) async {
    try {
      await _updaterChannel.invokeMethod('installApk', {'filePath': path});
    } catch (e) {
      debugPrint('[-] Error launching package installer: $e');
    }
  }

  Future<void> installDownloadedUpdate() async {
    final cacheDir = await getCacheDir();
    if (cacheDir != null) {
      try {
        final dir = Directory(cacheDir);
        final apks = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.apk'));
        if (apks.isNotEmpty) {
          await installApkFile(apks.first.path);
        }
      } catch (_) {}
    }
  }

  void initialize() {
    if (_initialized) return;
    _initialized = true;
    try {
      WidgetsBinding.instance.addObserver(this);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        checkUpdate();
      });
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!isUserBusy && !_isShowingDialog) {
        checkUpdate();
      }
    }
  }

  Future<void> checkUpdate() async {
    if (isUserBusy || _isShowingDialog) return;

    final now = DateTime.now();
    if (now.difference(_lastCheckTime).inSeconds < 15) return;
    _lastCheckTime = now;

    if (kIsWeb) {
      await _checkWebUpdate(now);
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      await _checkAndroidUpdate(now);
    }
  }

  Future<void> _checkWebUpdate(DateTime now) async {
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
            _currentBuildNumber = serverBuild;
            await prefs.setString('nust_build_number', serverBuild);
          } else if (_currentBuildNumber != serverBuild) {
            debugPrint('[+] Web version update detected: $serverBuild (was: $_currentBuildNumber)');
            await prefs.setString('nust_build_number', serverBuild);
          }
        }
      }
    } catch (e) {
      debugPrint('[-] Error checking web updates: $e');
    }
  }

  Future<void> _checkAndroidUpdate(DateTime now) async {
    try {
      // 1. استخراج رقم versionCode الحقيقي المترجم والمثبت على جهاز الطالب عبر نظام أندرويد
      int localVersionCode = 0;
      try {
        localVersionCode = await _updaterChannel.invokeMethod<int>('getVersionCode') ?? 0;
      } catch (_) {}
      debugPrint('[*] Local Android OS versionCode: $localVersionCode (AppVersion: ${AppConstants.appVersion})');

      // 2. استعلام العقد الرسمي من السيرفر
      final url = Uri.parse('https://mohadarati.vercel.app/version.json?_t=${now.millisecondsSinceEpoch}');
      final response = await http.get(url).timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final serverVersionCode = data['android_version_code'] as int? ?? 0;
      final serverVersion = data['version']?.toString() ?? '1.0.4';
      final releaseNotes = data['release_notes']?.toString() ?? '';
      final apkUrl = data['apk_url']?.toString() ?? 'https://mohadarati.vercel.app/Mohadarati.apk';

      // 3. المقارنة الرياضية القطعية: هل إصدار السيرفر أكبر فعلياً من إصدار الجهاز؟
      if (serverVersionCode <= localVersionCode) {
        debugPrint('[*] Android is 100% up-to-date (Local: $localVersionCode >= Server: $serverVersionCode). Zero prompt.');
        // تنظيف أي ملفات تثبيت قديمة موجودة في الكاش
        final cacheDir = await getCacheDir();
        if (cacheDir != null) {
          try {
            final oldApk = File('$cacheDir/Mohadarati_v$serverVersionCode.apk');
            if (await oldApk.exists()) await oldApk.delete();
          } catch (_) {}
        }
        return;
      }

      debugPrint('[+] New Android update required! (Local: $localVersionCode < Server: $serverVersionCode)');

      // 4. عرض نافذة التحديث الإجباري بشريط التقدم
      final context = NustStudentPortalApp.navigatorKey.currentContext;
      if (context != null && !_isShowingDialog) {
        _isShowingDialog = true;
        await InAppUpdateDialog.show(
          context,
          version: serverVersion,
          versionCode: serverVersionCode,
          releaseNotes: releaseNotes,
          apkUrl: apkUrl,
        );
        _isShowingDialog = false;
      }
    } catch (e) {
      debugPrint('[-] Error checking Android update: $e');
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
}
