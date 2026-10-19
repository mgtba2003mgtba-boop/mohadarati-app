import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/app_theme.dart';
import '../models/announcement_model.dart';
import '../models/app_user_model.dart';
import 'app_fullscreen_modal.dart';
import 'app_media_preview_modal.dart';
import 'app_network_image.dart';
import 'app_tactile_bounce.dart';

/// بطاقة التبليغات الكلاسيكية المستوحاة من قنوات تيليجرام الرسمية
/// تدعم التفاعلات الأكاديمية المجهولة للطلاب، مع حصرية كشف المتفاعلين للمشرف العام مجتبى عواد
class TelegramAnnouncementCard extends StatefulWidget {
  final AnnouncementModel announcement;
  final AppUserModel? currentUser;
  final Function(String emoji)? onReactionToggled;
  final VoidCallback? onDelete;

  const TelegramAnnouncementCard({
    super.key,
    required this.announcement,
    required this.currentUser,
    this.onReactionToggled,
    this.onDelete,
  });

  @override
  State<TelegramAnnouncementCard> createState() => _TelegramAnnouncementCardState();
}

class _TelegramAnnouncementCardState extends State<TelegramAnnouncementCard> {
  // قائمة باقة التفاعلات الأكاديمية الشاملة المعتمدة
  static const List<String> _availableReactions = ['👍', '❤️', '👏', '💡', '🔥'];

  bool get _isMujtabaAdmin {
    final user = widget.currentUser;
    if (user == null) return false;
    return user.isAdmin ||
        user.studentId == 'ST-NUST-001630760-413' ||
        user.name.contains('مجتبى');
  }

  void _showAnnouncementModal(BuildContext context) {
    AppFullscreenModal.show(
      context: context,
      title: widget.announcement.subjectName != null && widget.announcement.subjectName!.isNotEmpty
          ? 'تبليغ • ${widget.announcement.subjectName}'
          : (widget.announcement.title.isNotEmpty ? widget.announcement.title : 'تبليغ أكاديمي'),
      subtitle: '${widget.announcement.createdAt.year}/${widget.announcement.createdAt.month.toString().padLeft(2, '0')}/${widget.announcement.createdAt.day.toString().padLeft(2, '0')}',
      icon: Icons.campaign_rounded,
      imageUrl: widget.announcement.imageUrl,
      contentText: widget.announcement.displayContent,
      accentColor: AppTheme.primary,
      actions: [
        if (_isMujtabaAdmin && widget.onDelete != null)
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              widget.onDelete!();
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Colors.redAccent),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.delete_rounded, size: 18),
            label: Text('حذف التبليغ', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          ),
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

  /// نافذة منبثقة عائمة لاختيار التفاعل بنمط قنوات تيليجرام
  void _showReactionPicker(BuildContext context) {
    final currentStudentId = widget.currentUser?.studentId ?? widget.currentUser?.id ?? '';

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (ctx) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              tween: Tween(begin: 0.65, end: 1.0),
              builder: (context, scale, child) {
                return Transform.scale(
                  scale: scale,
                  child: child,
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 22,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: _availableReactions.map((emoji) {
                    final hasReacted = widget.announcement.hasUserReacted(currentStudentId, emoji);
                    return InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () {
                        Navigator.pop(ctx);
                        if (widget.onReactionToggled != null) {
                          widget.onReactionToggled!(emoji);
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: hasReacted ? const Color(0xFFEFF6FF) : Colors.transparent,
                          shape: BoxShape.circle,
                          border: hasReacted
                              ? Border.all(color: AppTheme.primary, width: 1.6)
                              : null,
                        ),
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 26),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// نافذة فحص المتفاعلين مع التبليغ (حصرية تماماً للمشرف العام مجتبى عواد)
  void _showReactorsInspector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return _ReactorsInspectorSheet(
          announcement: widget.announcement,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final announcement = widget.announcement;
    final hasContent = announcement.displayContent.trim().isNotEmpty;
    final hasImage = announcement.imageUrl != null &&
        announcement.imageUrl!.trim().isNotEmpty &&
        announcement.imageUrl != 'null' &&
        announcement.imageUrl != 'undefined';
    final hasPoll = announcement.isPoll;

    // حماية وقائية (Zero-Render): عدم رسم البطاقة نهائياً إن كانت خالية من المحتوى والصور والاستطلاعات
    if (!hasContent && !hasImage && !hasPoll) {
      return const SizedBox.shrink();
    }

    final currentStudentId = widget.currentUser?.studentId ?? widget.currentUser?.id;
    final counts = announcement.reactionCounts;
    final totalReactions = announcement.totalReactionsCount;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: announcement.isPinned ? AppTheme.primary.withValues(alpha: 0.6) : AppTheme.lightBorder,
          width: announcement.isPinned ? 1.5 : 1.0,
        ),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // شريط المنشور المثبت إن وجد
          if (announcement.isPinned)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: const BoxDecoration(
                color: Color(0xFFF0F9FF),
                borderRadius: BorderRadius.vertical(top: Radius.circular(17)),
                border: Border(bottom: BorderSide(color: Color(0xFFBAE6FD), width: 0.8)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.push_pin_rounded, size: 14, color: Color(0xFF0284C7)),
                  const SizedBox(width: 6),
                  Text(
                    'تبليغ مثبت في القناة الرسمية',
                    style: GoogleFonts.cairo(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0369A1),
                    ),
                  ),
                ],
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. رأس المنشور (Telegram Channel Header)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // أيقونة القناة الرسمية
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.primary, AppTheme.primaryLight],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(13),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.campaign_rounded, color: Colors.white, size: 22),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  announcement.authorName.isNotEmpty
                                      ? announcement.authorName
                                      : 'قناة التبليغات الرسمية',
                                  style: GoogleFonts.cairo(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 1),
                          Row(
                            children: [
                              Text(
                                '${announcement.createdAt.year}/${announcement.createdAt.month.toString().padLeft(2, '0')}/${announcement.createdAt.day.toString().padLeft(2, '0')}',
                                style: GoogleFonts.cairo(fontSize: 10.5, color: AppTheme.textMuted),
                              ),
                              if (announcement.section != 'ALL') ...[
                                Text(' • ', style: GoogleFonts.cairo(color: AppTheme.textMuted)),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: const Color(0xFFBFDBFE), width: 0.6),
                                  ),
                                  child: Text(
                                    'شعبة ${announcement.section}',
                                    style: GoogleFonts.cairo(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF1D4ED8),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),

                    // زر حذف المنشور للمشرف العام
                    if (_isMujtabaAdmin && widget.onDelete != null)
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'حذف التبليغ',
                        onPressed: widget.onDelete,
                      ),
                  ],
                ),

                // 2. فقاعة نص التبليغ مباشرة بنمط قنوات تيليجرام (فقط إن كان النص غير فارغ)
                if (hasContent) ...[
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () => _showAnnouncementModal(context),
                    onLongPress: () => _showReactionPicker(context),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFF1F5F9)),
                      ),
                      child: Text(
                        announcement.displayContent,
                        style: GoogleFonts.cairo(
                          fontSize: 13.5,
                          color: const Color(0xFF1E293B),
                          height: 1.6,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],

                // 4. صورة التبليغ إن وجدت (مع دعم التكبير والتدوير والمعاينة التفاعلية)
                if (hasImage) ...[
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () {
                      AppMediaPreviewModal.show(
                        context: context,
                        title: announcement.title.isNotEmpty ? announcement.title : 'صورة التبليغ الأكاديمي',
                        subtitle: announcement.subjectName != null && announcement.subjectName!.isNotEmpty
                            ? announcement.subjectName
                            : '${announcement.department} • ${announcement.stage}',
                        url: announcement.imageUrl!,
                        fileName: 'announcement_${announcement.id}.jpg',
                        mimeType: 'image/jpeg',
                      );
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        alignment: Alignment.bottomLeft,
                        children: [
                          AppNetworkImage(
                            imageUrl: announcement.imageUrl!,
                            height: 180,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorWidget: const SizedBox.shrink(),
                          ),
                          Container(
                            margin: const EdgeInsets.all(8),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.zoom_in_rounded, size: 14, color: Colors.white),
                                const SizedBox(width: 4),
                                Text(
                                  'اضغط للتكبير والفحص 🔍',
                                  style: GoogleFonts.cairo(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                // 5. شريط التفاعلات الأكاديمية بنمط قنوات تيليجرام
                Builder(
                  builder: (context) {
                    final activeReactions = _availableReactions.where((emoji) => (counts[emoji] ?? 0) > 0).toList();
                    if (activeReactions.isEmpty && !(_isMujtabaAdmin && totalReactions > 0)) {
                      return const SizedBox.shrink();
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  // عرض التفاعلات النشطة فقط التي حصلت على نقرات count > 0
                                  ...activeReactions.map((emoji) {
                                    final count = counts[emoji] ?? 0;
                                    final hasReacted = announcement.hasUserReacted(currentStudentId, emoji);

                                    return AppTactileBounce(
                                      lowerBound: 0.92,
                                      borderRadius: BorderRadius.circular(20),
                                      onTap: () {
                                        if (widget.onReactionToggled != null) {
                                          widget.onReactionToggled!(emoji);
                                        }
                                      },
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 180),
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                                        decoration: BoxDecoration(
                                          color: hasReacted
                                              ? const Color(0xFFEFF6FF)
                                              : const Color(0xFFF8FAFC),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(
                                            color: hasReacted
                                                ? AppTheme.primary
                                                : const Color(0xFFE2E8F0),
                                            width: hasReacted ? 1.4 : 1.0,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              emoji,
                                              style: const TextStyle(fontSize: 14),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '$count',
                                              style: GoogleFonts.cairo(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: hasReacted ? AppTheme.primary : const Color(0xFF64748B),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }),

                                  // زر إضافة تفاعل إضافي
                                  AppTactileBounce(
                                    lowerBound: 0.92,
                                    borderRadius: BorderRadius.circular(20),
                                    onTap: () => _showReactionPicker(context),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
                                      ),
                                      child: const Icon(
                                        Icons.add_reaction_outlined,
                                        size: 15,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // زر كشف المتفاعلين (حصر للمشرف العام مجتبى عواد فقط 👁️)
                            if (_isMujtabaAdmin && totalReactions > 0) ...[
                              const SizedBox(width: 8),
                              InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () => _showReactorsInspector(context),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [AppTheme.primary, AppTheme.primaryDark],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppTheme.primary.withValues(alpha: 0.2),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.visibility_rounded, size: 14, color: Colors.white),
                                      const SizedBox(width: 4),
                                      Text(
                                        'المتفاعلون ($totalReactions)',
                                        style: GoogleFonts.cairo(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// اللوحة السفلية لكشف أسماء وتفاصيل المتفاعلين (خاصة بالمشرف العام مجتبى فقط)
class _ReactorsInspectorSheet extends StatefulWidget {
  final AnnouncementModel announcement;

  const _ReactorsInspectorSheet({required this.announcement});

  @override
  State<_ReactorsInspectorSheet> createState() => _ReactorsInspectorSheetState();
}

class _ReactorsInspectorSheetState extends State<_ReactorsInspectorSheet> {
  String _selectedFilter = 'ALL';
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final allReactions = widget.announcement.reactionsList;
    final counts = widget.announcement.reactionCounts;

    final filtered = allReactions.where((r) {
      final matchesFilter = _selectedFilter == 'ALL' || r.reaction == _selectedFilter;
      final matchesSearch = _searchQuery.isEmpty ||
          r.studentName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          r.section.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          r.department.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesFilter && matchesSearch;
    }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scrollController) {
        return Column(
          children: [
            // مقبض السحب
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // رأس النافذة
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primarySubtle,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.people_alt_rounded, color: AppTheme.primary, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'سجل المتفاعلين مع التبليغ',
                          style: GoogleFonts.cairo(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          'خاص بالمشرف العام مجتبى عواد (${allReactions.length} تفاعل)',
                          style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // شريط تصفية الإيموجي
            Container(
              height: 42,
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildFilterChip('الكل (${allReactions.length})', 'ALL'),
                  ...counts.entries.map((entry) {
                    return _buildFilterChip('${entry.key} ${entry.value}', entry.key);
                  }),
                ],
              ),
            ),

            // شريط البحث بالاسم
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
                style: GoogleFonts.cairo(fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'البحث عن طالب أو شعبة...',
                  hintStyle: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textMuted),
                  prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppTheme.textSecondary),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 6),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),

            // قائمة الطلاب المتفاعلين
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'لا توجد تفاعلات مطابقة',
                        style: GoogleFonts.cairo(color: AppTheme.textMuted, fontSize: 13),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 12, color: Color(0xFFF1F5F9)),
                      itemBuilder: (_, idx) {
                        final reaction = filtered[idx];
                        return Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: const Color(0xFFF1F5F9),
                              child: Text(
                                reaction.studentName.isNotEmpty
                                    ? reaction.studentName.trim().substring(0, 1)
                                    : 'ط',
                                style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    reaction.studentName,
                                    style: GoogleFonts.cairo(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    '${reaction.department} • ${reaction.stage}${reaction.section.isNotEmpty ? " • شعبة ${reaction.section}" : ""}',
                                    style: GoogleFonts.cairo(fontSize: 10.5, color: AppTheme.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Text(
                                reaction.reaction,
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => setState(() => _selectedFilter = value),
        selectedColor: AppTheme.primary,
        backgroundColor: const Color(0xFFF1F5F9),
        labelStyle: GoogleFonts.cairo(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: isSelected ? Colors.white : AppTheme.textPrimary,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: isSelected ? AppTheme.primary : const Color(0xFFE2E8F0),
          ),
        ),
      ),
    );
  }
}
