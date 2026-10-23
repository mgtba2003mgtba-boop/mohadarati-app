import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';
import '../models/lecture_model.dart';

/// خدمة تحسين تجربة الطالب الذكية (شارات المحاضرات الجديدة + حالة الحفظ بدون إنترنت)
class LectureUxService extends ChangeNotifier {
  static final LectureUxService instance = LectureUxService._internal();
  factory LectureUxService() => instance;
  LectureUxService._internal();

  static const String _seenSubjectsKey = 'ux_seen_subjects_v1';
  static const String _cachedLecturesKey = 'ux_offline_lectures_v1';
  static const String _seenLecturesIdsKey = 'ux_seen_lecture_ids_v1';

  final Map<String, DateTime> _subjectLastSeen = {};
  final Set<String> _offlineCachedIds = {};
  final Set<String> _openedLectureIds = {};
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();

      final rawSeen = prefs.getString(_seenSubjectsKey);
      if (rawSeen != null && rawSeen.isNotEmpty) {
        final decoded = jsonDecode(rawSeen) as Map<String, dynamic>;
        decoded.forEach((key, val) {
          final dt = DateTime.tryParse(val.toString());
          if (dt != null) {
            _subjectLastSeen[key] = dt;
          }
        });
      }

      final cachedList = prefs.getStringList(_cachedLecturesKey);
      if (cachedList != null) {
        _offlineCachedIds.addAll(cachedList);
      }

      final openedList = prefs.getStringList(_seenLecturesIdsKey);
      if (openedList != null) {
        _openedLectureIds.addAll(openedList);
      }

      notifyListeners();
    } catch (e) {
      debugPrint('[-] LectureUxService init error: $e');
    }
  }

  String _normalizeKey(String subjectName) {
    return AppConstants.normalizeArabic(subjectName.trim().toLowerCase());
  }

  /// التحقق مما إذا كانت المحاضرة محفوظة وجاهزة للفتح السريع/بدون إنترنت
  bool isLectureCached(String lectureId) {
    if (lectureId.isEmpty) return false;
    return _offlineCachedIds.contains(lectureId);
  }

  /// تعليم المحاضرة كمحفوظة بدون إنترنت بعد فتحها أو تنزيلها
  Future<void> markLectureCached(String lectureId) async {
    final clean = lectureId.trim();
    if (clean.isEmpty) return;
    final changed = _offlineCachedIds.add(clean);
    final openedChanged = _openedLectureIds.add(clean);
    if (changed || openedChanged) {
      notifyListeners();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(_cachedLecturesKey, _offlineCachedIds.toList());
        await prefs.setStringList(_seenLecturesIdsKey, _openedLectureIds.toList());
      } catch (_) {}
    }
  }

  /// التحقق مما إذا كانت المحاضرة جديدة (مرفوعة خلال آخر 72 ساعة ولم يفتحها الطالب بعد)
  bool isLectureNew(LectureModel lecture) {
    if (lecture.id.isEmpty) return false;
    if (_openedLectureIds.contains(lecture.id)) return false;

    final age = DateTime.now().difference(lecture.createdAt);
    if (age > const Duration(hours: 72)) return false;

    return true;
  }

  /// حساب عدد المحاضرات الجديدة غير المقروءة لمادة معينة
  int getUnreadLecturesCount(
    String subjectName,
    List<LectureModel> allLectures, {
    String? displayName,
  }) {
    final key = _normalizeKey(subjectName);
    final lastSeen = _subjectLastSeen[key];
    final cutoff = DateTime.now().subtract(const Duration(hours: 72));

    int count = 0;
    for (final lec in allLectures) {
      if (!AppConstants.matchesSubject(lec.subjectName, subjectName, displayName: displayName)) {
        continue;
      }
      if (_openedLectureIds.contains(lec.id)) continue;

      if (lastSeen != null) {
        if (lec.createdAt.isAfter(lastSeen)) {
          count++;
        }
      } else {
        if (lec.createdAt.isAfter(cutoff)) {
          count++;
        }
      }
    }
    return count;
  }

  /// حساب إجمالي المحاضرات الجديدة عبر جميع المواد
  int getTotalUnreadLecturesCount(List<LectureModel> allLectures) {
    final cutoff = DateTime.now().subtract(const Duration(hours: 72));
    int total = 0;
    for (final lec in allLectures) {
      if (_openedLectureIds.contains(lec.id)) continue;
      final key = _normalizeKey(lec.subjectName);
      final lastSeen = _subjectLastSeen[key];
      if (lastSeen != null) {
        if (lec.createdAt.isAfter(lastSeen)) total++;
      } else {
        if (lec.createdAt.isAfter(cutoff)) total++;
      }
    }
    return total;
  }

  /// تسجيل فتح الطالب لصفحة المادة لإخفاء شارة "جديد" عن بطاقة المادة
  Future<void> markSubjectSeen(String subjectName, {String? displayName}) async {
    final now = DateTime.now();
    final key = _normalizeKey(subjectName);
    _subjectLastSeen[key] = now;
    if (displayName != null && displayName.trim().isNotEmpty) {
      _subjectLastSeen[_normalizeKey(displayName)] = now;
    }
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = _subjectLastSeen.map((k, v) => MapEntry(k, v.toIso8601String()));
      await prefs.setString(_seenSubjectsKey, jsonEncode(encoded));
    } catch (_) {}
  }
}
