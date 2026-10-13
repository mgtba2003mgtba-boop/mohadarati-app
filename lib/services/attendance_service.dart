import '../models/attendance_model.dart';

class AttendanceService {
  /// تحليل ومعالجة سجلات الحضور الخام واستخراج النسب والإنذارات لكل مادة
  static OverallAttendanceSummary processAttendanceRecords(
    List<AttendanceRecordModel> records, {
    int standardSemesterSessions = 15,
  }) {
    if (records.isEmpty) {
      return OverallAttendanceSummary(
        totalPresences: 0,
        totalEstimatedAbsences: 0,
        overallPercentage: 0.0,
        subjectsStats: [],
      );
    }

    // 1. تجميع السجلات حسب اسم المادة
    final Map<String, int> subjectCounts = {};
    for (final rec in records) {
      final name = (rec.subjectName != null && rec.subjectName!.trim().isNotEmpty)
          ? rec.subjectName!.trim()
          : 'المحاضرات العامة';
      subjectCounts[name] = (subjectCounts[name] ?? 0) + 1;
    }

    // 2. حساب إحصائيات كل مادة
    final List<SubjectAttendanceStats> statsList = [];
    int totalPresences = 0;

    subjectCounts.forEach((subjName, count) {
      totalPresences += count;
      final stats = SubjectAttendanceStats.calculate(
        subjectName: subjName,
        attendedCount: count,
        standardSemesterSessions: standardSemesterSessions,
      );
      statsList.add(stats);
    });

    // ترتيب المواد: الأكثر خطورة في الغياب أولاً
    statsList.sort((a, b) => b.absencePercentage.compareTo(a.absencePercentage));

    // 3. الحساب الإجمالي
    final int estimatedTotalAllSubjects = subjectCounts.length * standardSemesterSessions;
    final int totalEstimatedAbsences = estimatedTotalAllSubjects > totalPresences
        ? (estimatedTotalAllSubjects - totalPresences)
        : 0;

    final double overallPct = estimatedTotalAllSubjects > 0
        ? ((totalPresences / estimatedTotalAllSubjects) * 100.0).clamp(0.0, 100.0)
        : 100.0;

    return OverallAttendanceSummary(
      totalPresences: totalPresences,
      totalEstimatedAbsences: totalEstimatedAbsences,
      overallPercentage: overallPct,
      subjectsStats: statsList,
    );
  }
}
