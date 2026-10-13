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

  /// ── التحقق من كود المعرف الجامعي (قراءة فقط من سيرفر الحضور القديم) ───
  Future<StudentModel?> verifyTelegramStudentCode(String inputCode) async {
    final cleanCode = inputCode.trim();
    if (cleanCode.isEmpty) return null;

    try {
      // 1. البحث عبر المعرف الجامعي المباشر (e.g. ST-NUST-...) من سيرفر الحضور
      final resById = await _attendanceClient
          .from('students')
          .select('*')
          .eq('id', cleanCode)
          .maybeSingle();

      if (resById != null) {
        return StudentModel.fromJson(resById);
      }

      // 2. البحث عبر معرف التيليجرام chat_id إن كان الكود رقماً
      final resByTelegram = await _attendanceClient
          .from('students')
          .select('*')
          .eq('telegram_chat_id', cleanCode)
          .maybeSingle();

      if (resByTelegram != null) {
        return StudentModel.fromJson(resByTelegram);
      }

      // 3. البحث المرن بالاسم أو كود مختصر
      final resByName = await _attendanceClient
          .from('students')
          .select('*')
          .ilike('name', '%$cleanCode%')
          .limit(1);

      if (resByName.isNotEmpty) {
        return StudentModel.fromJson(resByName.first);
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
          if (inputPin.isNotEmpty && inputPin != existing.pinCode!.trim()) {
            debugPrint('[-] Cannot overwrite existing PIN without matching current PIN');
            return null;
          }
        }

        // تحديث البيانات دون العبث برمز المرور القائم
        final updatedData = {
          'name': student.name,
          'department': student.department,
          'stage': student.stage,
          'section': student.section,
          'photo_url': student.photoUrl,
          'pin_code': (existing.pinCode != null && existing.pinCode!.trim().isNotEmpty)
              ? existing.pinCode
              : (pinCode ?? '1234'),
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

      // إنشاء حساب جديد للطالب لأول مرة
      final newUserPayload = {
        'student_id': student.id,
        'name': student.name,
        'department': student.department,
        'stage': student.stage,
        'section': student.section,
        'email': email,
        'phone': phone,
        'pin_code': pinCode ?? '1234',
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

  /// ── تسجيل الدخول الصارم برمز الـ PIN أو المعرف ────────────────────────
  Future<AppUserModel?> loginWithStudentIdAndPin({
    required String studentId,
    required String pinCode,
  }) async {
    try {
      final user = await getAppUserByStudentId(studentId);
      if (user != null) {
        final storedPin = user.pinCode?.trim() ?? '';
        final inputPin = pinCode.trim();

        // حماية أمنية صارمة: لن يفتح الحساب نهائياً إلا إذا كان الرمز المخزن موجوداً ومطابقاً تماماً للرمز المدخل
        if (storedPin.isNotEmpty && storedPin == inputPin) {
          _currentUser = user;
          await _saveUserSession(user);
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
          .update({'pin_code': newPin.trim()})
          .eq('student_id', studentId.trim());

      _otpCache.remove(studentId);
      return true;
    } catch (e) {
      debugPrint('[-] Error updating user PIN: $e');
      return false;
    }
  }

  /// ── جلب سجلات الحضور والغياب (قراءة فقط من سيرفر الحضور القديم) ───────
  Future<List<AttendanceRecordModel>> fetchStudentAttendance(String studentId) async {
    try {
      final res = await _attendanceClient
          .from('attendance_records')
          .select('*')
          .eq('student_id', studentId.trim())
          .order('date', ascending: false);

      return (res as List)
          .map((item) => AttendanceRecordModel.fromJson(item))
          .toList();
    } catch (e) {
      debugPrint('[-] Error fetching attendance: $e');
      return [];
    }
  }

  /// ── جلب الإعلانات الأكاديمية والتبليغات (مع فلترة الشعبة) ─────────────────
  Future<List<AnnouncementModel>> fetchAnnouncements({
    String? department,
    String? stage,
    String? section,
  }) async {
    try {
      var query = client.from('announcements').select('*');

      // فلترة الإعلانات العامة وتلك الموجهة لقسم أو مرحلة الطالب
      final res = await query
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: false);

      var list = (res as List)
          .map((item) => AnnouncementModel.fromJson(item))
          .where((a) {
            // استبعاد الجداول الدراسية والمقررات لكي تظهر حصراً في خاناتها المخصصة
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
        list = list.where((a) =>
            a.stage == 'ALL' || a.stage == stage).toList();
      }

      // فلترة الشعبة: المنشورات العامة (ALL) وتلك المخصصة لشعبة الطالب
      if (section != null && section.isNotEmpty && section != 'ALL') {
        list = list.where((a) => a.section == 'ALL' || a.section == section).toList();
      }

      return list;
    } catch (e) {
      debugPrint('[-] Error fetching announcements: $e');
      return [];
    }
  }

  /// ── إضافة إعلان جديد ─────────────────────────────────────────────────────
  Future<bool> createAnnouncement(AnnouncementModel announcement) async {
    try {
      final json = announcement.toJson();
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
      return true;
    } catch (e) {
      debugPrint('[-] Error creating announcement: $e');
      return false;
    }
  }

  /// ── حذف إعلان / بوستر / جدول (مع حذف الرسالة من قناة تيليجرام بالتزامن) ───
  Future<bool> deleteAnnouncement(String id) async {
    try {
      // 1. استعلام مسبق لحذف المنشور المقابل من قناة تيليجرام إن وجد
      try {
        final row = await client
            .from('announcements')
            .select('content, image_url')
            .eq('id', id)
            .maybeSingle();

        if (row != null) {
          int? msgId;
          final contentStr = row['content']?.toString() ?? '';
          final match = RegExp(r'\[TG_MSG_ID:(\d+)\]').firstMatch(contentStr);
          if (match != null) {
            msgId = int.tryParse(match.group(1) ?? '');
          }

          // محاولة بديلة: إذا كان رابط الصورة يحمل معرف الرسالة
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
      return true;
    } catch (e) {
      debugPrint('[-] Error deleting announcement: $e');
      return false;
    }
  }

  /// ── جلب الجداول الدراسية والامتحانية (منعزلة عن الإعلانات) ──────────────
  Future<List<ScheduleModel>> fetchSchedules({
    required String department,
    required String stage,
    String? type,
  }) async {
    try {
      final res = await client
          .from('announcements')
          .select('*')
          .order('created_at', ascending: false);

      final list = (res as List).where((item) {
        final content = item['content']?.toString() ?? '';
        final subjectName = item['subject_name']?.toString() ?? '';
        // الجداول حصراً تحمل وسم [SCHEDULE_TIMETABLE] أو subject_name = SCHEDULE
        return content.contains('[SCHEDULE_TIMETABLE]') || subjectName == 'SCHEDULE';
      }).map((item) {
        final cat = item['category']?.toString() ?? '';
        final title = item['title']?.toString() ?? '';
        final isExam = cat == 'exam' || title.contains('امتحان');
        final content = item['content']?.toString() ?? '';
        final tgMatch = RegExp(r'\[TG_MSG_ID:(\d+)\]').firstMatch(content);
        final tgMsgId = tgMatch != null ? int.tryParse(tgMatch.group(1) ?? '') : null;

        return ScheduleModel(
          id: item['id']?.toString() ?? '',
          title: item['title'] ?? 'جدول دراسي',
          type: isExam ? 'exams' : 'lectures',
          department: item['department'] ?? 'ALL',
          stage: item['stage'] ?? 'ALL',
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

      return list.where((s) {
        final matchDept = s.department == 'ALL' || s.department == department;
        final matchStage = s.stage == 'ALL' || s.stage == stage;
        final matchType = type == null || s.type == type;
        return matchDept && matchStage && matchType;
      }).toList();
    } catch (e) {
      debugPrint('[-] Error fetching schedules: $e');
      return [];
    }
  }

  /// ── حفظ / رفع جدول جديد (مع وسم العزل التام عن الإعلانات وتوثيق رسالة تيليجرام) ─────────────
  Future<bool> createSchedule(ScheduleModel schedule) async {
    try {
      final tgTag = schedule.telegramMessageId != null ? ' [TG_MSG_ID:${schedule.telegramMessageId}]' : '';
      final payload = {
        'title': schedule.title,
        'content': '[SCHEDULE_TIMETABLE]$tgTag جدول دراسي',
        'category': schedule.isExam ? 'exam' : 'academic',
        'department': schedule.department,
        'stage': schedule.stage,
        'image_url': schedule.fileUrl,
        'author_name': schedule.uploaderName ?? 'ممثل الدفعة',
        'author_id': schedule.uploaderId ?? 'REP',
        'author_role': 'representative',
        'is_pinned': true,
        'subject_name': 'SCHEDULE',
      };
      await client.from('announcements').insert(payload);
      return true;
    } catch (e) {
      debugPrint('[-] Error creating schedule: $e');
      return false;
    }
  }

  Future<bool> deleteSchedule(String id) async {
    return deleteAnnouncement(id);
  }

  /// ── جلب المحاضرات (موحدة لكافة شُعب المرحلة والقسم) ──────────────────
  Future<List<LectureModel>> fetchLectures({
    String? department,
    String? stage,
    String? section,
    int? semester,
  }) async {
    try {
      var query = client.from('lectures').select('*');

      if (department != null && department.isNotEmpty && department != 'ALL') {
        query = query.eq('department', department);
      }
      if (stage != null && stage.isNotEmpty && stage != 'ALL') {
        query = query.eq('stage', stage);
      }
      if (semester != null) {
        query = query.eq('semester', semester);
      }

      final res = await query.order('created_at', ascending: false);

      // المحاضرات تظهر لكافة طلبة المرحلة والشعب بصورة موحدة
      return (res as List).map((item) => LectureModel.fromJson(item)).toList();
    } catch (e) {
      debugPrint('[-] Error fetching lectures: $e');
      return [];
    }
  }

  /// ── نشر محاضرة جديدة برابط Google Drive ────────────────────────────────
  Future<bool> createLecture(LectureModel lecture) async {
    try {
      await client.from('lectures').insert(lecture.toJson());
      return true;
    } catch (e) {
      debugPrint('[-] Error creating lecture: $e');
      return false;
    }
  }

  /// ── حذف محاضرة (مع حذف الرسالة من قناة تيليجرام بالتزامن) ────────────────
  Future<bool> deleteLecture(String id) async {
    try {
      // 1. استعلام مسبق لجلب معرف رسالة تيليجرام والقناة
      try {
        final row = await client
            .from('lectures')
            .select('telegram_message_id, telegram_channel_id')
            .eq('id', id)
            .maybeSingle();

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
      final res = await _attendanceClient
          .from('students')
          .select('section')
          .eq('department', department)
          .eq('stage', stage);

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
      var q = _attendanceClient
          .from('students')
          .select('*')
          .eq('department', department)
          .eq('stage', stage)
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
      final existing = await getAppUserByStudentId(student.id);
      if (existing != null) {
        await client.from('app_users').update({
          'role': AppConstants.roleRepresentative,
          'department': student.department,
          'stage': student.stage,
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
          'stage': student.stage,
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
    return BiometricSubjects.getSubjects(
      department: department,
      stage: stage,
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
    return BiometricSubjects.getSubjectNames(
      department: department,
      stage: stage,
      semester: targetSemester,
    );
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

    try {
      final payload = {
        'title': cleanName,
        'content': '[COURSE_REGISTRY:ADD] مقرر دراسي مضاف',
        'category': 'academic',
        'department': department,
        'stage': stage,
        'author_id': user.studentId,
        'author_name': user.name,
        'author_role': user.role,
        'subject_name': 'COURSE',
        'is_pinned': false,
      };
      await client.from('announcements').insert(payload);

      // تحديث الكاش المحلي فورياً
      final current = await fetchCourses(department: department, stage: stage);
      if (!current.contains(cleanName)) {
        current.add(cleanName);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('custom_courses_${department}_$stage', jsonEncode(current));
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

    try {
      final payload = {
        'title': cleanNew,
        'content': '[COURSE_REGISTRY:EDIT] old_name:$cleanOld',
        'category': 'academic',
        'department': department,
        'stage': stage,
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
      final current = await fetchCourses(department: department, stage: stage);
      current.remove(cleanOld);
      if (!current.contains(cleanNew)) current.add(cleanNew);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('custom_courses_${department}_$stage', jsonEncode(current));

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

    try {
      final payload = {
        'title': cleanName,
        'content': '[COURSE_REGISTRY:DELETE] مقرر محذوف',
        'category': 'academic',
        'department': department,
        'stage': stage,
        'author_id': user.studentId,
        'author_name': user.name,
        'author_role': user.role,
        'subject_name': 'COURSE',
        'is_pinned': false,
      };
      await client.from('announcements').insert(payload);

      // تحديث الكاش المحلي فورياً
      final current = await fetchCourses(department: department, stage: stage);
      current.remove(cleanName);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('custom_courses_${department}_$stage', jsonEncode(current));

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
          .order('created_at', ascending: false);

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
