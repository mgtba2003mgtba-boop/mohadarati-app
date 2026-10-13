import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme/app_theme.dart';
import '../models/app_user_model.dart';
import '../models/lecture_model.dart';
import '../services/supabase_service.dart';
import 'dashboard_screen.dart';

class LecturesScreen extends StatefulWidget {
  const LecturesScreen({super.key});

  @override
  State<LecturesScreen> createState() => _LecturesScreenState();
}

class _LecturesScreenState extends State<LecturesScreen> {
  bool _isLoading = true;
  List<LectureModel> _lectures = [];
  AppUserModel? _user;

  String _selectedDept = 'ALL';
  String _selectedStage = 'ALL';
  int _selectedSemester = 1;
  String _selectedType = 'ALL'; // 'ALL', 'theory', 'practical'
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _initFiltersAndLoad();
  }

  void _initFiltersAndLoad() {
    final service = SupabaseService();
    _user = service.currentUser;

    if (_user != null) {
      _selectedDept = _user!.department;
      _selectedStage = _user!.stage;
    }

    _loadLectures();
  }

  Future<void> _loadLectures() async {
    setState(() => _isLoading = true);

    final service = SupabaseService();
    final list = await service.fetchLectures(
      department: _selectedDept == 'ALL' ? null : _selectedDept,
      stage: _selectedStage == 'ALL' ? null : _selectedStage,
      semester: _selectedSemester,
    );

    if (mounted) {
      setState(() {
        _lectures = list;
        _isLoading = false;
      });
    }
  }

  List<LectureModel> get _filteredLectures {
    return _lectures.where((l) {
      final matchesType = _selectedType == 'ALL' || l.type == _selectedType;
      final matchesSearch = _searchQuery.isEmpty ||
          l.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          l.subjectName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (l.professorName != null && l.professorName!.toLowerCase().contains(_searchQuery.toLowerCase()));
      return matchesType && matchesSearch;
    }).toList();
  }

  /// فتح رابط المحاضرة المباشر على Google Drive
  Future<void> _openGoogleDrive(String url) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return;

    final uri = Uri.parse(cleanUrl);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح الرابط. يمكنك نسخه يدوياً.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في الرابط: $e')),
        );
      }
    }
  }

  /// نسخ رابط Google Drive
  void _copyDriveLink(String url) {
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم نسخ رابط Google Drive إلى الحافظة بنجاح'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// فتح أو بث المحاضرة مباشرة عبر مشغل الفيديو
  Future<void> _openMediaStream(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.parse(url);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح مشغل الفيديو للبث المباشر')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في البث: $e')),
        );
      }
    }
  }

  /// تحميل المحاضرة مباشرة من سيرفر تيليجرام
  Future<void> _openMediaDownload(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.parse(url);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر بدء التحميل')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في التحميل: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPublish = _user?.canManageLectures == true;

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        title: const Text('المحاضرات والمقررات الدراسية'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadLectures,
          ),
        ],
      ),
      floatingActionButton: canPublish
          ? FloatingActionButton.extended(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.upload_file_rounded),
              label: Text('نشر محاضرة Drive', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DashboardScreen(initialTabIndex: 0)),
                ).then((_) => _loadLectures());
              },
            )
          : null,
      body: Column(
        children: [
          // شريط البحث
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: TextField(
              style: GoogleFonts.cairo(color: Colors.white),
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'ابحث باسم المحاضرة، المادة، أو الأستاذ...',
                prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.primaryLight),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, color: Color(0xFF64748B)),
                        onPressed: () => setState(() => _searchQuery = ''),
                      )
                    : null,
              ),
            ),
          ),

          // محدد الفصل الدراسي والنوع (الكورس الأول / الثاني - نظري / عملي)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: Row(
              children: [
                _buildSemesterToggle(1, 'الفصل الأول (الكورس 1)'),
                const SizedBox(width: 8),
                _buildSemesterToggle(2, 'الفصل الثاني (الكورس 2)'),
                const SizedBox(width: 14),
                Container(width: 1, height: 24, color: AppTheme.darkBorder),
                const SizedBox(width: 14),
                _buildTypeChip('الكل', 'ALL'),
                const SizedBox(width: 6),
                _buildTypeChip('نظري', 'theory'),
                const SizedBox(width: 6),
                _buildTypeChip('عملي', 'practical'),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // قائمة المحاضرات
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryLight))
                : _filteredLectures.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.folder_open_rounded, size: 54, color: Color(0xFF475569)),
                            const SizedBox(height: 12),
                            Text(
                              'لا توجد محاضرات منشورة لهذا الفصل حالياً',
                              style: GoogleFonts.cairo(color: const Color(0xFF94A3B8), fontSize: 13),
                            ),
                            if (canPublish) ...[
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const DashboardScreen(initialTabIndex: 0)),
                                  ).then((_) => _loadLectures());
                                },
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('كن أول من ينشر محاضرة'),
                              ),
                            ],
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadLectures,
                        color: AppTheme.primaryLight,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                          itemCount: _filteredLectures.length,
                          itemBuilder: (context, index) {
                            return _buildLectureCard(_filteredLectures[index]);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSemesterToggle(int semester, String label) {
    final isSelected = _selectedSemester == semester;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _selectedSemester = semester);
          _loadLectures();
        }
      },
      selectedColor: AppTheme.primary,
      backgroundColor: AppTheme.darkCard,
      labelStyle: GoogleFonts.cairo(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        color: isSelected ? Colors.white : const Color(0xFF94A3B8),
      ),
      side: BorderSide(color: isSelected ? AppTheme.primary : AppTheme.darkBorder),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _buildTypeChip(String label, String typeKey) {
    final isSelected = _selectedType == typeKey;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) setState(() => _selectedType = typeKey);
      },
      selectedColor: AppTheme.accent,
      backgroundColor: AppTheme.darkCard,
      labelStyle: GoogleFonts.cairo(
        fontSize: 11,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        color: isSelected ? Colors.black : const Color(0xFF94A3B8),
      ),
      side: BorderSide(color: isSelected ? AppTheme.accent : AppTheme.darkBorder),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  Widget _buildLectureCard(LectureModel lecture) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // الرأس: اسم المادة ونوعها (نظري/عملي)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: lecture.isPractical
                      ? AppTheme.accent.withValues(alpha: 0.15)
                      : AppTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  lecture.typeLabel,
                  style: GoogleFonts.cairo(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: lecture.isPractical ? AppTheme.accent : AppTheme.primaryLight,
                  ),
                ),
              ),
              Text(
                '${lecture.createdAt.year}/${lecture.createdAt.month}/${lecture.createdAt.day}',
                style: GoogleFonts.cairo(fontSize: 10, color: const Color(0xFF64748B)),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // عنوان المحاضرة
          Text(
            lecture.title,
            style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 2),

          // اسم المادة والأستاذ
          Text(
            'المادة: ${lecture.subjectName} ${lecture.professorName != null ? '• أ. ${lecture.professorName}' : ''}',
            style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFF94A3B8)),
          ),

          if (lecture.description != null && lecture.description!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              lecture.description!,
              style: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFFCBD5E1), height: 1.4),
            ),
          ],
          const SizedBox(height: 12),

          // إذا كانت المحاضرة متوفرة عبر سيرفر تيليجرام
          if (lecture.hasTelegramMedia) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF0D9488).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bolt_rounded, size: 16, color: Color(0xFF2DD4BF)),
                  const SizedBox(width: 6),
                  Text(
                    'متوفرة عبر سيرفر التيليجرام السريع (CDN)',
                    style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF2DD4BF)),
                  ),
                  const Spacer(),
                  if (lecture.formattedFileSize.isNotEmpty)
                    Text(
                      lecture.formattedFileSize,
                      style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                // زر البث المباشر للفيديو
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D9488),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.play_circle_fill_rounded, size: 18, color: Colors.white),
                    label: Text(
                      'تشغيل مباشر (Stream)',
                      style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    onPressed: () => _openMediaStream(lecture.streamUrl),
                  ),
                ),
                const SizedBox(width: 8),
                // زر التحميل المباشر
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF0D9488)),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 18, color: Color(0xFF2DD4BF)),
                    label: Text(
                      'تحميل المحاضرة',
                      style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2DD4BF)),
                    ),
                    onPressed: () => _openMediaDownload(lecture.downloadUrl),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),

          // معلومات الناشر وزر التحميل من Google Drive إن توفر
          Row(
            children: [
              Expanded(
                child: Text(
                  'نُشرت بواسطة: ${lecture.uploaderName} (${lecture.uploaderRole == 'representative' ? 'ممثل الدفعة' : 'الأستاذ'})',
                  style: GoogleFonts.cairo(fontSize: 10, color: const Color(0xFF64748B)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (lecture.driveUrl.isNotEmpty) ...[
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 18, color: Color(0xFF94A3B8)),
                  tooltip: 'نسخ رابط Drive',
                  onPressed: () => _copyDriveLink(lecture.driveUrl),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A8A),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.add_to_drive_rounded, size: 16, color: Colors.white),
                  label: Text(
                    'فتح Google Drive',
                    style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => _openGoogleDrive(lecture.driveUrl),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
