import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';
import '../models/app_user_model.dart';
import '../models/course_override_model.dart';
import 'supabase_service.dart';

/// خدمة التخصيص والمزامنة السحابية للمقررات الدراسية
/// تتيح إخفاء المواد وتعديل أسمائها ورموزها مع الحفاظ التام على سلامة العلاقات مع المحاضرات القديمة
/// وتدعم الفصلين الدراسيين الأول والثاني باستقلالية تامة
class CourseCustomizationService extends ChangeNotifier {
  static final CourseCustomizationService _instance = CourseCustomizationService._internal();
  factory CourseCustomizationService() => _instance;
  CourseCustomizationService._internal();

  final Map<String, Map<String, CourseOverrideModel>> _cache = {};

  static String buildCacheKey({
    required String department,
    required String stage,
    required int semester,
  }) {
    final normStage = AppConstants.normalizeStage(stage);
    return 'course_overrides_${department}_${normStage}_S$semester';
  }

  String _cacheKey(String department, String stage, int semester) {
    return buildCacheKey(department: department, stage: stage, semester: semester);
  }

  /// جلب كافة التخصيصات لقسم ومرحلة وفصل دراسي معين
  Future<Map<String, CourseOverrideModel>> getOverrides({
    required String department,
    required String stage,
    int semester = 1,
    bool forceRefresh = false,
  }) async {
    final key = _cacheKey(department, stage, semester);

    // 1. فحص ذاكرة الوصول السريع RAM
    if (!forceRefresh && _cache.containsKey(key)) {
      return Map.unmodifiable(_cache[key]!);
    }

    final Map<String, CourseOverrideModel> localMap = {};

    // 2. فحص التخزين المحلي الدائم SharedPreferences (0ms)
    try {
      final prefs = await SharedPreferences.getInstance();
      final localJson = prefs.getString(key);
      if (localJson != null && localJson.isNotEmpty) {
        final List<dynamic> list = jsonDecode(localJson);
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            final model = CourseOverrideModel.fromJson(item);
            if (model.originalName.isNotEmpty && model.semester == semester) {
              localMap[model.originalName] = model;
            }
          }
        }
        _cache[key] = localMap;
      }
    } catch (e) {
      debugPrint('[-] Error reading local course overrides: $e');
    }

    // 3. المزامنة من خادم Supabase
    try {
      final supabase = SupabaseService();
      final normStage = AppConstants.normalizeStage(stage);

      final response = await supabase.client
          .from('announcements')
          .select('*')
          .eq('subject_name', 'COURSE_OVERRIDE')
          .eq('department', department)
          .eq('stage', normStage);

      final Map<String, CourseOverrideModel> cloudMap = {};
      for (final row in (response as List<dynamic>)) {
        final content = row['content']?.toString() ?? '';
        final model = CourseOverrideModel.fromAnnouncementContent(content);
        if (model != null && model.originalName.isNotEmpty && model.semester == semester) {
          cloudMap[model.originalName] = model;
        }
      }

      // دمج التخصيصات وحفظها في الكاش
      _cache[key] = cloudMap;
      await _persistToLocal(key, cloudMap.values.toList());
      notifyListeners();
      return Map.unmodifiable(cloudMap);
    } catch (e) {
      debugPrint('[-] Error syncing course overrides from Supabase: $e');
    }

    return Map.unmodifiable(localMap);
  }

  /// فحص مباشر إذا كان المقرر لديه تخصيص مسجل في هذا الفصل
  CourseOverrideModel? getOverrideFor(
    String originalName, {
    required String department,
    required String stage,
    int semester = 1,
  }) {
    final key = _cacheKey(department, stage, semester);
    return _cache[key]?[originalName];
  }

  /// حفظ أو تحديث تخصيص مقرر (تغيير الاسم أو الرمز أو حالة الإخفاء)
  Future<bool> saveOverride(
    CourseOverrideModel override, {
    required AppUserModel user,
  }) async {
    final key = _cacheKey(override.department, override.stage, override.semester);
    final normStage = AppConstants.normalizeStage(override.stage);

    // 1. التحديث الفوري في الذاكرة والكاش المحلي
    _cache.putIfAbsent(key, () => {})[override.originalName] = override;
    await _persistToLocal(key, _cache[key]!.values.toList());
    notifyListeners();

    // 2. المزامنة مع سحابة Supabase
    try {
      final supabase = SupabaseService();

      // حذف أي سجلات تخصيص قديمة للمادة نفسها في هذا القسم والمرحلة والفصل
      try {
        final existing = await supabase.client
            .from('announcements')
            .select('id, content')
            .eq('subject_name', 'COURSE_OVERRIDE')
            .eq('department', override.department)
            .eq('stage', normStage);

        for (final row in (existing as List<dynamic>)) {
          final content = row['content']?.toString() ?? '';
          final oldModel = CourseOverrideModel.fromAnnouncementContent(content);
          if (oldModel != null &&
              oldModel.originalName == override.originalName &&
              oldModel.semester == override.semester) {
            await supabase.client.from('announcements').delete().eq('id', row['id']);
          }
        }
      } catch (_) {}

      // إدراج سجل التخصيص الجديد
      final jsonPayload = jsonEncode(override.toJson());
      final payload = {
        'title': override.displayName,
        'content': '[COURSE_OVERRIDE_V1]$jsonPayload',
        'category': 'academic',
        'department': override.department,
        'stage': normStage,
        'author_id': user.studentId,
        'author_name': user.name,
        'author_role': user.role,
        'subject_name': 'COURSE_OVERRIDE',
        'is_pinned': false,
      };

      await supabase.client.from('announcements').insert(payload);
      return true;
    } catch (e) {
      debugPrint('[-] Error saving course override to Supabase: $e');
      return false;
    }
  }

  /// استعادة الحالة الافتراضية للمقرر (حذف التخصيص والاسم المخصص وإلغاء الإخفاء)
  Future<bool> resetOverride({
    required String originalName,
    required String department,
    required String stage,
    int semester = 1,
    required AppUserModel user,
  }) async {
    final key = _cacheKey(department, stage, semester);
    final normStage = AppConstants.normalizeStage(stage);

    if (_cache.containsKey(key)) {
      _cache[key]!.remove(originalName);
      await _persistToLocal(key, _cache[key]!.values.toList());
      notifyListeners();
    }

    try {
      final supabase = SupabaseService();
      final existing = await supabase.client
          .from('announcements')
          .select('id, content')
          .eq('subject_name', 'COURSE_OVERRIDE')
          .eq('department', department)
          .eq('stage', normStage);

      for (final row in (existing as List<dynamic>)) {
        final content = row['content']?.toString() ?? '';
        final model = CourseOverrideModel.fromAnnouncementContent(content);
        if (model != null && model.originalName == originalName && model.semester == semester) {
          await supabase.client.from('announcements').delete().eq('id', row['id']);
        }
      }
      return true;
    } catch (e) {
      debugPrint('[-] Error resetting course override: $e');
      return false;
    }
  }

  /// تبديل سريع لحالة إخفاء المقرر عن الطلاب
  Future<bool> toggleHideCourse({
    required String originalName,
    required bool isHidden,
    required String department,
    required String stage,
    int semester = 1,
    required AppUserModel user,
    String? currentCustomName,
    String? currentCustomCode,
  }) async {
    final existing = getOverrideFor(originalName, department: department, stage: stage, semester: semester);
    final updated = (existing != null)
        ? existing.copyWith(
            isHidden: isHidden,
            displayName: currentCustomName ?? existing.displayName,
            customCode: currentCustomCode ?? existing.customCode,
            semester: semester,
            updatedAt: DateTime.now(),
            updatedBy: user.name,
          )
        : CourseOverrideModel(
            originalName: originalName,
            displayName: currentCustomName ?? originalName,
            customCode: currentCustomCode,
            isHidden: isHidden,
            department: department,
            stage: stage,
            semester: semester,
            updatedAt: DateTime.now(),
            updatedBy: user.name,
          );

    return await saveOverride(updated, user: user);
  }

  Future<void> _persistToLocal(String key, List<CourseOverrideModel> models) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = models.map((m) => m.toJson()).toList();
      await prefs.setString(key, jsonEncode(list));
    } catch (e) {
      debugPrint('[-] Error persisting course overrides locally: $e');
    }
  }
}
