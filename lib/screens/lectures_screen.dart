import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../models/app_user_model.dart';
import '../models/lecture_model.dart';
import '../services/supabase_service.dart';
import '../services/telegram_uploader_service.dart';
import '../widgets/app_media_preview_modal.dart';
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
  String _selectedSection = 'ALL';
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
      _selectedDept = _user!.isAdmin ? 'ALL' : _user!.department;
      _selectedStage = _user!.isAdmin ? 'ALL' : _user!.stage;
      _selectedSection = _user!.isAdmin ? 'ALL' : (_user!.section ?? 'ALL');
    }

    _loadLectures();
  }

  Future<void> _loadLectures({bool forceRefresh = false}) async {
    setState(() => _isLoading = true);

    final service = SupabaseService();
    final list = await service.fetchLectures(
      department: _selectedDept == 'ALL' ? null : _selectedDept,
      stage: _selectedStage == 'ALL' ? null : _selectedStage,
      section: (_user?.isAdmin == true && _selectedSection != 'ALL')
          ? _selectedSection
          : (_user?.isAdmin == true ? null : _user?.section),
      semester: _selectedSemester,
      forceRefresh: forceRefresh,
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
          l.section.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesType && matchesSearch;
    }).toList();
  }

  /// فتح أو بث المحاضرة مباشرة عبر مشغل الفيديو أو السحابة
  Future<void> _openMediaStream(dynamic target) async {
    String? url;
    if (target is LectureModel) {
      if (target.telegramFileId != null && target.telegramFileId!.isNotEmpty) {
        final fresh = await TelegramUploaderService().resolveFileUrl(target.telegramFileId!);
        if (fresh != null && fresh.isNotEmpty) url = fresh;
      }
      if (url == null || url.isEmpty) {
        if (target.driveUrl.startsWith('http')) {
          url = target.driveUrl;
        } else {
          url = target.streamUrl;
        }
      }
    } else if (target is String) {
      url = target;
    }

    if (url == null || url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('رابط البث أو الملف غير متوفر')),
        );
      }
      return;
    }

    if (!mounted) return;
    AppMediaPreviewModal.show(
      context: context,
      title: target is LectureModel ? target.title : 'معاينة المحاضرة',
      subtitle: target is LectureModel ? '${target.subjectName} • ${target.typeLabel}' : null,
      url: url,
      downloadUrl: target is LectureModel ? target.downloadUrl : null,
      fileName: target is LectureModel ? (target.fileName ?? target.title) : null,
      mimeType: target is LectureModel ? target.mimeType : null,
    );
  }

  /// تحميل المحاضرة مباشرة من سحابة تيليجرام
  Future<void> _openMediaDownload(dynamic target) async {
    String? url;
    if (target is LectureModel) {
      url = target.downloadUrl;
      if (target.telegramFileId != null && target.telegramFileId!.isNotEmpty) {
        final fresh = await TelegramUploaderService().resolveFileUrl(target.telegramFileId!);
        if (fresh != null && fresh.isNotEmpty) url = fresh;
      }
      if (url == null || url.isEmpty) {
        if (target.hasDriveUrl) url = target.cleanDriveViewUrl;
      }
    } else if (target is String) {
      url = target;
    }

    if (url == null || url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('رابط التحميل غير متوفر')),
        );
      }
      return;
    }

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
          // شريط الرقابة والإشراف العام (خاص بالمشرف العام لمراقبة كافة الأقسام والشُعب)
          if (_user?.isAdmin == true) _buildSupervisorBar(),

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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.bookmark_added_rounded, color: AppTheme.primaryLight, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'الفصل الأول (الكورس 1) 📘',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryLight,
                        ),
                      ),
                    ],
                  ),
                ),
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
          // الرأس: نوع المحاضرة وتاريخ الإضافة
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
                '${lecture.createdAt.year}/${lecture.createdAt.month.toString().padLeft(2, '0')}/${lecture.createdAt.day.toString().padLeft(2, '0')}',
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

          // اسم المادة
          Text(
            'المادة: ${lecture.subjectName}',
            style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFF94A3B8)),
          ),

          if (lecture.displayDescription.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              lecture.displayDescription,
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
                // زر المعاينة المباشرة
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D9488),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.visibility_rounded, size: 18, color: Colors.white),
                    label: Text(
                      'معاينة المحاضرة',
                      style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    onPressed: () => _openMediaStream(lecture),
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
                    onPressed: () => _openMediaDownload(lecture),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSupervisorBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.admin_panel_settings_rounded, color: Color(0xFFF59E0B), size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'مراقبة المحاضرات والمقررات (إشراف عام)',
                          style: GoogleFonts.cairo(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFFF59E0B), width: 0.6),
                          ),
                          child: Text(
                            'المشرف العام',
                            style: GoogleFonts.cairo(color: const Color(0xFFFBBF24), fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'استعراض المحاضرات والمقررات المرفوعة لكافة الأقسام والمراحل والشُعب',
                      style: GoogleFonts.cairo(color: Colors.white70, fontSize: 10),
                    ),
                  ],
                ),
              ),
              if (_selectedDept != 'ALL' || _selectedStage != 'ALL' || _selectedSection != 'ALL')
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedDept = 'ALL';
                      _selectedStage = 'ALL';
                      _selectedSection = 'ALL';
                    });
                    _loadLectures();
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.restart_alt_rounded, size: 14, color: Color(0xFFFBBF24)),
                  label: Text(
                    'عرض الكل',
                    style: GoogleFonts.cairo(color: const Color(0xFFFBBF24), fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 4,
                child: _buildSupervisorDropdown(
                  label: 'القسم',
                  value: _selectedDept,
                  items: [
                    const DropdownMenuItem(value: 'ALL', child: Text('كافة الأقسام 🌐', overflow: TextOverflow.ellipsis)),
                    ...AppConstants.departments.map((d) => DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedDept = val);
                      _loadLectures();
                    }
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 3,
                child: _buildSupervisorDropdown(
                  label: 'المرحلة',
                  value: _selectedStage,
                  items: [
                    const DropdownMenuItem(value: 'ALL', child: Text('كل المراحل', overflow: TextOverflow.ellipsis)),
                    ...AppConstants.stages.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedStage = val);
                      _loadLectures();
                    }
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 3,
                child: _buildSupervisorDropdown(
                  label: 'الشعبة',
                  value: _selectedSection,
                  items: const [
                    DropdownMenuItem(value: 'ALL', child: Text('كل الشُعب', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'A', child: Text('شعبة A')),
                    DropdownMenuItem(value: 'B', child: Text('شعبة B')),
                    DropdownMenuItem(value: 'C', child: Text('شعبة C')),
                    DropdownMenuItem(value: 'D', child: Text('شعبة D')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedSection = val);
                      _loadLectures();
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSupervisorDropdown({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: const Color(0xFF1E293B),
          icon: const Icon(Icons.arrow_drop_down_rounded, color: Colors.white70, size: 18),
          style: GoogleFonts.cairo(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
