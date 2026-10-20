/// نموذج بيانات سجل نشاطات ممثلي الشعب والمشرفين
class RepresentativeActivityItem {
  final String id;
  final String type; // 'lecture' | 'announcement'
  final String title;
  final String subjectName;
  final String department;
  final String stage;
  final String? section;
  final String actorName;
  final String actorId;
  final String actorRole;
  final DateTime createdAt;
  final String? driveUrl;
  final String? streamUrl;
  final String? content;

  RepresentativeActivityItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subjectName,
    required this.department,
    required this.stage,
    this.section,
    required this.actorName,
    required this.actorId,
    required this.actorRole,
    required this.createdAt,
    this.driveUrl,
    this.streamUrl,
    this.content,
  });
}
