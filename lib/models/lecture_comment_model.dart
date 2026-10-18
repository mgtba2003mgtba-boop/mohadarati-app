import 'dart:convert';
import 'announcement_model.dart';
import '../core/constants/app_constants.dart';

class LectureCommentModel {
  final String id;
  final String lectureId;
  final String authorId;
  final String authorName;
  final String authorRole; // 'student', 'representative', 'admin'
  final String content;
  final bool isPinned;
  final List<String> helpfulUserIds;
  final DateTime createdAt;

  final String? section;

  const LectureCommentModel({
    required this.id,
    required this.lectureId,
    required this.authorId,
    required this.authorName,
    required this.authorRole,
    required this.content,
    this.isPinned = false,
    this.helpfulUserIds = const [],
    required this.createdAt,
    this.section,
  });

  bool get isRepresentative =>
      authorRole == AppConstants.roleRepresentative ||
      authorId == 'ST-NUST-001630760-413';

  bool get isAdmin =>
      authorRole == AppConstants.roleAdmin ||
      authorId == 'ST-NUST-001630760-413';

  int get helpfulCount => helpfulUserIds.length;

  bool isHelpfulBy(String? studentId) {
    if (studentId == null || studentId.isEmpty) return false;
    return helpfulUserIds.contains(studentId);
  }

  /// النص النظيف المعروض للمستخدم محصن ضد أي تسريب لرموز برمجية أو وسوم خام
  String get displayContent {
    String clean = content;
    // إن كان النص يحتوي على بنية JSON خام (مثل السجلات القديمة المشوهة)
    final jsonMatch = RegExp(r'\{[^{}]*\}').firstMatch(clean);
    if (jsonMatch != null) {
      try {
        final decoded = jsonDecode(jsonMatch.group(0)!);
        if (decoded is Map && decoded['text'] != null) {
          clean = decoded['text'].toString();
        }
      } catch (_) {
        final textMatch = RegExp(r'"text"\s*:\s*"([^"\\]*(?:\\.[^"\\]*)*)"').firstMatch(clean);
        if (textMatch != null) {
          clean = textMatch.group(1) ?? clean;
        }
      }
    }
    return clean
        .replaceAll(tag, '')
        .replaceAll(RegExp(r'\[SECTION:[^\]]+\]'), '')
        .replaceAll(RegExp(r'\[REACTIONS:[^\]]+\]'), '')
        .trim();
  }

  LectureCommentModel copyWith({
    String? content,
    bool? isPinned,
    List<String>? helpfulUserIds,
    String? section,
  }) {
    return LectureCommentModel(
      id: id,
      lectureId: lectureId,
      authorId: authorId,
      authorName: authorName,
      authorRole: authorRole,
      content: content ?? this.content,
      isPinned: isPinned ?? this.isPinned,
      helpfulUserIds: helpfulUserIds ?? this.helpfulUserIds,
      createdAt: createdAt,
      section: section ?? this.section,
    );
  }

  static const String tag = '[LECTURE_NOTE_V1]';

  /// ترميز التعليق لدمجه في محتوى الإعلان السحابي
  static String encodeContent({
    required String text,
    bool isPinned = false,
    List<String> helpfulUserIds = const [],
    String? section,
  }) {
    final payload = {
      'text': text.trim(),
      'is_pinned': isPinned,
      'helpful_users': helpfulUserIds,
      if (section != null && section.isNotEmpty) 'section': section,
    };
    return '$tag${jsonEncode(payload)}';
  }

  /// تحويل إعلان Supabase إلى نموذج تعليق أكاديمي محصن
  static LectureCommentModel? fromAnnouncement(AnnouncementModel a) {
    if (a.subjectName != 'LECTURE_NOTE' && !a.content.contains(tag)) return null;

    final raw = a.content;
    String text = '';
    bool pinned = false;
    List<String> helpful = [];
    String? extractedSection;

    // 1. استخراج وسم الشعبة [SECTION:X] إن وجد
    final secMatch = RegExp(r'\[SECTION:([^\]]+)\]').firstMatch(raw);
    if (secMatch != null) {
      extractedSection = secMatch.group(1)?.trim();
    }

    // 2. عزل كائن الـ JSON بأمان تام بمعزل عن الوسوم السابقة أو اللاحقة
    final jsonMatch = RegExp(r'\{[^{}]*\}').firstMatch(raw);
    if (jsonMatch != null) {
      try {
        final jsonStr = jsonMatch.group(0)!;
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        text = map['text']?.toString() ?? '';
        pinned = map['is_pinned'] == true;
        if (map['helpful_users'] is List) {
          helpful = (map['helpful_users'] as List)
              .map((e) => e.toString())
              .toList();
        }
        if (map['section'] != null && extractedSection == null) {
          extractedSection = map['section'].toString();
        }
      } catch (e) {
        // خطأ صامت في فك JSON، سنستخدم المستخرج البديل
      }
    }

    // 3. مسار استعادة وقائي منيع (Fallback): استخراج نص التعليق ومنع ظهور أي كود JSON خام
    if (text.isEmpty) {
      final textRegexMatch = RegExp(r'"text"\s*:\s*"([^"\\]*(?:\\.[^"\\]*)*)"').firstMatch(raw);
      if (textRegexMatch != null) {
        text = textRegexMatch.group(1) ?? '';
        text = text.replaceAll(r'\"', '"').replaceAll(r'\n', '\n');
      } else {
        // تجريد كامل من الوسوم وبنية الـ JSON
        text = raw
            .replaceAll(tag, '')
            .replaceAll(RegExp(r'\[SECTION:[^\]]+\]'), '')
            .replaceAll(RegExp(r'\[REACTIONS:[^\]]+\]'), '')
            .replaceAll(RegExp(r'\{[^{}]*\}'), '')
            .trim();
      }
    }

    // تنظيف نهائي لضمان خلو النص من أي وسوم داخلية
    text = text
        .replaceAll(tag, '')
        .replaceAll(RegExp(r'\[SECTION:[^\]]+\]'), '')
        .replaceAll(RegExp(r'\[REACTIONS:[^\]]+\]'), '')
        .trim();

    return LectureCommentModel(
      id: a.id,
      lectureId: a.title, // نستخدم title لحفظ معرف المحاضرة lectureId
      authorId: a.authorId,
      authorName: a.authorName,
      authorRole: a.authorRole,
      content: text,
      isPinned: pinned,
      helpfulUserIds: helpful,
      createdAt: a.createdAt,
      section: extractedSection ?? (a.section.isNotEmpty && a.section != 'ALL' ? a.section : null),
    );
  }
}
