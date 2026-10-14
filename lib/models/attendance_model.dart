import '../core/constants/app_constants.dart';

class AttendanceRecordModel {
  final String id;
  final String studentId;
  final String studentName;
  final String date;
  final String? subjectName;
  final DateTime? timestamp;

  AttendanceRecordModel({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.date,
    this.subjectName,
    this.timestamp,
  });

  factory AttendanceRecordModel.fromJson(Map<String, dynamic> json) {
    DateTime? ts;
    if (json['timestamp'] != null) {
      try {
        ts = DateTime.parse(json['timestamp'].toString());
      } catch (_) {}
    }

    return AttendanceRecordModel(
      id: json['id']?.toString() ?? '',
      studentId: json['student_id']?.toString() ?? '',
      studentName: json['student_name']?.toString() ?? '',
      date: json['date']?.toString() ?? '',
      subjectName: json['subject_name']?.toString(),
      timestamp: ts,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'student_id': studentId,
    'student_name': studentName,
    'date': date,
    'subject_name': subjectName,
    'timestamp': timestamp?.toIso8601String(),
  };
}

enum AcademicWarningLevel {
  safe,
  firstWarning,   // 5% - 7%
  secondWarning,  // 7% - 10%
  finalWarning,   // 10% - 15%
  dismissed,      // >= 15%
}

class SubjectAttendanceStats {
  final String subjectName;
  final int attendedCount;
  final int estimatedTotalSessions; // عادة ما يُقدر بـ 15 أسبوعاً لكل فصل
  final int absentCount;
  final double attendancePercentage;
  final double absencePercentage;
  final AcademicWarningLevel warningLevel;

  SubjectAttendanceStats({
    required this.subjectName,
    required this.attendedCount,
    required this.estimatedTotalSessions,
    required this.absentCount,
    required this.attendancePercentage,
    required this.absencePercentage,
    required this.warningLevel,
  });

  factory SubjectAttendanceStats.calculate({
    required String subjectName,
    required int attendedCount,
    int standardSemesterSessions = 15,
  }) {
    final total = standardSemesterSessions;
    final absents = total > attendedCount ? (total - attendedCount) : 0;
    final attPct = total > 0 ? (attendedCount / total) * 100.0 : 0.0;
    final absPct = total > 0 ? (absents / total) : 0.0;

    AcademicWarningLevel level = AcademicWarningLevel.safe;
    if (absPct >= AppConstants.failureThreshold) {
      level = AcademicWarningLevel.dismissed;
    } else if (absPct >= AppConstants.finalWarningThreshold) {
      level = AcademicWarningLevel.finalWarning;
    } else if (absPct >= AppConstants.secondWarningThreshold) {
      level = AcademicWarningLevel.secondWarning;
    } else if (absPct >= AppConstants.firstWarningThreshold) {
      level = AcademicWarningLevel.firstWarning;
    }

    return SubjectAttendanceStats(
      subjectName: subjectName,
      attendedCount: attendedCount,
      estimatedTotalSessions: total,
      absentCount: absents,
      attendancePercentage: attPct.clamp(0.0, 100.0),
      absencePercentage: (absPct * 100.0).clamp(0.0, 100.0),
      warningLevel: level,
    );
  }

  String get warningLabel {
    switch (warningLevel) {
      case AcademicWarningLevel.dismissed:
        return 'تجاوز نسبة الغياب (فصل)';
      case AcademicWarningLevel.finalWarning:
        return 'إنذار نهائي';
      case AcademicWarningLevel.secondWarning:
        return 'إنذار ثانٍ';
      case AcademicWarningLevel.firstWarning:
        return 'إنذار أولي';
      case AcademicWarningLevel.safe:
        return 'وضع نظامي';
    }
  }
}

class OverallAttendanceSummary {
  final int totalPresences;
  final int totalEstimatedAbsences;
  final double overallPercentage;
  final List<SubjectAttendanceStats> subjectsStats;

  OverallAttendanceSummary({
    required this.totalPresences,
    required this.totalEstimatedAbsences,
    required this.overallPercentage,
    required this.subjectsStats,
  });
}
