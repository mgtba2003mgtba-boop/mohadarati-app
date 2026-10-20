import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/theme/app_theme.dart';
import '../models/announcement_model.dart';
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
/// وتُصدر إشعارات نظام حقيقية على الهاتف وبانرات داخل التطبيق.
class AppNotificationService {
  static final AppNotificationService instance = AppNotificationService._internal();
  factory AppNotificationService() => instance;
  AppNotificationService._internal();

  final _notificationController = StreamController<AppNotificationItem>.broadcast();
  Stream<AppNotificationItem> get notificationStream => _notificationController.stream;

  final _announcementInsertController = StreamController<AnnouncementModel>.broadcast();
  Stream<AnnouncementModel> get announcementInsertStream => _announcementInsertController.stream;

  final _announcementUpdateController = StreamController<AnnouncementModel>.broadcast();
  Stream<AnnouncementModel> get announcementUpdateStream => _announcementUpdateController.stream;

  RealtimeChannel? _realtimeChannel;
  bool _isSubscribed = false;

  /// إظهار إشعار عائم أعلى الشاشة يدوياً (للتحديثات أو التنبيهات الفورية)
  void showInAppNotification(AppNotificationItem item) {
    _notificationController.add(item);
  }

  /// تهيئة الاتصال المباشر بالقناة السحابية
  void initialize() {
    if (_isSubscribed) return;
    _isSubscribed = true;

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
    } catch (e) {
      debugPrint('[-] AppNotificationService initialization error: $e');
    }
  }

  void _handleNewAnnouncement(Map<String, dynamic> record) {
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

      final title = record['title']?.toString() ?? 'إعلان جديد';
      final id = record['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();

      try {
        final ann = AnnouncementModel.fromJson(record);
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

      // إشعار نظام حقيقي على الجهاز (آيفون وأندرويد)
      showWebNotification(
        title: '📢 تبليغ جديد: $title',
        body: content.isNotEmpty ? content : 'تم نشر تبليغ رسمي جديد في المنظومة الأكاديمية.',
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
      _announcementUpdateController.add(ann);
    } catch (e) {
      debugPrint('[-] Error handling updated announcement/reactions: $e');
    }
  }

  void _handleNewLecture(Map<String, dynamic> record) {
    try {
      final title = record['title']?.toString() ?? 'محاضرة جديدة';
      final subjectName = record['subject_name']?.toString() ?? '';
      final id = record['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();

      final notif = AppNotificationItem(
        id: id,
        title: subjectName.isNotEmpty ? '📚 محاضرة: $subjectName' : '📚 محاضرة جديدة',
        message: title,
        type: AppNotificationType.lecture,
        targetId: id,
      );

      _notificationController.add(notif);

      // إشعار نظام حقيقي على الجهاز (آيفون وأندرويد)
      showWebNotification(
        title: '📚 محاضرة جديدة: $title',
        body: subjectName.isNotEmpty
            ? 'تم رفع محاضرة جديدة لمادة $subjectName'
            : 'تم رفع محاضرة دراسية جديدة في المنظومة.',
        tag: 'lec_$id',
      );
    } catch (e) {
      debugPrint('[-] Error handling new lecture: $e');
    }
  }

  /// طلب صلاحية الإشعارات وتفعيلها
  Future<bool> requestPermission() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_prompted', true);

    bool granted = true;
    if (kIsWeb) {
      granted = await requestWebNotificationPermission();
    }

    await prefs.setBool('notifications_enabled', granted);
    return granted;
  }

  /// فحص هل الإشعارات مفعلة
  Future<bool> areNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('notifications_enabled') ?? true;
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
    _realtimeChannel?.unsubscribe();
    _notificationController.close();
    _announcementInsertController.close();
    _announcementUpdateController.close();
  }
}
