import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';
import 'app_notification_service.dart';

/// ── خدمة التحديث التلقائي الصامت (Silent In-App Auto-Updater) ──────────────
/// تفحص وجود أي إصدار أحدث عند الإقلاع، وتقوم بتنزيله صامتاً في الخلفية
/// دون أي إزعاج أو أزرار، وتُظهر إشعاراً علوياً هادئاً فور اكتمال التنزيل
/// لتثبيت التحديث بنقرة واحدة عبر النظام مباشرة.
class AutoUpdateService with WidgetsBindingObserver {
  static final AutoUpdateService _instance = AutoUpdateService._internal();
  factory AutoUpdateService() => _instance;
  AutoUpdateService._internal();

  static const MethodChannel _updaterChannel = MethodChannel('iq.edu.nust.mohadarati/updater');

  bool _initialized = false;
  String? _currentBuildNumber;
  DateTime _lastCheckTime = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isDownloading = false;
  String? _downloadedApkPath;

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
      if (!isUserBusy) {
        checkUpdate();
      }
    }
  }

  Future<void> checkUpdate() async {
    if (isUserBusy) return;

    final now = DateTime.now();
    if (now.difference(_lastCheckTime).inSeconds < 25) return;
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
            debugPrint('[+] Web version detected: $serverBuild (was: $_currentBuildNumber)');
            await prefs.setString('nust_build_number', serverBuild);
          }
        }
      }
    } catch (e) {
      debugPrint('[-] Error checking web updates: $e');
    }
  }

  Future<void> _checkAndroidUpdate(DateTime now) async {
    if (_isDownloading) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      _currentBuildNumber ??= prefs.getString('nust_android_build_number') ?? AppConstants.appVersion;

      // 1. استعلام رقم الإصدار من السيرفر السحابي
      final url = Uri.parse('https://mohadarati.vercel.app/version.json?_t=${now.millisecondsSinceEpoch}');
      final response = await http.get(url).timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final serverVersion = data['version']?.toString() ?? '';
      final serverBuild = data['build_number']?.toString() ?? '';
      final apkUrl = data['apk_url']?.toString() ?? 'https://mohadarati.vercel.app/Mohadarati.apk';

      // مقارنة رقم الإصدار أو رقم البناء
      final bool hasNewerVersion = _isNewerVersion(serverVersion, AppConstants.appVersion) ||
          (_currentBuildNumber != null && serverBuild.isNotEmpty && _currentBuildNumber != serverBuild);

      if (!hasNewerVersion) {
        debugPrint('[*] Android App is up to date (${AppConstants.appVersion}).');
        return;
      }

      debugPrint('[+] New Android update available: $serverVersion ($serverBuild)');

      // 2. الحصول على مسار الكاش الآمن عبر Native MethodChannel
      final cacheDir = await _updaterChannel.invokeMethod<String>('getCacheDir');
      if (cacheDir == null) return;

      final targetFile = File('$cacheDir/Mohadarati_update.apk');

      // 3. التحقق إذا كان الملف محملاً مسبقاً وبحجم سليم (أكبر من 15MB)
      if (await targetFile.exists()) {
        final length = await targetFile.length();
        if (length > 15 * 1024 * 1024) {
          _downloadedApkPath = targetFile.path;
          _notifyUserForInstall(serverVersion);
          return;
        }
      }

      // 4. بدء التنزيل الصامت في الخلفية دون أي مقاطعة
      _isDownloading = true;
      debugPrint('[*] Starting silent background download of APK from: $apkUrl');

      final apkUri = Uri.parse(apkUrl);
      final client = http.Client();
      final req = http.Request('GET', apkUri);
      final streamedResponse = await client.send(req).timeout(const Duration(seconds: 180));

      if (streamedResponse.statusCode == 200) {
        final sink = targetFile.openWrite();
        await streamedResponse.stream.pipe(sink);
        await sink.flush();
        await sink.close();

        final fileSize = await targetFile.length();
        debugPrint('[SUCCESS] APK downloaded successfully ($fileSize bytes) to: ${targetFile.path}');

        if (fileSize > 15 * 1024 * 1024) {
          _downloadedApkPath = targetFile.path;
          await prefs.setString('nust_android_build_number', serverBuild);
          _notifyUserForInstall(serverVersion);
        }
      }
    } catch (e) {
      debugPrint('[-] Error during silent background update: $e');
    } finally {
      _isDownloading = false;
    }
  }

  bool _isNewerVersion(String server, String local) {
    if (server.isEmpty || local.isEmpty) return false;
    try {
      final sParts = server.replaceAll('v', '').split('.').map(int.parse).toList();
      final lParts = local.replaceAll('v', '').split('.').map(int.parse).toList();
      for (int i = 0; i < sParts.length && i < lParts.length; i++) {
        if (sParts[i] > lParts[i]) return true;
        if (sParts[i] < lParts[i]) return false;
      }
      return sParts.length > lParts.length;
    } catch (_) {
      return server != local;
    }
  }

  void _notifyUserForInstall(String version) {
    AppNotificationService.instance.showInAppNotification(
      AppNotificationItem(
        id: 'update_${DateTime.now().millisecondsSinceEpoch}',
        title: '✨ يتوفر تحديث جديد للمنظومة ($version)',
        message: 'تم تنزيل النسخة الجديدة بنجاح في الخلفية. اضغط هنا للتثبيت الآن.',
        type: AppNotificationType.update,
        timestamp: DateTime.now(),
      ),
    );
  }

  /// إطلاق شاشة تثبيت الأندرويد الرسمية للملف المحمل
  Future<void> installDownloadedUpdate() async {
    if (_downloadedApkPath == null) {
      try {
        final cacheDir = await _updaterChannel.invokeMethod<String>('getCacheDir');
        if (cacheDir != null) {
          final file = File('$cacheDir/Mohadarati_update.apk');
          if (await file.exists() && await file.length() > 15 * 1024 * 1024) {
            _downloadedApkPath = file.path;
          }
        }
      } catch (_) {}
    }

    if (_downloadedApkPath != null) {
      debugPrint('[*] Triggering native package installer for: $_downloadedApkPath');
      try {
        await _updaterChannel.invokeMethod('installApk', {'filePath': _downloadedApkPath});
      } catch (e) {
        debugPrint('[-] Failed to launch package installer: $e');
      }
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
}
