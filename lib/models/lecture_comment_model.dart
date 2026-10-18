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

  LectureCommentModel copyWith({
    String? content,
    bool? isPinned,
    List<String>? helpfulUserIds,
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
    );
  }

  static const String tag = '[LECTURE_NOTE_V1]';

  /// ترميز التعليق لدمجه في محتوى الإعلان السحابي
  static String encodeContent({
    required String text,
    bool isPinned = false,
    List<String> helpfulUserIds = const [],
  }) {
    final payload = {
      'text': text.trim(),
      'is_pinned': isPinned,
      'helpful_users': helpfulUserIds,
    };
    return '$tag${jsonEncode(payload)}';
  }

  /// تحويل إعلان Supabase إلى نموذج تعليق أكاديمي
  static LectureCommentModel? fromAnnouncement(AnnouncementModel a) {
    if (a.subjectName != 'LECTURE_NOTE') return null;

    final raw = a.content;
    String text = raw;
    bool pinned = false;
    List<String> helpful = [];

    if (raw.startsWith(tag)) {
      try {
        final jsonStr = raw.substring(tag.length);
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        text = map['text']?.toString() ?? '';
        pinned = map['is_pinned'] == true;
        if (map['helpful_users'] is List) {
          helpful = (map['helpful_users'] as List)
              .map((e) => e.toString())
              .toList();
        }
      } catch (_) {
        text = raw.replaceAll(tag, '').trim();
      }
    }

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
    );
  }
}
