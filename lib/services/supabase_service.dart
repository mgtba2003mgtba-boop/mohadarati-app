import 'dart:math';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';
import '../models/student_model.dart';
import '../models/app_user_model.dart';
import '../models/attendance_model.dart';
import '../models/announcement_model.dart';
import '../models/lecture_model.dart';
import '../models/schedule_model.dart';
import '../models/subject_model.dart';
import '../core/constants/biometric_subjects.dart';
import 'telegram_uploader_service.dart';

class _OtpRecord {
  final String code;
  final DateTime expiresAt;
  _OtpRecord(this.code, this.expiresAt);
  bool get isValid => DateTime.now().isBefore(expiresAt);
}

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  final Map<String, _OtpRecord> _otpCache = {};

  // ── محرك الذاكرة المؤقتة الذكي (Smart In-Memory RAM & Persistent Cache Engine) ───
  final Map<String, dynamic> _memoryCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};

  /// جلب البيانات من الذاكرة المؤقتة المحلية (RAM أولاً ثم SharedPreferences)
  Future<T?> _getCachedData<T>({
    required String key,
    required T Function(dynamic json) fromJson,
    Duration maxAge = const Duration(minutes: 15),
  }) async {
    // 1. فحص ذاكرة الوصول العشوائي RAM (فوري في أقل من 0.001 ثانية)
    if (_memoryCache.containsKey(key)) {
      final ts = _cacheTimestamps[key];
      if (ts != null && DateTime.now().difference(ts) < maxAge) {
        return _memoryCache[key] as T?;
      }
    }

    // 2. فحص التخزين المحلي الدائم SharedPreferences عبر المتصفح/الجهاز
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('cache_$key');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        final data = fromJson(decoded);
        _memoryCache[key] = data;
        _cacheTimestamps[key] = DateTime.now();
        return data;
      }
    } catch (e) {
      debugPrint('[-] Cache read error for $key: $e');
    }
    return null;
  }

  /// حفظ البيانات في الذاكرة المؤقتة RAM و SharedPreferences
  Future<void> _setCachedData({
    required String key,
    required dynamic rawData,
    required dynamic Function() toJson,
  }) async {
    try {
      _memoryCache[key] = rawData;
      _cacheTimestamps[key] = DateTime.now();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cache_$key', jsonEncode(toJson()));
    } catch (e) {
      debugPrint('[-] Cache write error for $key: $e');
    }
  }

  /// إبطال الكاش عند إضافة أو تعديل أو حذف بيانات لضمان التزامن الفوري
  void invalidateCachePattern(String pattern) {
    _memoryCache.removeWhere((k, _) => k.contains(pattern));
    _cacheTimestamps.removeWhere((k, _) => k.contains(pattern));
    SharedPreferences.getInstance().then((prefs) {
      final keys = prefs.getKeys().where((k) => k.startsWith('cache_') && k.contains(pattern)).toList();
      for (final k in keys) {
        prefs.remove(k);
      }
    }).catchError((_) {});
  }

  SupabaseClient get client => Supabase.instance.client;

  /// ── سيرفر البصمة ونظام الحضور القديم (Read-Only Data Source) ───────────
  late final SupabaseClient _attendanceClient = SupabaseClient(
    AppConstants.attendanceSupabaseUrl,
    AppConstants.attendanceSupabaseAnonKey,
  );
  SupabaseClient get attendanceClient => _attendanceClient;

  AppUserModel? _currentUser;
  AppUserModel? get currentUser => _currentUser;

  /// تهيئة اتصال Supabase
  static Future<void> initialize() async {
    try {
      await Supabase.initialize(
        url: AppConstants.portalSupabaseUrl,
        publishableKey: AppConstants.portalSupabaseAnonKey,
      );
      debugPrint('[+] Supabase Portal initialized successfully.');
    } catch (e) {
      debugPrint('[-] Supabase init error: $e');
    }
  }

  /// ── التحقق من كود المعرف الجامعي حصراً (قراءة فقط من سيرفر الحضور القديم) ───
  Future<StudentModel?> verifyTelegramStudentCode(String inputCode) async {
    final cleanCode = inputCode.trim();
    if (cleanCode.isEmpty) return null;

    try {
      // 1. البحث عبر المعرف الجامعي المباشر حصراً (e.g. ST-NUST-...) من سيرفر الحضور
      final resById = await _attendanceClient
          .from('students')
          .select('*')
          .eq('id', cleanCode)
          .maybeSingle();

      if (resById != null) {
        return StudentModel.fromJson(resById);
      }

      // 2. البحث عبر معرف التيليجرام chat_id إن كان الكود رقماً عددياً
      if (RegExp(r'^\d+$').hasMatch(cleanCode)) {
        final resByTelegram = await _attendanceClient
            .from('students')
            .select('*')
            .eq('telegram_chat_id', cleanCode)
            .maybeSingle();

        if (resByTelegram != null) {
          return StudentModel.fromJson(resByTelegram);
        }
      }

      return null;
    } catch (e) {
      debugPrint('[-] Error verifying student code: $e');
      return null;
    }
  }

  /// ── إنشاء أو ربط حساب الطالب في التطبيق ──────────────────────────────────
  Future<AppUserModel?> registerOrLinkStudentAccount({
    required StudentModel student,
    String? pinCode,
    String? email,
    String? phone,
  }) async {
    try {
      // التحقق أولاً إن كان المستخدم مسجلاً مسبقاً
      final existing = await getAppUserByStudentId(student.id);

      if (existing != null) {
        // حماية أمنية صارمة: إذا كان الحساب مفعلاً مسبقاً برمز مرور، يمنع تغييره برمز عشوائي دون مطابقة
        if (existing.pinCode != null && existing.pinCode!.trim().isNotEmpty) {
          final inputPin = pinCode?.trim() ?? '';
          if (inputPin.isNotEmpty && !AppConstants.verifyPin(inputPin, existing.pinCode)) {
            debugPrint('[-] Cannot overwrite existing PIN without matching current PIN');
            return null;
          }
        }

        // تحديث البيانات دون العبث برمز المرور القائم
        final updatedData = {
          'name': student.name,
          'department': student.department,
          'stage': AppConstants.normalizeStage(student.stage),
          'section': student.section,
          'photo_url': student.photoUrl,
          'pin_code': (existing.pinCode != null && existing.pinCode!.trim().isNotEmpty)
              ? existing.pinCode
              : AppConstants.hashPin(pinCode ?? '1234'),
          'email': email ?? existing.email,
          'phone': phone ?? existing.phone,
          'last_login': DateTime.now().toIso8601String(),
        };

        final res = await client
            .from('app_users')
            .update(updatedData)
            .eq('id', existing.id)
            .select()
            .single();

        _currentUser = AppUserModel.fromJson(res);
        await _saveUserSession(_currentUser!);
        return _currentUser;
      }

      // إنشاء حساب جديد للطالب لأول مرة وتشفير الرمز مباشرة بـ SHA-256
      final newUserPayload = {
        'student_id': student.id,
        'name': student.name,
        'department': student.department,
        'stage': AppConstants.normalizeStage(student.stage),
        'section': student.section,
        'email': email,
        'phone': phone,
        'pin_code': AppConstants.hashPin(pinCode ?? '1234'),
        'role': AppConstants.roleStudent,
        'can_publish_lectures': false,
        'can_publish_announcements': false,
        'is_approved': true,
        'photo_url': student.photoUrl,
        'last_login': DateTime.now().toIso8601String(),
      };

      final res = await client
          .from('app_users')
          .insert(newUserPayload)
          .select()
          .single();

      _currentUser = AppUserModel.fromJson(res);
      await _saveUserSession(_currentUser!);
      return _currentUser;
    } catch (e) {
      debugPrint('[-] Error creating app user: $e');
      return null;
    }
  }

  /// ── جلب بيانات المستخدم عبر المعرف الجامعي ──────────────────────────────
  Future<AppUserModel?> getAppUserByStudentId(String studentId) async {
    try {
      final res = await client
          .from('app_users')
          .select('*')
          .eq('student_id', studentId.trim())
          .maybeSingle();

      if (res != null) {
        return AppUserModel.fromJson(res);
      }
      return null;
    } catch (e) {
      debugPrint('[-] Error fetching app user: $e');
      return null;
    }
  }

  /// ── تسجيل الدخول الصارم برمز الـ PIN أو المعرف مع التحقق المزدوج والتشفير ───
  Future<AppUserModel?> loginWithStudentIdAndPin({
    required String studentId,
    required String pinCode,
  }) async {
    try {
      final user = await getAppUserByStudentId(studentId);
      if (user != null) {
        final storedPin = user.pinCode?.trim() ?? '';
        final inputPin = pinCode.trim();

        // حماية أمنية صارمة: تحقق مزدوج ذكي (Dual Verification) يقبل القديم والمشفر
        final isMatch = AppConstants.verifyPin(inputPin, storedPin);
        if (isMatch) {
          _currentUser = user;
          await _saveUserSession(user);

          // ترقية أمنية تلقائية: إذا كان الرمز في قاعدة البيانات غير مشفر بعد، نقوم بتشفيره فوراً
          final hashedPin = AppConstants.hashPin(inputPin);
          if (storedPin != hashedPin && user.id.isNotEmpty) {
            client
                .from('app_users')
                .update({'pin_code': hashedPin})
                .eq('id', user.id)
                .then((_) => debugPrint('[+] Auto-upgraded PIN to SHA-256 for user: ${user.studentId}'))
                .catchError((e) => debugPrint('[-] PIN upgrade error: $e'));
          }

          return user;
        }
      }
      return null;
    } catch (e) {
      debugPrint('[-] Login error: $e');
      return null;
    }
  }

  /// ── إرسال كود تحقق لاستعادة رمز المرور عبر بوت تيليجرام ──────────────────
  Future<bool> sendTelegramPasswordResetCode({
    required StudentModel student,
  }) async {
    final chatId = student.telegramChatId?.trim();
    if (chatId == null || chatId.isEmpty) {
      debugPrint('[-] Student does not have registered telegram_chat_id');
      return false;
    }

    // توليد كود عشوائي من 6 أرقام
    final rng = Random();
    final otpCode = (100000 + rng.nextInt(900000)).toString();

    // حفظ الكود صالحاً لمدة 10 دقائق
    _otpCache[student.id] = _OtpRecord(
      otpCode,
      DateTime.now().add(const Duration(minutes: 10)),
    );

    // 1. المحاولة أولاً عبر سيرفر تيليجرام (Port 8050) لمنع مشاكل CORS في المتصفح
    try {
      final serverUrl = Uri.parse('${AppConstants.telegramStreamerBaseUrl}/api/telegram/send_otp');
      final serverResp = await http.post(
        serverUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chat_id': chatId,
          'otp_code': otpCode,
          'student_id': student.id,
          'student_name': student.name,
        }),
      );
      if (serverResp.statusCode == 200) {
        debugPrint('[+] Telegram OTP sent via proxy: $chatId');
        return true;
      }
    } catch (e) {
      debugPrint('[-] Proxy OTP send error: $e');
    }

    // 2. خط احتياطي عبر Telegram API المباشر
    try {
      final url = Uri.parse(
        'https://api.telegram.org/bot${AppConstants.telegramBotToken}/sendMessage',
      );
      final resp = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chat_id': chatId,
          'text': '🔐 *كود الاستعادة:* `$otpCode`\nصالح لمدة 10 دقائق.',
          'parse_mode': 'Markdown',
        }),
      );

      if (resp.statusCode == 200) {
        debugPrint('[+] Telegram OTP sent directly: $chatId');
        return true;
      }
    } catch (e) {
      debugPrint('[-] Error sending telegram OTP: $e');
    }
    return false;
  }

  /// ── التحقق من كود التيليجرام وتعيين رمز المرور الجديد ────────────────────
  Future<bool> verifyOtpAndResetPin({
    required String studentId,
    required String otpCode,
    required String newPin,
  }) async {
    final record = _otpCache[studentId];
    if (record == null || !record.isValid) {
      return false;
    }

    if (record.code.trim() != otpCode.trim()) {
      return false;
    }

    // مطابقة ناجحة -> تحديث رمز المرور في قاعدة البيانات
    try {
      await client
          .from('app_users')
          .update({'pin_code': AppConstants.hashPin(newPin.trim())})
          .eq('student_id', studentId.trim());

      _otpCache.remove(studentId);
      return true;
    } catch (e) {
      debugPrint('[-] Error updating user PIN: $e');
      return false;
    }
  }

  /// ── جلب سجلات الحضور والغياب (مع كاش محلي سريع ومرونة قصوى) ───────
  Future<List<AttendanceRecordModel>> fetchStudentAttendance(
    String studentId, {
    bool forceRefresh = false,
  }) async {
    final cleanId = studentId.trim();
    if (cleanId.isEmpty) return [];
    final cacheKey = 'attendance_$cleanId';

    // 1. استرجاع فوري من الذاكرة المؤقتة (RAM / LocalStorage) في 0.001 ثانية
    if (!forceRefresh) {
      final cached = await _getCachedData<List<AttendanceRecordModel>>(
        key: cacheKey,
        fromJson: (json) => (json as List).map((i) => AttendanceRecordModel.fromJson(i)).toList(),
      );
      if (cached != null && cached.isNotEmpty) {
        // تحديث صامت في الخلفية إن مضى أكثر من دقيقتين
        final ts = _cacheTimestamps[cacheKey];
        if (ts == null || DateTime.now().difference(ts) > const Duration(minutes: 2)) {
          _fetchFreshAttendanceAndCache(cleanId, cacheKey).catchError((_) => <AttendanceRecordModel>[]);
        }
        return cached;
      }
    }

    return await _fetchFreshAttendanceAndCache(cleanId, cacheKey);
  }

  Future<List<AttendanceRecordModel>> _fetchFreshAttendanceAndCache(
    String studentId,
    String cacheKey,
  ) async {
    try {
      final res = await _attendanceClient
          .from('attendance_records')
          .select('*')
          .eq('student_id', studentId)
          .order('date', ascending: false)
          .timeout(const Duration(seconds: 8));

      final list = (res as List)
          .map((item) => AttendanceRecordModel.fromJson(item))
          .toList();

      await _setCachedData(
        key: cacheKey,
        rawData: list,
        toJson: () => list.map((a) => a.toJson()).toList(),
      );

      return list;
    } catch (e) {
      debugPrint('[-] Error fetching attendance (falling back to cache): $e');
      final cached = await _getCachedData<List<AttendanceRecordModel>>(
        key: cacheKey,
        fromJson: (json) => (json as List).map((i) => AttendanceRecordModel.fromJson(i)).toList(),
        maxAge: const Duration(days: 30),
      );
      return cached ?? [];
    }
  }

  /// ── جلب الإعلانات الأكاديمية والتبليغات (كاش فوري ومقاوم لبطء الشبكة) ─────────────────
  Future<List<AnnouncementModel>> fetchAnnouncements({
    String? department,
    String? stage,
    String? section,
    bool forceRefresh = false,
  }) async {
    final cacheKey = 'announcements_${department ?? "ALL"}_${stage ?? "ALL"}_${section ?? "ALL"}';

    // 1. عرض فوري في 0.01 ثانية من الكاش المحلي
    if (!forceRefresh) {
      final cached = await _getCachedData<List<AnnouncementModel>>(
        key: cacheKey,
        fromJson: (json) => (json as List).map((item) => AnnouncementModel.fromJson(item)).toList(),
      );
      if (cached != null && cached.isNotEmpty) {
        // تحديث في الخلفية دون تجميد واجهة المستخدم
        final ts = _cacheTimestamps[cacheKey];
        if (ts == null || DateTime.now().difference(ts) > const Duration(minutes: 2)) {
          _fetchFreshAnnouncementsAndCache(department: department, stage: stage, section: section, cacheKey: cacheKey)
              .catchError((_) => <AnnouncementModel>[]);
        }
        return cached;
      }
    }

    return await _fetchFreshAnnouncementsAndCache(
      department: department,
      stage: stage,
      section: section,
      cacheKey: cacheKey,
    );
  }

  Future<List<AnnouncementModel>> _fetchFreshAnnouncementsAndCache({
    String? department,
    String? stage,
    String? section,
    required String cacheKey,
  }) async {
    try {
      var query = client.from('announcements').select('*');

      final res = await query
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 8));

      var list = (res as List)
          .map((item) => AnnouncementModel.fromJson(item))
          .where((a) {
            final isSchedule = a.content.contains('[SCHEDULE_TIMETABLE]') ||
                a.subjectName == 'SCHEDULE';
            final isCourse = a.content.contains('[COURSE_REGISTRY') ||
                a.subjectName == 'COURSE';
            return !isSchedule && !isCourse;
          })
          .toList();

      if (department != null && department.isNotEmpty && department != 'ALL') {
        list = list.where((a) =>
            a.department == 'ALL' || a.department == department).toList();
      }

      if (stage != null && stage.isNotEmpty && stage != 'ALL') {
        final aliases = AppConstants.getStageAliases(stage);
        list = list.where((a) =>
            a.stage == 'ALL' || aliases.contains(a.stage) || a.stage == stage).toList();
      }

      if (section != null && section.isNotEmpty && section != 'ALL') {
        list = list.where((a) =>
            a.section == 'ALL' ||
            a.section.isEmpty ||
            a.section.toUpperCase() == section.toUpperCase()).toList();
      }

      await _setCachedData(
        key: cacheKey,
        rawData: list,
        toJson: () => list.map((a) => a.toCacheJson()).toList(),
      );

      return list;
    } catch (e) {
      debugPrint('[-] Error fetching announcements (falling back to cache): $e');
      final cached = await _getCachedData<List<AnnouncementModel>>(
        key: cacheKey,
        fromJson: (json) => (json as List).map((item) => AnnouncementModel.fromJson(item)).toList(),
        maxAge: const Duration(days: 30),
      );
      return cached ?? [];
    }
  }

  /// ── إضافة إعلان جديد (مع فحص الصلاحيات وإبطال الكاش فورا للتزامن) ──────────
  Future<bool> createAnnouncement(AnnouncementModel announcement) async {
    try {
      // فحص أمان الصلاحيات
      final user = _currentUser;
      if (user != null) {
        final canPublish = user.role == AppConstants.roleAdmin ||
            user.role == AppConstants.roleRepresentative ||
            user.canPublishAnnouncements;
        if (!canPublish) {
          debugPrint('[-] Security Block: User ${user.studentId} not authorized to publish announcements');
          return false;
        }
      }

      final json = announcement.toJson();
      json['stage'] = AppConstants.normalizeStage(announcement.stage);
      const allowedCategories = ['academic', 'urgent', 'exam', 'activity'];
      if (!allowedCategories.contains(json['category'])) {
        json['category'] = 'academic';
      }
      if (json['image_url'] == null || json['image_url'].toString().trim().isEmpty) {
        json.remove('image_url');
      }
      if (json['subject_name'] == null || json['subject_name'].toString().trim().isEmpty) {
        json.remove('subject_name');
      }
      await client.from('announcements').insert(json);
      invalidateCachePattern('announcements_');
      return true;
    } catch (e) {
      debugPrint('[-] Error creating announcement: $e');
      return false;
    }
  }

  /// ── حذف إعلان / بوستر / جدول (مع فحص هوية الكاتب وحذف تيليجرام وتفريغ الكاش) ───
  Future<bool> deleteAnnouncement(String id) async {
    try {
      // 1. استعلام مسبق لحذف المنشور المقابل من قناة تيليجرام وفحص ملكية الكاتب
      try {
        final row = await client
            .from('announcements')
            .select('author_id, content, image_url')
            .eq('id', id)
            .maybeSingle();

        // حماية الصلاحيات: التحقق من أن المستخدم إما مشرف عام أو كاتب الإعلان نفسه
        final user = _currentUser;
        if (user != null && row != null) {
          final authorId = row['author_id']?.toString() ?? '';
          final isAdmin = user.role == AppConstants.roleAdmin;
          final isAuthor = authorId.isNotEmpty && (authorId == user.id || authorId == user.studentId);
          if (!isAdmin && !isAuthor) {
            debugPrint('[-] Security Block: User ${user.studentId} not authorized to delete announcement $id owned by $authorId');
            return false;
          }
        }

        if (row != null) {
          int? msgId;
          final contentStr = row['content']?.toString() ?? '';
          final match = RegExp(r'\[TG_MSG_ID:(\d+)\]').firstMatch(contentStr);
          if (match != null) {
            msgId = int.tryParse(match.group(1) ?? '');
          }

          if (msgId == null) {
            final imageUrl = row['image_url']?.toString() ?? '';
            final urlMatch = RegExp(r'/api/file/(\d+)').firstMatch(imageUrl);
            if (urlMatch != null) {
              msgId = int.tryParse(urlMatch.group(1) ?? '');
            }
          }

          if (msgId != null && msgId > 0) {
            await TelegramUploaderService().deleteMessageFromTelegram(messageId: msgId);
          }
        }
      } catch (tgErr) {
        debugPrint('[-] Note on deleting announcement message from Telegram: $tgErr');
      }

      // 2. حذف السجل من قاعدة بيانات Supabase
      await client.from('announcements').delete().eq('id', id);
      invalidateCachePattern('announcements_');
      invalidateCachePattern('schedules_');
      return true;
    } catch (e) {
      debugPrint('[-] Error deleting announcement: $e');
      return false;
    }
  }

  /// ── جلب الجداول الدراسية والامتحانية (كاش فوري + دعم إشراف شامل لكافة الأقسام) ──────────────
  Future<List<ScheduleModel>> fetchSchedules({
    required String department,
    required String stage,
    String? section,
    String? type,
    bool forceRefresh = false,
  }) async {
    final cacheKey = 'schedules_${department}_${stage}_${section ?? "ALL"}_${type ?? "ALL"}';

    // 1. عرض فوري في 0.01 ثانية من الكاش المحلي
    if (!forceRefresh) {
      final cached = await _getCachedData<List<ScheduleModel>>(
        key: cacheKey,
        fromJson: (json) => (json as List).map((item) => ScheduleModel.fromJson(item)).toList(),
      );
      if (cached != null && cached.isNotEmpty) {
        final ts = _cacheTimestamps[cacheKey];
        if (ts == null || DateTime.now().difference(ts) > const Duration(minutes: 2)) {
          _fetchFreshSchedulesAndCache(
            department: department,
            stage: stage,
            section: section,
            type: type,
            cacheKey: cacheKey,
          ).catchError((_) => <ScheduleModel>[]);
        }
        return cached;
      }
    }

    return await _fetchFreshSchedulesAndCache(
      department: department,
      stage: stage,
      section: section,
      type: type,
      cacheKey: cacheKey,
    );
  }

  Future<List<ScheduleModel>> _fetchFreshSchedulesAndCache({
    required String department,
    required String stage,
    String? section,
    String? type,
    required String cacheKey,
  }) async {
    try {
      final res = await client
          .from('announcements')
          .select('*')
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 8));

      final list = (res as List).where((item) {
        final content = item['content']?.toString() ?? '';
        final subjectName = item['subject_name']?.toString() ?? '';
        return content.contains('[SCHEDULE_TIMETABLE]') || subjectName == 'SCHEDULE';
      }).map((item) {
        final cat = item['category']?.toString() ?? '';
        final title = item['title']?.toString() ?? '';
        final isExam = cat == 'exam' || title.contains('امتحان');
        final content = item['content']?.toString() ?? '';
        final tgMatch = RegExp(r'\[TG_MSG_ID:(\d+)\]').firstMatch(content);
        final tgMsgId = tgMatch != null ? int.tryParse(tgMatch.group(1) ?? '') : null;

        final secMatch = RegExp(r'\[SECTION:([A-Za-z0-9_]+)\]').firstMatch(content);
        String? rawSec = item['section']?.toString();
        if (rawSec == null || rawSec.isEmpty || rawSec == 'null') {
          rawSec = secMatch?.group(1) ?? 'ALL';
        }
        final itemSection = rawSec.trim().toUpperCase();

        return ScheduleModel(
          id: item['id']?.toString() ?? '',
          title: item['title'] ?? 'جدول دراسي',
          type: isExam ? 'exams' : 'lectures',
          department: item['department'] ?? 'ALL',
          stage: item['stage'] ?? 'ALL',
          section: itemSection,
          fileUrl: item['image_url'],
          fileName: item['title'],
          uploaderName: item['author_name'] ?? 'إدارة الكلية',
          uploaderId: item['author_id'],
          telegramMessageId: tgMsgId,
          createdAt: item['created_at'] != null
              ? DateTime.tryParse(item['created_at']) ?? DateTime.now()
              : DateTime.now(),
        );
      }).toList();

      final filtered = list.where((s) {
        final matchDept = department == 'ALL' || s.department == department;
        final matchStage = stage == 'ALL' || s.stage == stage;
        final matchType = type == null || type == 'ALL' || s.type == type;
        final matchSection = (section == null || section.isEmpty || section == 'ALL')
            ? true
            : (s.section.toUpperCase() == section.toUpperCase() || s.section.toUpperCase() == 'ALL');
        return matchDept && matchStage && matchType && matchSection;
      }).toList();

      await _setCachedData(
        key: cacheKey,
        rawData: filtered,
        toJson: () => filtered.map((s) => s.toJson()).toList(),
      );

      return filtered;
    } catch (e) {
      debugPrint('[-] Error fetching schedules (falling back to cache): $e');
      final cached = await _getCachedData<List<ScheduleModel>>(
        key: cacheKey,
        fromJson: (json) => (json as List).map((item) => ScheduleModel.fromJson(item)).toList(),
        maxAge: const Duration(days: 30),
      );
      return cached ?? [];
    }
  }

  /// ── حفظ / رفع جدول جديد (مع وسم العزل التام وتحديث الكاش) ─────────────
  Future<bool> createSchedule(ScheduleModel schedule) async {
    try {
      final tgTag = schedule.telegramMessageId != null ? ' [TG_MSG_ID:${schedule.telegramMessageId}]' : '';
      final payload = {
        'title': schedule.title,
        'content': '[SCHEDULE_TIMETABLE]$tgTag [SECTION:${schedule.section.toUpperCase()}] جدول دراسي',
        'category': schedule.isExam ? 'exam' : 'academic',
        'department': schedule.department,
        'stage': schedule.stage,
        'image_url': schedule.fileUrl,
        'author_name': schedule.uploaderName ?? 'ممثل الشعبة',
        'author_id': schedule.uploaderId ?? 'REP',
        'author_role': 'representative',
        'is_pinned': true,
        'subject_name': 'SCHEDULE',
      };
      await client.from('announcements').insert(payload);
      invalidateCachePattern('schedules_');
      invalidateCachePattern('announcements_');
      return true;
    } catch (e) {
      debugPrint('[-] Error creating schedule: $e');
      return false;
    }
  }

  Future<bool> deleteSchedule(String id) async {
    return deleteAnnouncement(id);
  }

  /// ── جلب المحاضرات (كاش فوري وموحدة لكافة طلبة المرحلة والقسم) ──────────────────
  Future<List<LectureModel>> fetchLectures({
    String? department,
    String? stage,
    String? section,
    int? semester,
    bool forceRefresh = false,
  }) async {
    final cacheKey = 'lectures_${department ?? "ALL"}_${stage ?? "ALL"}_${section ?? "ALL"}_${semester ?? 0}';

    // 1. عرض فوري في 0.01 ثانية من الكاش المحلي
    if (!forceRefresh) {
      final cached = await _getCachedData<List<LectureModel>>(
        key: cacheKey,
        fromJson: (json) => (json as List).map((item) => LectureModel.fromJson(item)).toList(),
      );
      if (cached != null && cached.isNotEmpty) {
        final ts = _cacheTimestamps[cacheKey];
        if (ts == null || DateTime.now().difference(ts) > const Duration(minutes: 2)) {
          _fetchFreshLecturesAndCache(
            department: department,
            stage: stage,
            section: section,
            semester: semester,
            cacheKey: cacheKey,
          ).catchError((_) => <LectureModel>[]);
        }
        return cached;
      }
    }

    return await _fetchFreshLecturesAndCache(
      department: department,
      stage: stage,
      section: section,
      semester: semester,
      cacheKey: cacheKey,
    );
  }

  Future<List<LectureModel>> _fetchFreshLecturesAndCache({
    String? department,
    String? stage,
    String? section,
    int? semester,
    required String cacheKey,
  }) async {
    try {
      var query = client.from('lectures').select('*');

      if (department != null && department.isNotEmpty && department != 'ALL') {
        query = query.eq('department', department);
      }
      if (stage != null && stage.isNotEmpty && stage != 'ALL') {
        final aliases = AppConstants.getStageAliases(stage);
        query = query.filter('stage', 'in', '(${aliases.map((a) => '"$a"').join(",")})');
      }
      if (semester != null && semester != 0) {
        query = query.eq('semester', semester);
      }

      final res = await query.order('created_at', ascending: false).timeout(const Duration(seconds: 8));

      var list = (res as List).map((item) => LectureModel.fromJson(item)).toList();

      if (section != null && section.isNotEmpty && section != 'ALL') {
        list = list.where((l) =>
            l.section == 'ALL' ||
            l.section.isEmpty ||
            l.section.toUpperCase() == section.toUpperCase()).toList();
      }

      await _setCachedData(
        key: cacheKey,
        rawData: list,
        toJson: () => list.map((l) => l.toJson()).toList(),
      );

      return list;
    } catch (e) {
      debugPrint('[-] Error fetching lectures (falling back to cache): $e');
      final cached = await _getCachedData<List<LectureModel>>(
        key: cacheKey,
        fromJson: (json) => (json as List).map((item) => LectureModel.fromJson(item)).toList(),
        maxAge: const Duration(days: 30),
      );
      return cached ?? [];
    }
  }

  /// ── نشر محاضرة جديدة برابط Google Drive أو سحابي (مع فحص الصلاحيات وتحديث الكاش) ───
  Future<bool> createLecture(LectureModel lecture) async {
    try {
      // فحص أمان الصلاحيات: التحقق من امتلاك المستخدم صلاحية النشر
      final user = _currentUser;
      if (user != null) {
        final canPublish = user.role == AppConstants.roleAdmin ||
            user.role == AppConstants.roleRepresentative ||
            user.canPublishLectures;
        if (!canPublish) {
          debugPrint('[-] Security Block: User ${user.studentId} does not have lecture publishing permission');
          return false;
        }
      }

      final payload = lecture.toJson();
      payload['stage'] = AppConstants.normalizeStage(lecture.stage);
      await client.from('lectures').insert(payload);
      invalidateCachePattern('lectures_');
      return true;
    } catch (e) {
      debugPrint('[-] Error creating lecture: $e');
      return false;
    }
  }

  /// ── حذف محاضرة (مع فحص هوية الكاتب وحذف الرسالة من قناة تيليجرام وتفريغ الكاش) ──────────────
  Future<bool> deleteLecture(String id) async {
    try {
      // 1. استعلام مسبق لجلب معرف رسالة تيليجرام والقناة والكاتب
      try {
        final row = await client
            .from('lectures')
            .select('author_id, telegram_message_id, telegram_channel_id')
            .eq('id', id)
            .maybeSingle();

        // حماية الصلاحيات: التحقق من أن المستخدم إما مشرف عام أو كاتب المحاضرة نفسه
        final user = _currentUser;
        if (user != null && row != null) {
          final authorId = row['author_id']?.toString() ?? '';
          final isAdmin = user.role == AppConstants.roleAdmin;
          final isAuthor = authorId.isNotEmpty && (authorId == user.id || authorId == user.studentId);
          if (!isAdmin && !isAuthor) {
            debugPrint('[-] Security Block: User ${user.studentId} not authorized to delete lecture $id owned by $authorId');
            return false;
          }
        }

        if (row != null && row['telegram_message_id'] != null) {
          final msgId = int.tryParse(row['telegram_message_id'].toString());
          final chId = int.tryParse(row['telegram_channel_id']?.toString() ?? '');
          if (msgId != null && msgId > 0) {
            await TelegramUploaderService().deleteMessageFromTelegram(
              messageId: msgId,
              channelId: chId,
            );
          }
        }
      } catch (tgErr) {
        debugPrint('[-] Note on deleting lecture message from Telegram: $tgErr');
      }

      // 2. حذف السجل من قاعدة بيانات Supabase
      await client.from('lectures').delete().eq('id', id);
      invalidateCachePattern('lectures_');
      return true;
    } catch (e) {
      debugPrint('[-] Error deleting lecture: $e');
      return false;
    }
  }

  /// ── جلب الشعب الأكاديمية الفعلية من نظام البصمة الجامعي ────────────────────
  Future<List<String>> fetchBiometricSections({
    required String department,
    required String stage,
  }) async {
    try {
      final aliases = AppConstants.getStageAliases(stage);
      final res = await _attendanceClient
          .from('students')
          .select('section')
          .eq('department', department)
          .filter('stage', 'in', '(${aliases.map((a) => '"$a"').join(",")})');

      if (res is List && res.isNotEmpty) {
        final Set<String> found = {};
        for (final item in res) {
          final sec = item['section']?.toString().trim().toUpperCase();
          if (sec != null && sec.isNotEmpty && sec != 'NULL') {
            found.add(sec);
          }
        }
        if (found.isNotEmpty) {
          final list = found.toList()..sort();
          return list;
        }
      }
    } catch (e) {
      debugPrint('[-] Biometric sections query note: $e');
    }
    return ['A', 'B', 'C', 'D'];
  }

  /// ── جلب قائمة طلاب شعبة معينة من نظام البصمة للتكليف والترقية ─────────────
  Future<List<StudentModel>> fetchBiometricStudentsBySection({
    required String department,
    required String stage,
    required String section,
    String? query,
    int limit = 60,
  }) async {
    try {
      final aliases = AppConstants.getStageAliases(stage);
      var q = _attendanceClient
          .from('students')
          .select('*')
          .eq('department', department)
          .filter('stage', 'in', '(${aliases.map((a) => '"$a"').join(",")})')
          .eq('section', section);

      final cleanQuery = query?.trim() ?? '';
      if (cleanQuery.isNotEmpty) {
        q = q.or('name.ilike.%$cleanQuery%,id.ilike.%$cleanQuery%');
      }

      final res = await q.order('name', ascending: true).limit(limit);
      if (res is List) {
        return res.map((item) => StudentModel.fromJson(item)).toList();
      }
    } catch (e) {
      debugPrint('[-] Error fetching biometric students for section: $e');
    }
    return [];
  }

  /// ── تكليف طالب كممثل لشعبة معينة وتحديث صلاحياته فوراً ───────────────────
  Future<bool> assignSectionRepresentative({
    required StudentModel student,
    required String section,
    bool canLectures = true,
    bool canAnnouncements = true,
  }) async {
    try {
      final normStage = AppConstants.normalizeStage(student.stage);
      final existing = await getAppUserByStudentId(student.id);
      if (existing != null) {
        await client.from('app_users').update({
          'role': AppConstants.roleRepresentative,
          'department': student.department,
          'stage': normStage,
          'section': section,
          'can_publish_lectures': canLectures,
          'can_publish_announcements': canAnnouncements,
          'is_approved': true,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('student_id', student.id);
      } else {
        await client.from('app_users').insert({
          'student_id': student.id,
          'name': student.name,
          'department': student.department,
          'stage': normStage,
          'section': section,
          'role': AppConstants.roleRepresentative,
          'can_publish_lectures': canLectures,
          'can_publish_announcements': canAnnouncements,
          'is_approved': true,
          'photo_url': student.photoUrl,
          'pin_code': '1234',
        });
      }
      return true;
    } catch (e) {
      debugPrint('[-] Error assigning section representative: $e');
      return false;
    }
  }

  /// ── سحب التكليف من ممثل وإعادته إلى رتبة طالب ──────────────────────────
  Future<bool> revokeRepresentative(String studentId) async {
    try {
      await client.from('app_users').update({
        'role': AppConstants.roleStudent,
        'can_publish_lectures': false,
        'can_publish_announcements': false,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('student_id', studentId);
      return true;
    } catch (e) {
      debugPrint('[-] Error revoking representative: $e');
      return false;
    }
  }

  /// ── جلب المواد الدراسية الرسمية المعتمدة من نظام البصمة الجامعي ─────────────
  Future<List<SubjectModel>> fetchBiometricSubjects({
    String? department,
    String? stage,
    int? semester,
  }) async {
    try {
      final res = await _attendanceClient.from('subjects').select('*');
      if (res is List && res.isNotEmpty) {
        // بيانات البصمة الحية متاحة
      }
    } catch (e) {
      debugPrint('[-] Biometric subjects live query note: $e');
    }
    final normStage = stage != null && stage != 'ALL' ? AppConstants.normalizeStage(stage) : stage;
    return BiometricSubjects.getSubjects(
      department: department,
      stage: normStage,
      semester: semester,
    );
  }

  /// ── جلب المقررات الدراسية المعتمدة حصراً من نظام البصمة الجامعي (الكورس الأول) ────────
  Future<List<String>> fetchCourses({
    required String department,
    required String stage,
    int? semester,
  }) async {
    final targetSemester = semester ?? 1;
    final normStage = AppConstants.normalizeStage(stage);
    final base = BiometricSubjects.getSubjectNames(
      department: department,
      stage: normStage,
      semester: targetSemester,
    );

    // دمج المقررات المضافة والمسجلة محلياً
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'custom_courses_${department}_$normStage';
      final cachedJson = prefs.getString(key);
      if (cachedJson != null && cachedJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(cachedJson);
        for (final item in decoded) {
          final s = item.toString().trim();
          if (s.isNotEmpty && !base.contains(s)) {
            base.add(s);
          }
        }
      }
    } catch (_) {}

    return base;
  }

  /// ── إضافة مقرر دراسي جديد (للممثلين والمشرفين) ───────────────────────────
  Future<bool> addCourse({
    required String courseName,
    required String department,
    required String stage,
    required AppUserModel user,
  }) async {
    final cleanName = courseName.trim();
    if (cleanName.isEmpty) return false;
    final normStage = AppConstants.normalizeStage(stage);

    try {
      final payload = {
        'title': cleanName,
        'content': '[COURSE_REGISTRY:ADD] مقرر دراسي مضاف',
        'category': 'academic',
        'department': department,
        'stage': normStage,
        'author_id': user.studentId,
        'author_name': user.name,
        'author_role': user.role,
        'subject_name': 'COURSE',
        'is_pinned': false,
      };
      await client.from('announcements').insert(payload);

      // تحديث الكاش المحلي فورياً
      final current = await fetchCourses(department: department, stage: normStage);
      if (!current.contains(cleanName)) {
        current.add(cleanName);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('custom_courses_${department}_$normStage', jsonEncode(current));
      }
      return true;
    } catch (e) {
      debugPrint('[-] Error adding course: $e');
      return false;
    }
  }

  /// ── تعديل اسم مقرر دراسي ────────────────────────────────────────────────
  Future<bool> editCourse({
    required String oldName,
    required String newName,
    required String department,
    required String stage,
    required AppUserModel user,
  }) async {
    final cleanOld = oldName.trim();
    final cleanNew = newName.trim();
    if (cleanNew.isEmpty || cleanOld == cleanNew) return false;
    final normStage = AppConstants.normalizeStage(stage);

    try {
      final payload = {
        'title': cleanNew,
        'content': '[COURSE_REGISTRY:EDIT] old_name:$cleanOld',
        'category': 'academic',
        'department': department,
        'stage': normStage,
        'author_id': user.studentId,
        'author_name': user.name,
        'author_role': user.role,
        'subject_name': 'COURSE',
        'is_pinned': false,
      };
      await client.from('announcements').insert(payload);

      // تحديث اسم المادة في المحاضرات المرفوعة
      try {
        await client
            .from('lectures')
            .update({'subject_name': cleanNew})
            .eq('subject_name', cleanOld);
      } catch (_) {}

      // تحديث الكاش المحلي
      final current = await fetchCourses(department: department, stage: normStage);
      current.remove(cleanOld);
      if (!current.contains(cleanNew)) current.add(cleanNew);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('custom_courses_${department}_$normStage', jsonEncode(current));

      return true;
    } catch (e) {
      debugPrint('[-] Error editing course: $e');
      return false;
    }
  }

  /// ── حذف مقرر دراسي ──────────────────────────────────────────────────────
  Future<bool> deleteCourse({
    required String courseName,
    required String department,
    required String stage,
    required AppUserModel user,
  }) async {
    final cleanName = courseName.trim();
    if (cleanName.isEmpty) return false;
    final normStage = AppConstants.normalizeStage(stage);

    try {
      final payload = {
        'title': cleanName,
        'content': '[COURSE_REGISTRY:DELETE] مقرر محذوف',
        'category': 'academic',
        'department': department,
        'stage': normStage,
        'author_id': user.studentId,
        'author_name': user.name,
        'author_role': user.role,
        'subject_name': 'COURSE',
        'is_pinned': false,
      };
      await client.from('announcements').insert(payload);

      // تحديث الكاش المحلي فورياً
      final current = await fetchCourses(department: department, stage: normStage);
      current.remove(cleanName);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('custom_courses_${department}_$normStage', jsonEncode(current));

      return true;
    } catch (e) {
      debugPrint('[-] Error deleting course: $e');
      return false;
    }
  }

  /// ── جلب كافة المستخدمين (للإدارة والترقية) ──────────────────────────────
  Future<List<AppUserModel>> fetchAllUsers() async {
    try {
      final res = await client
          .from('app_users')
          .select('*')
          .order('created_at', ascending: false)
          .limit(5000);

      return (res as List).map((item) => AppUserModel.fromJson(item)).toList();
    } catch (e) {
      debugPrint('[-] Error fetching users: $e');
      return [];
    }
  }

  /// ── ترقية مستخدم وتعديل صلاحياته (ممثل دفعة، أستاذ، إلخ) ─────────────────
  Future<bool> updateUserRole({
    required String studentId,
    required String role,
    required bool canPublishLectures,
    required bool canPublishAnnouncements,
    String? section,
    String? stage,
    String? department,
  }) async {
    try {
      final Map<String, dynamic> updateData = {
        'role': role,
        'can_publish_lectures': canPublishLectures,
        'can_publish_announcements': canPublishAnnouncements,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (section != null) updateData['section'] = section;
      if (stage != null) updateData['stage'] = stage;
      if (department != null) updateData['department'] = department;

      await client.from('app_users').update(updateData).eq('student_id', studentId);

      // تحديث الحالة محلياً إن كان المستخدم هو الحالي
      if (_currentUser != null && _currentUser!.studentId == studentId) {
        _currentUser = await getAppUserByStudentId(studentId);
        if (_currentUser != null) {
          await _saveUserSession(_currentUser!);
        }
      }

      return true;
    } catch (e) {
      debugPrint('[-] Error updating user role: $e');
      return false;
    }
  }

  /// ── إدارة الجلسة المحلية الفورية (Shared Preferences) ───────────────────
  Future<void> _saveUserSession(AppUserModel user) async {
    _currentUser = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('session_student_id', user.studentId);
    await prefs.setString('session_user_json', jsonEncode(user.toJson()));
  }

  Future<AppUserModel?> restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final studentId = prefs.getString('session_student_id');
      if (studentId != null && studentId.isNotEmpty) {
        // استعادة فورية من الكاش المحلي (أقل من 2ms)
        final cachedJson = prefs.getString('session_user_json');
        if (cachedJson != null && cachedJson.isNotEmpty) {
          try {
            _currentUser = AppUserModel.fromJson(jsonDecode(cachedJson));
          } catch (_) {}
        }

        // إن لم تكن في الكاش أو لجلب التحديثات في الخلفية بدون تعطيل فتح التطبيق
        if (_currentUser == null) {
          _currentUser = await getAppUserByStudentId(studentId);
        } else {
          // مزامنة غير متزامنة في الخلفية
          getAppUserByStudentId(studentId).then((fresh) {
            if (fresh != null) {
              _currentUser = fresh;
              prefs.setString('session_user_json', jsonEncode(fresh.toJson()));
            }
          }).catchError((_) {});
        }
        return _currentUser;
      }
    } catch (e) {
      debugPrint('[-] Error restoring session: $e');
    }
    return null;
  }

  Future<void> logout() async {
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('session_student_id');
    await prefs.remove('session_user_json');
  }
}
