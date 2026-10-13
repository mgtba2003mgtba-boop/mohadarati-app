import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../models/app_user_model.dart';
import '../models/announcement_model.dart';
import '../services/supabase_service.dart';
import '../widgets/app_fullscreen_modal.dart';
import '../widgets/app_icon_badge.dart';
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

  @override
  void initState() {
    super.initState();
    _loadAnnouncements();
  }

  Future<void> _loadAnnouncements() async {
    setState(() => _isLoading = true);
    final service = SupabaseService();
    _user = service.currentUser;

    _announcements = await service.fetchAnnouncements(
      department: _user?.department,
      stage: _user?.stage,
    );

    if (mounted) {
      setState(() => _isLoading = false);
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
            onPressed: _loadAnnouncements,
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
                ).then((_) => _loadAnnouncements());
              },
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : RefreshIndicator(
              onRefresh: _loadAnnouncements,
              color: AppTheme.primary,
              child: Column(
                children: [
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

                  // قائمة الإعلانات
                  Expanded(
                    child: _filteredList.isEmpty
                        ? Center(
                            child: Text(
                              'لا توجد إعلانات مطابقة',
                              style: GoogleFonts.cairo(color: AppTheme.textSecondary, fontSize: 13),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                            itemCount: _filteredList.length,
                            itemBuilder: (context, index) {
                              return _buildAnnouncementCard(_filteredList[index]);
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
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

  Widget _buildAnnouncementCard(AnnouncementModel announcement) {
    Color categoryColor = AppTheme.primary;
    if (announcement.category == 'urgent') categoryColor = AppTheme.danger;
    if (announcement.category == 'exam') categoryColor = AppTheme.warning;

    return InkWell(
      onTap: () => _showAnnouncementDetails(announcement),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: announcement.isPinned ? AppTheme.primary.withValues(alpha: 0.6) : AppTheme.lightBorder,
            width: announcement.isPinned ? 1.5 : 1.0,
          ),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: categoryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    AppConstants.announcementCategories[announcement.category] ?? 'إعلان',
                    style: GoogleFonts.cairo(fontSize: 10, color: categoryColor, fontWeight: FontWeight.bold),
                  ),
                ),
                const Spacer(),
                Text(
                  '${announcement.createdAt.year}/${announcement.createdAt.month.toString().padLeft(2, '0')}/${announcement.createdAt.day.toString().padLeft(2, '0')}',
                  style: GoogleFonts.cairo(fontSize: 10, color: AppTheme.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 10),

            Text(
              announcement.title,
              style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 6),

            Text(
              announcement.content,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 12),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person_pin_rounded, size: 16, color: AppTheme.textMuted),
                    const SizedBox(width: 4),
                    Text(
                      announcement.authorName,
                      style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
                Text(
                  'معاينة',
                  style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAnnouncementDetails(AnnouncementModel announcement) {
    AppFullscreenModal.show(
      context: context,
      title: announcement.title,
      subtitle: 'الناشر: ${announcement.authorName} • ${announcement.createdAt.year}/${announcement.createdAt.month.toString().padLeft(2, '0')}/${announcement.createdAt.day.toString().padLeft(2, '0')}',
      icon: Icons.campaign_rounded,
      imageUrl: announcement.imageUrl,
      contentText: announcement.content,
      accentColor: AppTheme.primary,
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text('إغلاق', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
