class AnnouncementModel {
  final String id;
  final String title;
  final String content;
  final String authorId;
  final String authorName;
  final String authorRole;
  final String department;
  final String stage;
  final String category;
  final bool isPinned;
  final String? imageUrl;
  final String? subjectName;
  final DateTime createdAt;

  AnnouncementModel({
    required this.id,
    required this.title,
    required this.content,
    required this.authorId,
    required this.authorName,
    required this.authorRole,
    this.department = 'ALL',
    this.stage = 'ALL',
    this.category = 'academic',
    this.isPinned = false,
    this.imageUrl,
    this.subjectName,
    required this.createdAt,
  });

  factory AnnouncementModel.fromJson(Map<String, dynamic> json) {
    DateTime created = DateTime.now();
    if (json['created_at'] != null) {
      try {
        created = DateTime.parse(json['created_at'].toString());
      } catch (_) {}
    }

    return AnnouncementModel(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      authorId: json['author_id']?.toString() ?? '',
      authorName: json['author_name']?.toString() ?? 'إدارة الكلية',
      authorRole: json['author_role']?.toString() ?? 'admin',
      department: json['department']?.toString() ?? 'ALL',
      stage: json['stage']?.toString() ?? 'ALL',
      category: json['category']?.toString() ?? 'academic',
      isPinned: json['is_pinned'] == true,
      imageUrl: json['image_url']?.toString(),
      subjectName: json['subject_name']?.toString(),
      createdAt: created,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'content': content,
      'author_id': authorId,
      'author_name': authorName,
      'author_role': authorRole,
      'department': department,
      'stage': stage,
      'category': category,
      'is_pinned': isPinned,
      'image_url': imageUrl,
      'subject_name': subjectName,
    };
  }
}
