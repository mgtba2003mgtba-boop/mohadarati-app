import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../models/app_user_model.dart';
import '../models/announcement_model.dart';
import '../services/supabase_service.dart';
import '../widgets/app_fullscreen_modal.dart';
import '../widgets/telegram_announcement_card.dart';
import 'dashboard_screen.dart';

class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  bool _isLoading = true;
  List<AnnouncementModel> _announcements = [];
  String _selectedCategory = 'ALL';
  String _searchQuery = '';
  AppUserModel? _user;

  // ── فلاتر المشرف العام لمراقبة كافة الأقسام والمراحل والشُعب ─────────
  String _supervisorDept = 'ALL';
  String _supervisorStage = 'ALL';
  String _supervisorSection = 'ALL';

  @override
  void initState() {
    super.initState();
    _loadAnnouncements();
  }

  Future<void> _loadAnnouncements({bool forceRefresh = false}) async {
    setState(() => _isLoading = true);
    final service = SupabaseService();
    _user = service.currentUser;

    final isAdmin = _user?.isAdmin == true;
    final dept = isAdmin
        ? (_supervisorDept == 'ALL' ? null : _supervisorDept)
        : _user?.department;
    final stage = isAdmin
        ? (_supervisorStage == 'ALL' ? null : _supervisorStage)
        : _user?.stage;
    final section = isAdmin
        ? (_supervisorSection == 'ALL' ? null : _supervisorSection)
        : _user?.section;

    _announcements = await service.fetchAnnouncements(
      department: dept,
      stage: stage,
      section: section,
      forceRefresh: forceRefresh,
    );

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmDeleteAnnouncement(AnnouncementModel announcement) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 24),
            const SizedBox(width: 8),
            Text('حذف التبليغ', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(
          'هل أنت متأكد من حذف التبليغ "${announcement.title}"؟\nسيتم حذفه من قاعدة البيانات وتيليجرام فوراً.',
          style: GoogleFonts.cairo(fontSize: 13, color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('إلغاء', style: GoogleFonts.cairo(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('نعم، حذف نهائي', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final ok = await SupabaseService().deleteAnnouncement(announcement.id);
      if (mounted) {
        if (ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم حذف التبليغ بنجاح وتحديث اللوحة')),
          );
          _loadAnnouncements(forceRefresh: true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تعذر حذف التبليغ، يرجى المحاولة لاحقاً')),
          );
        }
      }
    }
  }

  List<AnnouncementModel> get _filteredList {
    return _announcements.where((a) {
      final matchesCategory = _selectedCategory == 'ALL' || a.category == _selectedCategory;
      final matchesSearch = _searchQuery.isEmpty ||
          a.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          a.content.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesCategory && matchesSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final canPublish = _user?.canManageAnnouncements == true;

    return Scaffold(
      backgroundColor: AppTheme.lightBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'لوحة الإعلانات والتبليغات',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary),
            onPressed: () => _loadAnnouncements(forceRefresh: true),
          ),
        ],
      ),
      floatingActionButton: canPublish
          ? FloatingActionButton.extended(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_comment_rounded),
              label: Text('نشر إعلان', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DashboardScreen(initialTabIndex: 1)),
                ).then((_) => _loadAnnouncements(forceRefresh: true));
              },
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : RefreshIndicator(
              onRefresh: () => _loadAnnouncements(forceRefresh: true),
              color: AppTheme.primary,
              child: Column(
                children: [
                  // شريط الرقابة والإشراف العام (خاص بالمشرف العام لمراقبة كافة الأقسام والشُعب)
                  if (_user?.isAdmin == true) _buildSupervisorBar(),

                  // شريط البحث
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    child: TextField(
                      style: GoogleFonts.cairo(color: AppTheme.textPrimary, fontSize: 13),
                      onChanged: (val) => setState(() => _searchQuery = val),
                      decoration: InputDecoration(
                        hintText: 'بحث في الإعلانات الأكاديمية...',
                        hintStyle: GoogleFonts.cairo(color: AppTheme.textMuted, fontSize: 13),
                        prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.primary),
                        filled: true,
                        fillColor: AppTheme.lightSurface,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, color: AppTheme.textMuted),
                                onPressed: () => setState(() => _searchQuery = ''),
                              )
                            : null,
                      ),
                    ),
                  ),

                  // شرائح التصنيفات (Filter Chips)
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Row(
                        children: [
                          _buildFilterChip('الكل', 'ALL'),
                          const SizedBox(width: 8),
                          _buildFilterChip('أكاديمي وتدريسي', 'academic'),
                          const SizedBox(width: 8),
                          _buildFilterChip('عاجل وهام', 'urgent'),
                          const SizedBox(width: 8),
                          _buildFilterChip('امتحانات', 'exam'),
                          const SizedBox(width: 8),
                          _buildFilterChip('نشاطات', 'activity'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // قائمة الإعلانات بنمط قنوات تيليجرام والتفاعلات الأكاديمية
                  Expanded(
                    child: _filteredList.isEmpty
                        ? Center(
                            child: Text(
                              'لا توجد إعلانات مطابقة',
                              style: GoogleFonts.cairo(color: AppTheme.textSecondary, fontSize: 13),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            itemCount: _filteredList.length,
                            itemBuilder: (context, index) {
                              final item = _filteredList[index];
                              return TelegramAnnouncementCard(
                                key: ValueKey('ann_${item.id}'),
                                announcement: item,
                                currentUser: _user,
                                onReactionToggled: (emoji) => _toggleReaction(item, emoji),
                                onDelete: () => _confirmDeleteAnnouncement(item),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _toggleReaction(AnnouncementModel item, String emoji) async {
    if (_user == null) return;

    // 1. تحديث فوري وسريع للواجهة (Optimistic UI)
    final currentKey = _user!.studentId.isNotEmpty ? _user!.studentId : _user!.id;
    final reactionsMap = Map<String, AnnouncementReaction>.from(item.reactions);

    if (reactionsMap.containsKey(currentKey) && reactionsMap[currentKey]!.reaction == emoji) {
      reactionsMap.remove(currentKey);
    } else {
      reactionsMap[currentKey] = AnnouncementReaction(
        studentId: currentKey,
        studentName: _user!.name,
        department: _user!.department,
        stage: _user!.stage,
        section: _user!.section ?? '',
        reaction: emoji,
        createdAt: DateTime.now(),
      );
    }

    final updated = item.copyWithReactions(reactionsMap);
    setState(() {
      final idx = _announcements.indexWhere((a) => a.id == item.id);
      if (idx != -1) {
        _announcements[idx] = updated;
      }
    });

    // 2. مزامنة سحابية هادئة في الخلفية
    final synced = await SupabaseService().toggleAnnouncementReaction(
      announcementId: item.id,
      emoji: emoji,
      user: _user!,
    );
    if (synced != null && mounted) {
      setState(() {
        final idx = _announcements.indexWhere((a) => a.id == item.id);
        if (idx != -1) {
          _announcements[idx] = synced;
        }
      });
    }
  }

  Widget _buildFilterChip(String label, String categoryKey) {
    final isSelected = _selectedCategory == categoryKey;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) setState(() => _selectedCategory = categoryKey);
      },
      selectedColor: AppTheme.primary,
      backgroundColor: Colors.white,
      labelStyle: GoogleFonts.cairo(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        color: isSelected ? Colors.white : AppTheme.textSecondary,
      ),
      side: BorderSide(
        color: isSelected ? AppTheme.primary : AppTheme.lightBorder,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                          'وضع المراقبة والإشراف العام',
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
                      'مراقبة منشورات وتبليغات كافة الأقسام والمراحل والشُعب',
                      style: GoogleFonts.cairo(color: Colors.white70, fontSize: 10),
                    ),
                  ],
                ),
              ),
              if (_supervisorDept != 'ALL' || _supervisorStage != 'ALL' || _supervisorSection != 'ALL')
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _supervisorDept = 'ALL';
                      _supervisorStage = 'ALL';
                      _supervisorSection = 'ALL';
                    });
                    _loadAnnouncements();
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
              // اختيار القسم
              Expanded(
                flex: 4,
                child: _buildSupervisorDropdown(
                  label: 'القسم',
                  value: _supervisorDept,
                  items: [
                    const DropdownMenuItem(value: 'ALL', child: Text('كافة الأقسام 🌐', overflow: TextOverflow.ellipsis)),
                    ...AppConstants.departments.map((d) => DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _supervisorDept = val);
                      _loadAnnouncements();
                    }
                  },
                ),
              ),
              const SizedBox(width: 6),
              // اختيار المرحلة
              Expanded(
                flex: 3,
                child: _buildSupervisorDropdown(
                  label: 'المرحلة',
                  value: _supervisorStage,
                  items: [
                    const DropdownMenuItem(value: 'ALL', child: Text('كل المراحل', overflow: TextOverflow.ellipsis)),
                    ...AppConstants.stages.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _supervisorStage = val);
                      _loadAnnouncements();
                    }
                  },
                ),
              ),
              const SizedBox(width: 6),
              // اختيار الشعبة
              Expanded(
                flex: 3,
                child: _buildSupervisorDropdown(
                  label: 'الشعبة',
                  value: _supervisorSection,
                  items: const [
                    DropdownMenuItem(value: 'ALL', child: Text('كل الشُعب', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'A', child: Text('شعبة A')),
                    DropdownMenuItem(value: 'B', child: Text('شعبة B')),
                    DropdownMenuItem(value: 'C', child: Text('شعبة C')),
                    DropdownMenuItem(value: 'D', child: Text('شعبة D')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _supervisorSection = val);
                      _loadAnnouncements();
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
