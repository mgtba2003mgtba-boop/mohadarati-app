import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_user_model.dart';
import 'supabase_service.dart';

/// نوع العملية غير المتصلة المحفوظة في طابور المزامنة
enum MutationType {
  addLectureComment,
  toggleCommentHelpful,
  toggleCommentPin,
  castPollVote,
  toggleReaction,
}

/// بند عملية مؤجلة في طابور المزامنة
class SyncMutation {
  final String id;
  final MutationType type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  int retryCount;

  SyncMutation({
    required this.id,
    required this.type,
    required this.payload,
    required this.createdAt,
    this.retryCount = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'payload': payload,
    'createdAt': createdAt.toIso8601String(),
    'retryCount': retryCount,
  };

  factory SyncMutation.fromJson(Map<String, dynamic> json) {
    return SyncMutation(
      id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      type: MutationType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => MutationType.addLectureComment,
      ),
      payload: Map<String, dynamic>.from(json['payload'] ?? {}),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt']) ?? DateTime.now()
          : DateTime.now(),
      retryCount: json['retryCount'] is int ? json['retryCount'] : 0,
    );
  }
}

/// ── محرك المزامنة غير المتصلة (Offline-First State Sync Engine) ───────────
/// مصمم خصيصاً لتحمل ظروف الإنترنت المتقطعة وحفظ عمليات الطلبة والممثلين
/// محلياً في ذاكرة التخزين الدائمة وإعادة إرسالها تلقائياً فور عودة الاتصال.
class OfflineSyncService with WidgetsBindingObserver {
  static final OfflineSyncService _instance = OfflineSyncService._internal();
  factory OfflineSyncService() => _instance;
  OfflineSyncService._internal();

  static const String _storageKey = 'offline_mutations_queue_v1';
  static const int _maxRetries = 5;

  final List<SyncMutation> _queue = [];
  bool _isSyncing = false;
  Timer? _autoSyncTimer;

  final ValueNotifier<int> pendingCountNotifier = ValueNotifier<int>(0);

  int get pendingCount => _queue.length;
  bool get hasPending => _queue.isNotEmpty;
  List<SyncMutation> get pendingMutations => List.unmodifiable(_queue);

  /// تهيئة المحرك واستعادة العمليات العالقة من التخزين الدائم
  Future<void> initialize() async {
    try {
      WidgetsBinding.instance.addObserver(this);
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _queue.clear();
          for (final item in decoded) {
            try {
              if (item is Map<String, dynamic>) {
                _queue.add(SyncMutation.fromJson(item));
              }
            } catch (_) {}
          }
          pendingCountNotifier.value = _queue.length;
        }
      }
    } catch (e) {
      debugPrint('[OfflineSyncService] Init error: $e');
    }

    // جدولة فحص دوري ذكي كل دقيقة ونصف في حال كان التطبيق مفتوحاً
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 90), (_) {
      if (hasPending && !_isSyncing) {
        syncPendingMutations();
      }
    });

    // محاولة مزامنة فورية فور الإقلاع إن وُجدت عمليات معلقة
    if (hasPending) {
      Future.delayed(const Duration(seconds: 3), () => syncPendingMutations());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && hasPending && !_isSyncing) {
      syncPendingMutations();
    }
  }

  /// إضافة عملية جديدة إلى الطابور وحفظها محلياً
  Future<void> enqueue({
    required MutationType type,
    required Map<String, dynamic> payload,
  }) async {
    final mutation = SyncMutation(
      id: '${DateTime.now().millisecondsSinceEpoch}_${_queue.length}',
      type: type,
      payload: payload,
      createdAt: DateTime.now(),
    );

    _queue.add(mutation);
    pendingCountNotifier.value = _queue.length;
    await _persistQueue();

    debugPrint('[OfflineSyncService] Enqueued mutation: ${type.name} (Total pending: ${_queue.length})');

    // محاولة إرسال فورية في الخلفية
    syncPendingMutations();
  }

  /// معالجة وتفريغ طابور العمليات المعلقة بالتتابع
  Future<void> syncPendingMutations() async {
    if (_isSyncing || _queue.isEmpty) return;
    _isSyncing = true;

    debugPrint('[OfflineSyncService] Starting sync for ${_queue.length} pending mutations...');
    final service = SupabaseService();
    final List<SyncMutation> toRemove = [];

    try {
      for (final mutation in List<SyncMutation>.from(_queue)) {
        bool success = false;

        try {
          switch (mutation.type) {
            case MutationType.addLectureComment:
              final user = service.currentUser;
              if (user != null) {
                final res = await service.addLectureComment(
                  lectureId: mutation.payload['lecture_id'] ?? '',
                  text: mutation.payload['text'] ?? '',
                  user: user,
                  department: mutation.payload['department'] ?? user.department,
                  stage: mutation.payload['stage'] ?? user.stage,
                  section: mutation.payload['section'],
                );
                success = res != null;
              } else {
                // لا يمكن إرسال التعليق دون جلسة مسجلة
                toRemove.add(mutation);
                continue;
              }
              break;

            case MutationType.toggleCommentHelpful:
              success = await service.toggleLectureCommentHelpful(
                commentId: mutation.payload['comment_id'] ?? '',
                lectureId: mutation.payload['lecture_id'] ?? '',
                studentId: mutation.payload['student_id'] ?? '',
              );
              break;

            case MutationType.toggleCommentPin:
              final user = service.currentUser;
              if (user != null && (user.isAdmin || user.isRepresentative)) {
                success = await service.toggleLectureCommentPin(
                  commentId: mutation.payload['comment_id'] ?? '',
                  lectureId: mutation.payload['lecture_id'] ?? '',
                  isPinned: mutation.payload['is_pinned'] == true,
                  user: user,
                );
              } else {
                toRemove.add(mutation);
                continue;
              }
              break;

            case MutationType.castPollVote:
              {
                final userMap = mutation.payload['user'] as Map<String, dynamic>?;
                final user = userMap != null
                    ? AppUserModel.fromJson(userMap)
                    : AppUserModel(
                        id: mutation.payload['user_id'] ?? mutation.payload['student_id'] ?? '',
                        studentId: mutation.payload['student_id'] ?? '',
                        name: mutation.payload['student_name'] ?? 'طالب',
                        department: mutation.payload['department'] ?? 'عام',
                        stage: mutation.payload['stage'] ?? 'المرحلة الأولى',
                      );
                final res = await service.castPollVote(
                  announcementId: mutation.payload['announcement_id'] ?? '',
                  optionIndex: mutation.payload['option_index'] ?? 0,
                  user: user,
                );
                success = res != null;
              }
              break;

            case MutationType.toggleReaction:
              {
                final userMap = mutation.payload['user'] as Map<String, dynamic>?;
                final user = userMap != null
                    ? AppUserModel.fromJson(userMap)
                    : AppUserModel(
                        id: mutation.payload['user_id'] ?? mutation.payload['student_id'] ?? '',
                        studentId: mutation.payload['student_id'] ?? '',
                        name: mutation.payload['student_name'] ?? 'طالب',
                        department: mutation.payload['department'] ?? 'عام',
                        stage: mutation.payload['stage'] ?? 'المرحلة الأولى',
                      );
                final res = await service.toggleAnnouncementReaction(
                  announcementId: mutation.payload['announcement_id'] ?? '',
                  emoji: mutation.payload['emoji'] ?? '❤️',
                  user: user,
                );
                success = res != null;
              }
              break;
          }
        } catch (e) {
          debugPrint('[OfflineSyncService] Error processing mutation ${mutation.id}: $e');
          mutation.retryCount++;
          if (mutation.retryCount >= _maxRetries) {
            debugPrint('[OfflineSyncService] Dropping mutation ${mutation.id} after $_maxRetries failed attempts.');
            toRemove.add(mutation);
          }
          // إذا كان الخطأ متعلقاً بالاتصال، نوقف المحاولة الآن وننتظر الجولة القادمة
          break;
        }

        if (success) {
          toRemove.add(mutation);
        } else {
          mutation.retryCount++;
          if (mutation.retryCount >= _maxRetries) {
            toRemove.add(mutation);
          }
        }
      }

      if (toRemove.isNotEmpty) {
        _queue.removeWhere((m) => toRemove.contains(m));
        pendingCountNotifier.value = _queue.length;
        await _persistQueue();
        debugPrint('[OfflineSyncService] Successfully synced ${toRemove.length} mutations. Remaining: ${_queue.length}');
      }
    } finally {
      _isSyncing = false;
    }
  }

  /// حفظ الحالة في SharedPreferences
  Future<void> _persistQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_queue.isEmpty) {
        await prefs.remove(_storageKey);
      } else {
        final list = _queue.map((m) => m.toJson()).toList();
        await prefs.setString(_storageKey, jsonEncode(list));
      }
    } catch (e) {
      debugPrint('[OfflineSyncService] Persist error: $e');
    }
  }

  /// تنظيف الطابور بالكامل (مثلاً عند تسجيل الخروج)
  Future<void> clearQueue() async {
    _queue.clear();
    pendingCountNotifier.value = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  void dispose() {
    _autoSyncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}
