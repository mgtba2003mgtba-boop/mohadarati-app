import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/app_theme.dart';
import '../models/app_user_model.dart';
import '../models/attendance_model.dart';
import '../services/supabase_service.dart';
import '../services/attendance_service.dart';
import 'subject_detail_screen.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  bool _isLoading = true;
  AppUserModel? _user;
  List<AttendanceRecordModel> _rawRecords = [];
  OverallAttendanceSummary? _summary;

  @override
  void initState() {
    super.initState();
    _loadAttendance();
  }

  Future<void> _loadAttendance() async {
    setState(() => _isLoading = true);
    final service = SupabaseService();
    _user = service.currentUser;

    if (_user != null) {
      _rawRecords = await service.fetchStudentAttendance(_user!.studentId);
      _summary = AttendanceService.processAttendanceRecords(_rawRecords);
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.lightBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'سجل ونسب الحضور والغياب',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 17, color: AppTheme.textPrimary),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary),
            onPressed: _loadAttendance,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : RefreshIndicator(
              onRefresh: _loadAttendance,
              color: AppTheme.primary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // بطاقة النسبة الكلية العامة
                    _buildOverallStatsCard(),
                    const SizedBox(height: 18),

                    // تنبيه الإنذارات الأكاديمية
                    _buildAcademicWarningAlert(),
                    const SizedBox(height: 18),

                    // تفاصيل الحضور لكل مادة دراسية
                    Text(
                      'نسب الحضور حسب المواد الدراسية',
                      style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),

                    if (_summary == null || _summary!.subjectsStats.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.lightBorder),
                          boxShadow: AppTheme.cardShadow,
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.history_toggle_off_rounded, size: 40, color: Color(0xFF94A3B8)),
                            const SizedBox(height: 10),
                            Text(
                              'لا توجد سجلات حضور مسجلة حتى الآن',
                              style: GoogleFonts.cairo(color: AppTheme.textSecondary, fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    else
                      ..._summary!.subjectsStats.map((item) => _buildSubjectCard(item)),

                    const SizedBox(height: 24),

                    // سجل المحاضرات الأخيرة المسجلة بالكاميرات
                    Text(
                      'آخر عمليات الحضور المسجلة (منظومة الوجوه)',
                      style: GoogleFonts.cairo(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),

                    if (_rawRecords.isEmpty)
                      Text(
                        'لا توجد سجلات بعد',
                        style: GoogleFonts.cairo(color: AppTheme.textMuted, fontSize: 12),
                      )
                    else
                      ..._rawRecords.take(10).map((record) => _buildRecordTile(record)),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildOverallStatsCard() {
    final pct = _summary?.overallPercentage ?? 100.0;
    final totalAttended = _summary?.totalPresences ?? 0;
    final totalAbsent = _summary?.totalEstimatedAbsences ?? 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.lightBorder),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'المعدل التراكمي للحضور الأكاديمي',
                    style: GoogleFonts.cairo(fontSize: 13, color: AppTheme.textSecondary),
                  ),
                  Text(
                    '${pct.toStringAsFixed(1)}%',
                    style: GoogleFonts.cairo(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: pct >= 85 ? AppTheme.success : pct >= 70 ? AppTheme.warning : AppTheme.danger,
                    ),
                  ),
                ],
              ),
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: (pct >= 85 ? AppTheme.success : pct >= 70 ? AppTheme.warning : AppTheme.danger)
                      .withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    pct >= 85 ? Icons.verified_rounded : Icons.warning_amber_rounded,
                    color: pct >= 85 ? AppTheme.success : pct >= 70 ? AppTheme.warning : AppTheme.danger,
                    size: 30,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatMetric('المحاضرات المسجلة', '$totalAttended', AppTheme.success),
              Container(width: 1, height: 26, color: AppTheme.lightBorder),
              _buildStatMetric('الغيابات المقدرة', '$totalAbsent', AppTheme.danger),
              Container(width: 1, height: 26, color: AppTheme.lightBorder),
              _buildStatMetric('المواد المشمولة', '${_summary?.subjectsStats.length ?? 0}', AppTheme.primary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatMetric(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textMuted)),
      ],
    );
  }

  Widget _buildAcademicWarningAlert() {
    final warnings = _summary?.subjectsStats
        .where((s) => s.warningLevel != AcademicWarningLevel.safe)
        .toList() ?? [];

    if (warnings.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.successSubtle,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline_rounded, color: AppTheme.success, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'وضعك الأكاديمي آمن تماماً! لا توجد أي إنذارات غياب.',
                style: GoogleFonts.cairo(color: AppTheme.success, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.dangerSubtle,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_rounded, color: AppTheme.danger, size: 22),
              const SizedBox(width: 8),
              Text(
                'تنبيه: يوجد (${warnings.length}) مواد اقتربت من حدود الإنذار الأكاديمي',
                style: GoogleFonts.cairo(color: AppTheme.danger, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'احرص على تثبيت حضورك عبر الكاميرات الذكية بالقاعة لتجنب عقوبات الغياب.',
            style: GoogleFonts.cairo(color: AppTheme.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectCard(SubjectAttendanceStats item) {
    Color statusColor = AppTheme.success;
    if (item.warningLevel == AcademicWarningLevel.dismissed || item.warningLevel == AcademicWarningLevel.finalWarning) {
      statusColor = AppTheme.danger;
    } else if (item.warningLevel == AcademicWarningLevel.firstWarning || item.warningLevel == AcademicWarningLevel.secondWarning) {
      statusColor = AppTheme.warning;
    }

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SubjectDetailScreen(
              subjectName: item.subjectName,
              attendanceStats: item,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.lightBorder),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    item.subjectName,
                    style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    item.warningLabel,
                    style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // شريط التقدم
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (item.attendancePercentage / 100.0).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: AppTheme.lightSurface,
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              ),
            ),
            const SizedBox(height: 8),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'حضور: ${item.attendedCount} محاضرة (${item.attendancePercentage.toStringAsFixed(0)}%)',
                  style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textMuted),
                ),
                Text(
                  'نسبة الغياب: ${item.absencePercentage.toStringAsFixed(1)}%',
                  style: GoogleFonts.cairo(fontSize: 11, color: statusColor, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordTile(AttendanceRecordModel record) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.lightBorder),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primarySubtle,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, color: AppTheme.primary, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.subjectName ?? 'محاضرة عامة',
                  style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                Text(
                  'التاريخ: ${record.date}',
                  style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'حاضر',
              style: GoogleFonts.cairo(fontSize: 10, color: AppTheme.success, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
