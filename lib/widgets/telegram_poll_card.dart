import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/app_theme.dart';
import '../models/announcement_model.dart';
import '../models/app_user_model.dart';
import '../services/supabase_service.dart';
import 'app_tactile_bounce.dart';

/// بطاقة استطلاع الرأي الأكاديمي بنمط تيليجرام التفاعلي
/// التصويت سري ومجهول للطلاب، مع حصرية كشف المصوتين للمشرف العام مجتبى عواد فقط
class TelegramPollCard extends StatefulWidget {
  final AnnouncementModel announcement;
  final AppUserModel? currentUser;
  final VoidCallback? onVoteChanged;
  final VoidCallback? onDelete;

  const TelegramPollCard({
    super.key,
    required this.announcement,
    required this.currentUser,
    this.onVoteChanged,
    this.onDelete,
  });

  @override
  State<TelegramPollCard> createState() => _TelegramPollCardState();
}

class _TelegramPollCardState extends State<TelegramPollCard> {
  PollData? _localPoll;
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    _localPoll = widget.announcement.pollData;
  }

  @override
  void didUpdateWidget(TelegramPollCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.announcement.id != oldWidget.announcement.id ||
        widget.announcement.content != oldWidget.announcement.content) {
      _localPoll = widget.announcement.pollData;
    }
  }

  bool get _isMujtabaAdmin {
    final user = widget.currentUser;
    if (user == null) return false;
    return user.isAdmin ||
        user.studentId == 'ST-NUST-001630760-413' ||
        user.studentId == 'ST-NUST-001630760-413';
  }

  bool get _canClosePoll {
    final user = widget.currentUser;
    if (user == null) return false;
    return _isMujtabaAdmin || user.studentId == widget.announcement.authorId;
  }

  Future<void> _handleVote(int optionIndex) async {
    final user = widget.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى تسجيل الدخول أولاً للمشاركة بالتصويت')),
      );
      return;
    }

    final currentPoll = _localPoll ?? widget.announcement.pollData;
    if (currentPoll == null || currentPoll.isClosed) return;

    // استجابة لمسية فورية (Haptic Feedback) لإحساس خفيف وطبيعي
    HapticFeedback.lightImpact();

    final studentKey = user.studentId.isNotEmpty ? user.studentId : user.id;
    final previousState = currentPoll;

    // 1. تحديث لحظي وفوري في الذاكرة (0ms Optimistic UI)
    // خيار واحد حصرياً: الضغط على خيار آخر ينقل التصويت إليه مباشرة، والضغط على نفس الخيار يلغيه
    final updatedVotes = Map<String, PollVote>.from(currentPoll.votes);
    final previousVote = updatedVotes[studentKey];

    if (previousVote != null && previousVote.selectedOptionIndices.contains(optionIndex)) {
      // إلغاء التصويت بالضغط على نفس الخيار مجدداً
      updatedVotes.remove(studentKey);
    } else {
      // اختيار هذا الخيار حصرياً
      updatedVotes[studentKey] = PollVote(
        studentId: studentKey,
        studentName: user.name,
        department: user.department,
        stage: user.stage,
        section: user.section ?? '',
        selectedOptionIndices: [optionIndex], // خيار واحد فقط
        votedAt: DateTime.now(),
      );
    }

    final optimisticPoll = currentPoll.copyWith(votes: updatedVotes);
    setState(() {
      _localPoll = optimisticPoll;
    });

    // 2. مزامنة هادئة مع السيرفر في الخلفية دون أي تجميد أو إعادة تحميل كامل للشاشة
    try {
      final updated = await SupabaseService().castPollVote(
        announcementId: widget.announcement.id,
        optionIndex: optionIndex,
        user: user,
      );
      if (updated != null && mounted) {
        final serverPoll = updated.pollData;
        if (serverPoll != null) {
          setState(() {
            _localPoll = serverPoll;
          });
        }
      }
    } catch (_) {
      // في حال حدوث خطأ استرجاع الحالة السابقة
      if (mounted) {
        setState(() {
          _localPoll = previousState;
        });
      }
    }
  }

  Future<void> _handleClosePoll() async {
    final user = widget.currentUser;
    if (user == null || !_canClosePoll) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('إغلاق الاستطلاع', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text(
          'هل أنت متأكد من رغبتك في إغلاق التصويت وتثبيت النتائج الحالية نهائياً؟',
          style: GoogleFonts.cairo(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('إلغاء', style: GoogleFonts.cairo()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('إغلاق التصويت', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isClosing = true);
    final ok = await SupabaseService().closePoll(
      announcementId: widget.announcement.id,
      user: user,
    );
    if (mounted) {
      setState(() => _isClosing = false);
      if (ok) {
        widget.onVoteChanged?.call();
      }
    }
  }

  void _showVotersInspector(BuildContext context) {
    final poll = _localPoll ?? widget.announcement.pollData;
    if (poll == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => _PollVotersInspectorSheet(
        announcement: widget.announcement,
        poll: poll,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final announcement = widget.announcement;
    final poll = _localPoll ?? announcement.pollData;
    if (poll == null) return const SizedBox.shrink();

    final currentStudentId = widget.currentUser?.studentId ?? widget.currentUser?.id ?? '';
    final hasVoted = poll.hasStudentVoted(currentStudentId);
    final userSelections = poll.getStudentSelections(currentStudentId);
    final isClosed = poll.isClosed;
    final totalVoters = poll.totalVotersCount;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isClosed ? AppTheme.lightBorder : AppTheme.primary.withValues(alpha: 0.35),
          width: isClosed ? 1.0 : 1.4,
        ),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // شريط نوع الاستطلاع والحالة (بدون شارة نشط للتصويت)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: isClosed ? const Color(0xFFF1F5F9) : AppTheme.primarySubtle,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
              border: Border(
                bottom: BorderSide(
                  color: isClosed ? const Color(0xFFE2E8F0) : const Color(0xFFD6E4FF),
                  width: 0.8,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.poll_rounded,
                  size: 15,
                  color: isClosed ? const Color(0xFF64748B) : AppTheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'استطلاع رأي أكاديمي',
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isClosed ? const Color(0xFF475569) : AppTheme.primary,
                  ),
                ),
                const Spacer(),
                if (isClosed)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Color(0xFF64748B),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'مغلق',
                          style: GoogleFonts.cairo(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF475569),
                          ),
                        ),
                      ],
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
                // 1. رأس المنشور والقناة
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.primary, AppTheme.primaryLight],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.how_to_vote_rounded, color: Colors.white, size: 20),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  announcement.authorName.isNotEmpty ? announcement.authorName : 'ممثل المرحلة',
                                  style: GoogleFonts.cairo(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: AppTheme.primarySubtle,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  announcement.section == 'ALL' ? '🌐 عام' : '🏷️ شعبة ${announcement.section}',
                                  style: GoogleFonts.cairo(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            announcement.subjectName != null && announcement.subjectName!.isNotEmpty
                                ? 'مقرر: ${announcement.subjectName}'
                                : 'استطلاع طلابي رسمي',
                            style: GoogleFonts.cairo(fontSize: 10.5, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                    if (_isMujtabaAdmin && widget.onDelete != null)
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'حذف الاستطلاع',
                        onPressed: widget.onDelete,
                      ),
                  ],
                ),

                const SizedBox(height: 12),

                // 2. سؤال الاستطلاع
                Text(
                  poll.question,
                  style: GoogleFonts.cairo(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                    height: 1.4,
                  ),
                ),

                const SizedBox(height: 14),

                // 3. خيارات التصويت الفردي السلس بنمط راديو تيليجرام
                ...List.generate(poll.options.length, (index) {
                  final optionText = poll.options[index];
                  final isSelected = userSelections.contains(index);
                  final votesCount = poll.getVotesForOption(index);
                  final percentage = poll.getPercentageForOption(index);
                  final percentFormatted = (percentage * 100).toStringAsFixed(0);

                  final showResults = hasVoted || isClosed;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: AppTactileBounce(
                      lowerBound: 0.96,
                      borderRadius: BorderRadius.circular(12),
                      onTap: isClosed ? null : () => _handleVote(index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFFEEF3FF) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? AppTheme.primary : const Color(0xFFE2E8F0),
                            width: isSelected ? 1.6 : 1.0,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          children: [
                            // شريط التقدم الخلفي بنمط RTL متدفق بسلاسة
                            if (showResults)
                              TweenAnimationBuilder<double>(
                                duration: const Duration(milliseconds: 350),
                                curve: Curves.easeOutCubic,
                                tween: Tween<double>(
                                  begin: 0.0,
                                  end: percentage.clamp(0.0, 1.0),
                                ),
                                builder: (context, animVal, _) {
                                  if (animVal <= 0.001) return const SizedBox.shrink();
                                  return Positioned.fill(
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: FractionallySizedBox(
                                        widthFactor: animVal,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? AppTheme.primary.withValues(alpha: 0.16)
                                                : const Color(0xFFCBD5E1).withValues(alpha: 0.28),
                                            borderRadius: BorderRadius.circular(11),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),

                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                              child: Row(
                                children: [
                                  // دائرة الاختيار الفردي بنمط راديو أنيق
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isSelected ? AppTheme.primary : Colors.transparent,
                                      border: Border.all(
                                        color: isSelected ? AppTheme.primary : const Color(0xFF94A3B8),
                                        width: 1.6,
                                      ),
                                    ),
                                    child: isSelected
                                        ? const Center(
                                            child: Icon(Icons.check, size: 13, color: Colors.white),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 10),

                                  // نص الخيار
                                  Expanded(
                                    child: Text(
                                      optionText,
                                      style: GoogleFonts.cairo(
                                        fontSize: 13,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                        color: isSelected ? AppTheme.primary : AppTheme.textPrimary,
                                      ),
                                    ),
                                  ),

                                  // النسبة المئوية والأصوات
                                  if (showResults) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      '$percentFormatted% ($votesCount)',
                                      style: GoogleFonts.cairo(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                        color: isSelected ? AppTheme.primary : const Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),

                const SizedBox(height: 10),

                // 4. تذييل البطاقة (إجمالي الأصوات + أزرار التحكم)
                Row(
                  children: [
                    Icon(Icons.groups_outlined, size: 15, color: AppTheme.textMuted),
                    const SizedBox(width: 5),
                    Text(
                      'شارك $totalVoters طالباً',
                      style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textSecondary),
                    ),
                    const Spacer(),

                    // زر كشف المصوتين (حصري للمشرف العام مجتبى عواد فقط)
                    if (_isMujtabaAdmin && totalVoters > 0) ...[
                      InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _showVotersInspector(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
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
                              const Icon(Icons.visibility_rounded, size: 13, color: Colors.white),
                              const SizedBox(width: 4),
                              Text(
                                'المصوتون ($totalVoters)',
                                style: GoogleFonts.cairo(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],

                    // زر إغلاق الاستطلاع للممثل أو مجتبى
                    if (!isClosed && _canClosePoll) ...[
                      OutlinedButton.icon(
                        onPressed: _isClosing ? null : _handleClosePoll,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF64748B),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          minimumSize: Size.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                        ),
                        icon: const Icon(Icons.lock_outline_rounded, size: 13),
                        label: Text(
                          'إغلاق',
                          style: GoogleFonts.cairo(fontSize: 10.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// نافذة فحص وتدقيق المصوتين (خاصة بالمشرف العام مجتبى عواد حصرياً)
class _PollVotersInspectorSheet extends StatefulWidget {
  final AnnouncementModel announcement;
  final PollData poll;

  const _PollVotersInspectorSheet({
    required this.announcement,
    required this.poll,
  });

  @override
  State<_PollVotersInspectorSheet> createState() => _PollVotersInspectorSheetState();
}

class _PollVotersInspectorSheetState extends State<_PollVotersInspectorSheet> {
  int _selectedOptionFilter = -1; // -1 يعني الكل

  @override
  Widget build(BuildContext context) {
    final poll = widget.poll;
    final allVotes = poll.votes.values.toList();

    List<PollVote> filteredVotes;
    if (_selectedOptionFilter == -1) {
      filteredVotes = allVotes;
    } else {
      filteredVotes = poll.getVotersForOption(_selectedOptionFilter);
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primarySubtle,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.how_to_vote_rounded, color: AppTheme.primary, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'سجل المصوتين في الاستطلاع',
                          style: GoogleFonts.cairo(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          'خاص بالمشرف العام مجتبى عواد (${allVotes.length} صوت مسجل)',
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

            // شريط تصفية الخيارات
            Container(
              height: 40,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildFilterChip('الكل (${allVotes.length})', -1),
                  ...List.generate(poll.options.length, (idx) {
                    final count = poll.getVotesForOption(idx);
                    return _buildFilterChip('${poll.options[idx]} ($count)', idx);
                  }),
                ],
              ),
            ),

            const Divider(height: 1),

            // قائمة المصوتين
            Expanded(
              child: filteredVotes.isEmpty
                  ? Center(
                      child: Text(
                        'لا يوجد مصوتون في هذا الخيار',
                        style: GoogleFonts.cairo(color: AppTheme.textMuted, fontSize: 13),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemCount: filteredVotes.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 48),
                      itemBuilder: (ctx, index) {
                        final v = filteredVotes[index];
                        final votedOptions = v.selectedOptionIndices
                            .where((i) => i >= 0 && i < poll.options.length)
                            .map((i) => poll.options[i])
                            .join(' • ');

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: AppTheme.primarySubtle,
                                child: Text(
                                  v.studentName.isNotEmpty ? v.studentName.characters.first : 'ط',
                                  style: GoogleFonts.cairo(
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primary,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      v.studentName,
                                      style: GoogleFonts.cairo(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      '${v.studentId} • شعبة ${v.section.isNotEmpty ? v.section : '-'}',
                                      style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textMuted),
                                    ),
                                    Text(
                                      'صوّت لـ: $votedOptions',
                                      style: GoogleFonts.cairo(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '${v.votedAt.hour.toString().padLeft(2, '0')}:${v.votedAt.minute.toString().padLeft(2, '0')}',
                                style: GoogleFonts.cairo(fontSize: 10.5, color: const Color(0xFF94A3B8)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilterChip(String label, int optionIdx) {
    final isSelected = _selectedOptionFilter == optionIdx;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => setState(() => _selectedOptionFilter = optionIdx),
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
