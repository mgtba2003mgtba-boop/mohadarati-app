import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/theme/app_theme.dart';
import '../models/announcement_model.dart';
import '../models/lecture_model.dart';
import 'supabase_service.dart';
import 'web_notification_helper.dart';

enum AppNotificationType { announcement, lecture, update }

class AppNotificationItem {
  final String id;
  final String title;
  final String message;
  final AppNotificationType type;
  final String? targetId;
  final DateTime timestamp;

  AppNotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    this.targetId,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// ── خدمة الإشعارات والتنبيهات المباشرة للآيفون والأندرويد ────────────────
/// ترصد المنشورات والمحاضرات الجديدة فور نشرها في السحابة عبر Supabase Realtime،
/// وتُصدر إشعارات نظام حقيقية على الهاتف وبانرات تفاعلية داخل التطبيق،
/// مع محرك استدراك ذكي (Delta Catch-Up Engine) عند فتح التطبيق أو عودته للواجهة.
class AppNotificationService with WidgetsBindingObserver {
  static final AppNotificationService instance = AppNotificationService._internal();
  factory AppNotificationService() => instance;
  AppNotificationService._internal();

  final _notificationController = StreamController<AppNotificationItem>.broadcast();
  Stream<AppNotificationItem> get notificationStream => _notificationController.stream;

  final _announcementInsertController = StreamController<AnnouncementModel>.broadcast();
  Stream<AnnouncementModel> get announcementInsertStream => _announcementInsertController.stream;

  final _announcementUpdateController = StreamController<AnnouncementModel>.broadcast();
  Stream<AnnouncementModel> get announcementUpdateStream => _announcementUpdateController.stream;

  final _lectureInsertController = StreamController<LectureModel>.broadcast();
  Stream<LectureModel> get lectureInsertStream => _lectureInsertController.stream;

  RealtimeChannel? _realtimeChannel;
  bool _isSubscribed = false;
  Timer? _heartbeatTimer;
  bool _isCheckingDelta = false;

  /// إظهار إشعار عائم أعلى الشاشة يدوياً (للتحديثات أو التنبيهات الفورية)
  void showInAppNotification(AppNotificationItem item) {
    _notificationController.add(item);
  }

  /// تهيئة الاتصال المباشر بالقناة السحابية ومراقبة دورة حياة التطبيق
  void initialize() {
    if (_isSubscribed) return;
    _isSubscribed = true;

    WidgetsBinding.instance.addObserver(this);

    try {
      final client = Supabase.instance.client;
      _realtimeChannel = client.channel('nust_global_notifications');

      // الاستماع للتبليغات الجديدة
      _realtimeChannel!.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'announcements',
        callback: (payload) {
          _handleNewAnnouncement(payload.newRecord);
        },
      );

      // الاستماع لتحديثات التبليغات والتفاعلات اللحظية
      _realtimeChannel!.onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'announcements',
        callback: (payload) {
          _handleUpdatedAnnouncement(payload.newRecord);
        },
      );

      // الاستماع للمحاضرات الجديدة
      _realtimeChannel!.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'lectures',
        callback: (payload) {
          _handleNewLecture(payload.newRecord);
        },
      );

      _realtimeChannel!.subscribe();
      debugPrint('[+] AppNotificationService: Subscribed to live announcements & lectures');

      // فحص الاستدراك الفوري بعد اكتمال تهيئة الإطار (First Frame)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        checkMissedNotifications();
      });

      // مؤقت نبضي خفيف كل 75 ثانية كضمان إضافي في ظروف الشبكة المتذبذبة
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 75), (_) {
        checkMissedNotifications();
      });
    } catch (e) {
      debugPrint('[-] AppNotificationService initialization error: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // عند فتح الهاتف أو العودة للتطبيق: فحص هل نُشرت تبليغات أو محاضرات أثناء إغلاق التطبيق
      checkMissedNotifications();
    }
  }

  /// محرك استدراك الأحداث المتأخرة (Delta Catch-Up Engine)
  /// يضمن وصول الإشعارات للطالب حتى لو كان هاتفه مقفولاً أو التطبيق مغلقاً عند النشر
  Future<void> checkMissedNotifications() async {
    if (_isCheckingDelta) return;
    _isCheckingDelta = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastAnnId = prefs.getString('last_notified_ann_id');
      final lastLecId = prefs.getString('last_notified_lec_id');

      final client = Supabase.instance.client;

      // 1. استعلام أحدث التبليغات
      final annRes = await client
          .from('announcements')
          .select()
          .order('created_at', ascending: false)
          .limit(3);

      if (annRes is List && annRes.isNotEmpty) {
        final latestAnn = annRes.first as Map<String, dynamic>;
        final latestId = latestAnn['id']?.toString() ?? '';

        if (lastAnnId == null) {
          // أول تشغيل للتطبيق: حفظ المعرف كعلامة مرجعية دون إزعاج الطالب بتنبيهات قديمة
          await prefs.setString('last_notified_ann_id', latestId);
        } else if (latestId.isNotEmpty && latestId != lastAnnId) {
          // وُجد تبليغ جديد لم يُشعَر به الطالب بعد!
          await prefs.setString('last_notified_ann_id', latestId);
          _handleNewAnnouncement(latestAnn);
        }
      }

      // 2. استعلام أحدث المحاضرات
      final lecRes = await client
          .from('lectures')
          .select()
          .order('created_at', ascending: false)
          .limit(3);

      if (lecRes is List && lecRes.isNotEmpty) {
        final latestLec = lecRes.first as Map<String, dynamic>;
        final latestId = latestLec['id']?.toString() ?? '';

        if (lastLecId == null) {
          await prefs.setString('last_notified_lec_id', latestId);
        } else if (latestId.isNotEmpty && latestId != lastLecId) {
          await prefs.setString('last_notified_lec_id', latestId);
          _handleNewLecture(latestLec);
        }
      }
    } catch (e) {
      debugPrint('[-] Delta catch-up error: $e');
    } finally {
      _isCheckingDelta = false;
    }
  }

  void _handleNewAnnouncement(Map<String, dynamic> record) {
    try {
      final subjectName = record['subject_name']?.toString() ?? '';
      final content = record['content']?.toString()?.trim() ?? '';
      final isInternal = subjectName == 'LECTURE_NOTE' ||
          content.contains('[LECTURE_NOTE_V1]') ||
          subjectName == 'SCHEDULE' ||
          content.contains('[SCHEDULE_TIMETABLE]') ||
          subjectName == 'COURSE' ||
          content.contains('[COURSE_REGISTRY') ||
          subjectName == 'COURSE_OVERRIDE' ||
          content.contains('[COURSE_OVERRIDE');
      if (isInternal) return;

      final rawTitle = record['title']?.toString()?.trim() ?? '';
      // عنوان ذكي أنيق للإشعار في حال كان البوستر مصوراً بدون نصوص
      final title = rawTitle.isNotEmpty ? rawTitle : '📌 إعلان وتبليغ رسمي جديد';
      final id = record['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();

      try {
        final ann = AnnouncementModel.fromJson(record);
        SupabaseService().invalidateCachePattern('announcements_');
        _announcementInsertController.add(ann);
      } catch (_) {}

      final notif = AppNotificationItem(
        id: id,
        title: '📢 تبليغ رسمي جديد',
        message: title,
        type: AppNotificationType.announcement,
        targetId: id,
      );

      _notificationController.add(notif);

      // تحديث المعرف المرجعي في الذاكرة
      SharedPreferences.getInstance().then((p) => p.setString('last_notified_ann_id', id));

      // إشعار نظام حقيقي على الجهاز (آيفون وأندرويد)
      final bodyText = content.isNotEmpty ? content : 'تم نشر إعلان رسمي مصور في المنظومة الأكاديمية.';
      showWebNotification(
        title: '📢 $title',
        body: bodyText,
        tag: 'ann_$id',
      );
    } catch (e) {
      debugPrint('[-] Error handling new announcement: $e');
    }
  }

  void _handleUpdatedAnnouncement(Map<String, dynamic> record) {
    try {
      final subjectName = record['subject_name']?.toString() ?? '';
      final content = record['content']?.toString() ?? '';
      final isInternal = subjectName == 'LECTURE_NOTE' ||
          content.contains('[LECTURE_NOTE_V1]') ||
          subjectName == 'SCHEDULE' ||
          content.contains('[SCHEDULE_TIMETABLE]') ||
          subjectName == 'COURSE' ||
          content.contains('[COURSE_REGISTRY') ||
          subjectName == 'COURSE_OVERRIDE' ||
          content.contains('[COURSE_OVERRIDE');
      if (isInternal) return;

      final ann = AnnouncementModel.fromJson(record);
      SupabaseService().invalidateCachePattern('announcements_');
      _announcementUpdateController.add(ann);
    } catch (e) {
      debugPrint('[-] Error handling updated announcement/reactions: $e');
    }
  }

  void _handleNewLecture(Map<String, dynamic> record) {
    try {
      final title = record['title']?.toString()?.trim() ?? 'محاضرة دراسية جديدة';
      final subjectName = record['subject_name']?.toString()?.trim() ?? '';
      final id = record['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();

      try {
        final lec = LectureModel.fromJson(record);
        SupabaseService().invalidateCachePattern('lectures_');
        _lectureInsertController.add(lec);
      } catch (_) {}

      final notif = AppNotificationItem(
        id: id,
        title: subjectName.isNotEmpty ? '📚 مادة: $subjectName' : '📚 محاضرة جديدة',
        message: title,
        type: AppNotificationType.lecture,
        targetId: id,
      );

      _notificationController.add(notif);

      // تحديث المعرف المرجعي في الذاكرة
      SharedPreferences.getInstance().then((p) => p.setString('last_notified_lec_id', id));

      // إشعار نظام حقيقي على الجهاز (آيفون وأندرويد)
      showWebNotification(
        title: subjectName.isNotEmpty ? '📚 محاضرة: $subjectName' : '📚 محاضرة دراسية جديدة',
        body: 'تم رفع محاضرة جديدة: $title',
        tag: 'lec_$id',
      );
    } catch (e) {
      debugPrint('[-] Error handling new lecture: $e');
    }
  }

  /// طلب صلاحية الإشعارات وتفعيلها فورياً
  /// يتم استدعاء دالة النظام فوراً لحفظ رمز نقرة المستخدم (User Activation Token) على iOS WebKit
  Future<bool> requestPermission() async {
    // 1. إطلاق طلب صلاحية النظام فوراً دون أي await مسبق
    final requestFuture = requestWebNotificationPermission();

    // 2. تحديث التفضيلات في الخلفية
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notifications_prompted', true);
    } catch (_) {}

    final granted = await requestFuture;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notifications_enabled', granted);
    } catch (_) {}

    return granted;
  }

  /// فحص هل الإشعارات مفعلة وممنوحة على الجهاز
  Future<bool> areNotificationsEnabled() async {
    final deviceEnabled = await areDeviceNotificationsEnabled();
    final prefs = await SharedPreferences.getInstance();
    final prefEnabled = prefs.getBool('notifications_enabled') ?? true;
    return deviceEnabled && prefEnabled;
  }

  /// عرض نافذة الترحيب بطلب تفعيل الإشعارات إذا لم يسبق طلبها
  Future<void> promptPermissionIfNeeded(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alreadyPrompted = prefs.getBool('notifications_prompted') ?? false;
      if (alreadyPrompted) return;

      if (!context.mounted) return;

      await showModalBottomSheet(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppTheme.primary, AppTheme.primaryLight],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withValues(alpha: 0.35),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.notifications_active_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'تفعيل الإشعارات الفورية',
                    style: GoogleFonts.cairo(
                      fontSize: 16.5,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'لتصلك التبليغات الجامعية الرسمية والمحاضرات الجديدة فور نشرها مباشرة على هاتفك (آيفون وأندرويد).',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.cairo(
                      fontSize: 12.5,
                      color: AppTheme.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            final p = await SharedPreferences.getInstance();
                            await p.setBool('notifications_prompted', true);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF64748B),
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text('لاحقاً', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            final success = await requestPermission();
                            if (success && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'تم تفعيل الإشعارات الفورية بنجاح! 🔔',
                                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                                  ),
                                  backgroundColor: const Color(0xFF059669),
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: Text('تفعيل الإشعارات', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      debugPrint('[-] Error prompting notifications permission: $e');
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _realtimeChannel?.unsubscribe();
    _notificationController.close();
    _announcementInsertController.close();
    _announcementUpdateController.close();
    _lectureInsertController.close();
  }
}
