import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../models/app_user_model.dart';
import '../models/announcement_model.dart';
import '../services/app_notification_service.dart';
import '../services/supabase_service.dart';
import '../widgets/app_fullscreen_modal.dart';
import '../widgets/telegram_announcement_card.dart';
import '../widgets/telegram_poll_card.dart';
import '../widgets/create_poll_sheet.dart';
import 'package:file_picker/file_picker.dart';
import '../services/telegram_uploader_service.dart';
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

  StreamSubscription<AnnouncementModel>? _announcementInsertSub;
  StreamSubscription<AnnouncementModel>? _announcementUpdateSub;

  @override
  void initState() {
    super.initState();
    SupabaseService().announcementsNotifier.addListener(_onFreshAnnouncementsReceived);
    _loadAnnouncements(showSpinner: true);

    // ── الاستماع اللحظي لتحديث التفاعلات عبر WebSocket لجميع المستخدمين ──
    _announcementUpdateSub = AppNotificationService().announcementUpdateStream.listen((updated) {
      if (!mounted) return;
      setState(() {
        final idx = _announcements.indexWhere((a) => a.id == updated.id);
        if (idx != -1) {
          _announcements[idx] = updated;
        }
      });
    });

    // ── الاستماع اللحظي لإضافة تبليغات جديدة دون إعادة تحميل الصفحة ──
    _announcementInsertSub = AppNotificationService().announcementInsertStream.listen((inserted) {
      if (!mounted) return;
      final isAdmin = _user?.isAdmin == true;
      final myDept = _user?.department ?? '';
      final myStage = _user?.stage ?? '';
      final mySection = _user?.section ?? 'ALL';

      final matchesDept = isAdmin ||
          inserted.department == 'ALL' ||
          inserted.department == myDept;
      final matchesStage = isAdmin ||
          inserted.stage == 'ALL' ||
          AppConstants.normalizeStage(inserted.stage) == AppConstants.normalizeStage(myStage);
      final matchesSection = isAdmin ||
          inserted.section == 'ALL' ||
          inserted.section.isEmpty ||
          (_user != null && _user!.hasSectionAccess(inserted.section));

      if (matchesDept && matchesStage && matchesSection) {
        setState(() {
          if (!_announcements.any((a) => a.id == inserted.id)) {
            _announcements.insert(0, inserted);
          }
        });
      }
    });
  }

  void _onFreshAnnouncementsReceived() {
    final fresh = SupabaseService().announcementsNotifier.value;
    if (fresh != null && mounted) {
      setState(() {
        _announcements = fresh.where((a) {
          final isHomeBannerOnly = (a.category == 'banner' || a.subjectName == 'BANNER' || a.content.contains('[HOME_BANNER]')) &&
              (a.content.replaceAll(RegExp(r'\[.*?\]'), '').trim().isEmpty);
          return !isHomeBannerOnly;
        }).toList();
      });
    }
  }

  @override
  void dispose() {
    SupabaseService().announcementsNotifier.removeListener(_onFreshAnnouncementsReceived);
    _announcementInsertSub?.cancel();
    _announcementUpdateSub?.cancel();
    super.dispose();
  }

  Future<void> _loadAnnouncements({bool forceRefresh = false, bool showSpinner = false}) async {
    if (showSpinner || _announcements.isEmpty) {
      setState(() => _isLoading = true);
    }
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

    final rawList = await service.fetchAnnouncements(
      department: dept,
      stage: stage,
      section: section,
      forceRefresh: forceRefresh,
    );

    // استبعاد بوسترات الواجهة الرئيسية البحتة لتبقى شاشة التبليغات مخصصة للتبليغات الأكاديمية
    _announcements = rawList.where((a) {
      final isHomeBannerOnly = (a.category == 'banner' || a.subjectName == 'BANNER' || a.content.contains('[HOME_BANNER]')) &&
          (a.content.replaceAll(RegExp(r'\[.*?\]'), '').trim().isEmpty);
      return !isHomeBannerOnly;
    }).toList();

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
    final cleanQuery = _searchQuery.trim().toLowerCase();
    return _announcements.where((a) {
      final matchesCategory = _selectedCategory == 'ALL' || a.category == _selectedCategory;
      final matchesSearch = cleanQuery.isEmpty || a.searchToken.contains(cleanQuery);
      return matchesCategory && matchesSearch;
    }).toList();
  }

  bool get _canPublish {
    final u = _user;
    if (u == null) return false;
    return u.isAdmin ||
        u.isRepresentative ||
        u.canManageAnnouncements ||
        u.canPublishAnnouncements ||
        u.canPublishAnnouncements ||
        u.studentId == 'ST-NUST-001630760-413';
  }

  void _showPublishAnnouncementSheet(BuildContext context) {
    if (_user == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _DirectPublishAnnouncementSheet(
        currentUser: _user!,
        onOptimisticSubmit: (optimisticAnnounce, selectedImage) async {
          // 1. استجابة لحظية فائقة السرعة بنمط Optimistic UI (إدراج فوري دون انتظار الشبكة)
          setState(() {
            _announcements.insert(0, optimisticAnnounce);
          });
          HapticFeedback.lightImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم النشر بنجاح'),
              backgroundColor: AppTheme.primary,
              duration: Duration(seconds: 2),
            ),
          );

          // 2. المزامنة في الخلفية بأمان
          try {
            String? uploadedImageUrl;
            if (selectedImage != null) {
              final res = await TelegramUploaderService().uploadFileToTelegram(
                file: selectedImage,
                caption: optimisticAnnounce.title,
                fileType: 'announcement',
              );
              if (res.success && res.fileUrl != null) {
                uploadedImageUrl = res.fileUrl;
              }
            }

            final finalAnnounce = AnnouncementModel(
              id: '',
              title: optimisticAnnounce.title,
              content: optimisticAnnounce.content,
              authorId: optimisticAnnounce.authorId,
              authorName: optimisticAnnounce.authorName,
              authorRole: optimisticAnnounce.authorRole,
              department: optimisticAnnounce.department,
              stage: optimisticAnnounce.stage,
              section: optimisticAnnounce.section,
              category: optimisticAnnounce.category,
              isPinned: optimisticAnnounce.isPinned,
              imageUrl: uploadedImageUrl ?? optimisticAnnounce.imageUrl,
              subjectName: optimisticAnnounce.subjectName,
              createdAt: DateTime.now(),
            );

            final ok = await SupabaseService().createAnnouncement(finalAnnounce);
            if (!ok) throw Exception('تعذر حفظ التبليغ في قاعدة البيانات');

            // 3. تأكيد المزامنة واستبدال الكارت المؤقت
            if (mounted) {
              _loadAnnouncements(forceRefresh: true, showSpinner: false);
            }
          } catch (e) {
            debugPrint('[-] Optimistic announcement sync error: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('تعذر إكمال النشر: $e'),
                  backgroundColor: AppTheme.danger,
                ),
              );
            }
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPublish = _canPublish;

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
            onPressed: () => _loadAnnouncements(forceRefresh: true, showSpinner: false),
          ),
        ],
      ),
      floatingActionButton: canPublish
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'create_poll_fab',
                  backgroundColor: AppTheme.primaryDark,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.poll_rounded, size: 20),
                  label: Text('تصويت', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13)),
                  onPressed: () {
                    CreatePollSheet.show(
                      context: context,
                      currentUser: _user!,
                      department: _user!.department,
                      stage: _user!.stage,
                      onSuccess: (_) => _loadAnnouncements(forceRefresh: true),
                    );
                  },
                ),
                const SizedBox(width: 10),
                FloatingActionButton.extended(
                  heroTag: 'create_announce_fab',
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.add_photo_alternate_rounded, size: 20),
                  label: Text('نشر تبليغ', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13)),
                  onPressed: () => _showPublishAnnouncementSheet(context),
                ),
              ],
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : Column(
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
                            cacheExtent: 800,
                            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            itemCount: _filteredList.length,
                            addAutomaticKeepAlives: true,
                            addRepaintBoundaries: true,
                            itemBuilder: (context, index) {
                              final item = _filteredList[index];
                              if (item.isPoll) {
                                return RepaintBoundary(
                                  key: ValueKey('poll_b_${item.id}'),
                                  child: TelegramPollCard(
                                    key: ValueKey('poll_${item.id}'),
                                    announcement: item,
                                    currentUser: _user,
                                    onVoteChanged: () => _loadAnnouncements(forceRefresh: false, showSpinner: false),
                                    onDelete: () => _confirmDeleteAnnouncement(item),
                                  ),
                                );
                              }
                              return RepaintBoundary(
                                key: ValueKey('ann_b_${item.id}'),
                                child: TelegramAnnouncementCard(
                                  key: ValueKey('ann_${item.id}'),
                                  announcement: item,
                                  currentUser: _user,
                                  onReactionToggled: (emoji) => _toggleReaction(item, emoji),
                                  onDelete: () => _confirmDeleteAnnouncement(item),
                                ),
                              );
                            },
                            ),
                  ),
                ],
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
        if (selected) {
          HapticFeedback.selectionClick();
          setState(() => _selectedCategory = categoryKey);
        }
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

/// نافذة نشر تبليغ مباشر مع إرفاق الصور والكتب الرسمية من خانة التبليغات
class _DirectPublishAnnouncementSheet extends StatefulWidget {
  final AppUserModel currentUser;
  final Function(AnnouncementModel optimisticAnnounce, PlatformFile? selectedImage) onOptimisticSubmit;

  const _DirectPublishAnnouncementSheet({
    required this.currentUser,
    required this.onOptimisticSubmit,
  });

  @override
  State<_DirectPublishAnnouncementSheet> createState() => _DirectPublishAnnouncementSheetState();
}

class _DirectPublishAnnouncementSheetState extends State<_DirectPublishAnnouncementSheet> {
  final _contentController = TextEditingController();
  PlatformFile? _selectedImage;
  int _selectedImageSize = 0;
  bool _isPickingImage = false;

  late String _dept;
  late String _stage;
  late String _section;
  String _category = 'academic';
  bool _isPinned = false;

  @override
  void initState() {
    super.initState();
    final u = widget.currentUser;
    _dept = u.isAdmin ? 'ALL' : u.department;
    _stage = u.isAdmin ? 'ALL' : u.stage;
    _section = u.isAdmin
        ? 'ALL'
        : (u.assignedSections.isNotEmpty ? u.assignedSections.first : 'ALL');
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  String _formatFileSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
  }

  Future<void> _pickImage() async {
    setState(() => _isPickingImage = true);
    final file = await TelegramUploaderService().pickImageOnly();
    if (mounted) {
      if (file != null) {
        final size = await TelegramUploaderService().getFileSize(file);
        setState(() {
          _isPickingImage = false;
          _selectedImage = file;
          _selectedImageSize = size;
        });
      } else {
        setState(() => _isPickingImage = false);
      }
    }
  }

  void _submit() {
    final content = _contentController.text.trim();
    if (content.isEmpty && _selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى كتابة نص التبليغ أو إرفاق صورة'), backgroundColor: AppTheme.danger),
      );
      return;
    }

    final firstLine = content.isNotEmpty ? content.split('\n').first.trim() : '';
    final autoTitle = firstLine.length > 50
        ? '${firstLine.substring(0, 47)}...'
        : (firstLine.isNotEmpty ? firstLine : 'إعلان مصور');

    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final optimisticAnnounce = AnnouncementModel(
      id: tempId,
      title: autoTitle,
      content: content,
      authorId: widget.currentUser.studentId.isNotEmpty ? widget.currentUser.studentId : 'ADMIN',
      authorName: widget.currentUser.name.isNotEmpty ? widget.currentUser.name : 'إدارة الكلية',
      authorRole: widget.currentUser.role,
      department: _dept,
      stage: _stage,
      section: _section,
      category: _category,
      isPinned: _isPinned,
      imageUrl: null,
      subjectName: 'ANNOUNCEMENT',
      createdAt: DateTime.now(),
    );

    // إغلاق النافذة فورياً بنمط وتجربة التطبيقات العالمية دون انتظار الرفع السحابي
    Navigator.pop(context);
    widget.onOptimisticSubmit(optimisticAnnounce, _selectedImage);
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.currentUser.isAdmin;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 12,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // مقبض السحب
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // رأس النافذة
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primarySubtle,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.campaign_rounded, color: AppTheme.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'نشر تبليغ',
                        style: GoogleFonts.cairo(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        isAdmin
                            ? 'نشر عام'
                            : '${widget.currentUser.department} • ${widget.currentUser.stage}',
                        style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // حقل النص
            TextField(
              controller: _contentController,
              maxLines: 5,
              style: GoogleFonts.cairo(fontSize: 13, color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: 'نص التبليغ',
                hintText: 'اكتب نص التبليغ هنا...',
                labelStyle: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textSecondary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                alignLabelWithHint: true,
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(bottom: 70),
                  child: Icon(Icons.campaign_rounded, size: 22, color: AppTheme.primary),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // مساحة إرفاق صورة
            if (_selectedImage == null)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(color: AppTheme.accent.withValues(alpha: 0.6), width: 1.2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: _isPickingImage
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add_photo_alternate_rounded, color: AppTheme.accent),
                label: Text(
                  'إرفاق صورة (اختياري)',
                  style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                onPressed: _isPickingImage ? null : _pickImage,
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.image_rounded, color: AppTheme.accent, size: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedImage!.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            _formatFileSize(_selectedImageSize),
                            style: GoogleFonts.cairo(fontSize: 10, color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18, color: AppTheme.danger),
                      tooltip: 'إلغاء إرفاق الصورة',
                      onPressed: () => setState(() {
                        _selectedImage = null;
                        _selectedImageSize = 0;
                      }),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 14),

            if (isAdmin) ...[
              DropdownButtonFormField<String>(
                value: _dept,
                dropdownColor: Colors.white,
                style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'القسم المستهدف',
                  labelStyle: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textSecondary),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.domain_rounded, size: 20, color: AppTheme.primaryLight),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: [
                  const DropdownMenuItem(value: 'ALL', child: Text('كافة أقسام الكلية')),
                  ...AppConstants.departments.map((d) => DropdownMenuItem(value: d, child: Text(d))),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _dept = val);
                },
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                value: _stage,
                dropdownColor: Colors.white,
                style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'المرحلة المستهدفة',
                  labelStyle: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textSecondary),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.school_rounded, size: 20, color: AppTheme.primaryLight),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: [
                  const DropdownMenuItem(value: 'ALL', child: Text('كافة المراحل الدراسية')),
                  ...AppConstants.stages.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _stage = val);
                },
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                value: (widget.currentUser.isAdmin || widget.currentUser.assignedSections.contains(_section) || _section == 'ALL')
                    ? _section
                    : (widget.currentUser.assignedSections.isNotEmpty ? widget.currentUser.assignedSections.first : 'ALL'),
                dropdownColor: Colors.white,
                style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'الشعبة المستهدفة',
                  labelStyle: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textSecondary),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.groups_rounded, size: 20, color: AppTheme.accent),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: [
                  const DropdownMenuItem(value: 'ALL', child: Text('جميع الشعب')),
                  if (widget.currentUser.isAdmin) ...const [
                    DropdownMenuItem(value: 'A', child: Text('شعبة A')),
                    DropdownMenuItem(value: 'B', child: Text('شعبة B')),
                    DropdownMenuItem(value: 'C', child: Text('شعبة C')),
                    DropdownMenuItem(value: 'D', child: Text('شعبة D')),
                    DropdownMenuItem(value: 'E', child: Text('شعبة E')),
                    DropdownMenuItem(value: 'F', child: Text('شعبة F')),
                  ] else ...[
                    for (final s in widget.currentUser.assignedSections.where((s) => s != 'ALL'))
                      DropdownMenuItem(value: s, child: Text('شعبة $s')),
                  ],
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _section = val);
                },
              ),
              const SizedBox(height: 12),

              SwitchListTile(
                title: Text('تثبيت الإعلان في الأعلى', style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textPrimary)),
                value: _isPinned,
                activeThumbColor: AppTheme.accent,
                contentPadding: EdgeInsets.zero,
                onChanged: (val) => setState(() => _isPinned = val),
              ),
              const SizedBox(height: 12),
            ],

            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _submit,
              icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
              label: Text(
                'نشر التبليغ',
                style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

