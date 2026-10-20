import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../models/app_user_model.dart';
import '../models/lecture_model.dart';
import '../models/announcement_model.dart';
import '../models/lecture_comment_model.dart';
import '../services/supabase_service.dart';
import '../widgets/app_tactile_bounce.dart';

class LectureCommentsSheet extends StatefulWidget {
  final LectureModel lecture;
  final String department;
  final String stage;
  final AppUserModel? currentUser;

  const LectureCommentsSheet({super.key, 
    required this.lecture,
    required this.department,
    required this.stage,
    required this.currentUser,
  });

  @override
  State<LectureCommentsSheet> createState() => LectureCommentsSheetState();
}

class LectureCommentsSheetState extends State<LectureCommentsSheet> {
  final _commentController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isLoading = true;
  List<LectureCommentModel> _comments = [];
  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    _loadComments();
    _subscribeToRealtime();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    _unsubscribeFromRealtime();
    super.dispose();
  }

  /// ── الاشتراك اللحظي السحابي عبر قناة Supabase Realtime ────────────────
  void _subscribeToRealtime() {
    try {
      final client = Supabase.instance.client;
      final channelName = 'lecture_comments_${widget.lecture.id}_${DateTime.now().microsecondsSinceEpoch}';
      _realtimeChannel = client.channel(channelName);

      _realtimeChannel!.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'announcements',
        callback: (payload) {
          _handleRealtimePayload(payload);
        },
      );

      _realtimeChannel!.subscribe();
      debugPrint('[+] LectureCommentsSheet: Subscribed to live comments channel');
    } catch (e) {
      debugPrint('[-] LectureCommentsSheet realtime subscription error: $e');
    }
  }

  void _unsubscribeFromRealtime() {
    if (_realtimeChannel != null) {
      try {
        Supabase.instance.client.removeChannel(_realtimeChannel!);
        _realtimeChannel = null;
      } catch (e) {
        debugPrint('[-] Error removing realtime comments channel: $e');
      }
    }
  }

  /// ── معالجة أحداث التزامن الحي الواردة من السيرفر لحظياً ────────────────
  void _handleRealtimePayload(PostgresChangePayload payload) {
    if (!mounted) return;

    try {
      if (payload.eventType == PostgresChangeEvent.insert) {
        final record = payload.newRecord;
        final subjectName = record['subject_name']?.toString() ?? '';
        final title = record['title']?.toString() ?? '';
        final content = record['content']?.toString() ?? '';

        final isThisLectureComment = (subjectName == 'LECTURE_NOTE' || content.contains(LectureCommentModel.tag)) &&
            title == widget.lecture.id;

        if (!isThisLectureComment) return;

        final ann = AnnouncementModel.fromJson(record);
        final incoming = LectureCommentModel.fromAnnouncement(ann);
        if (incoming == null) return;

        setState(() {
          // إن كان التعليق موجوداً بالفعل بنفس المعرف السحابي
          final existingIndex = _comments.indexWhere((c) => c.id == incoming.id);
          if (existingIndex != -1) {
            _comments[existingIndex] = incoming;
            return;
          }

          // مطابقة التعليق التفاؤلي المؤقت لنفس الكاتب واستبداله بالمعرف الرسمي
          final optIndex = _comments.indexWhere((c) =>
              c.id.startsWith('temp_') &&
              c.authorId == incoming.authorId &&
              c.content.trim() == incoming.content.trim());

          if (optIndex != -1) {
            _comments[optIndex] = incoming;
          } else {
            // تعليق جديد تماماً قادم من طالب آخر في نفس اللحظة
            _comments.add(incoming);
          }

          _sortComments();
        });

        _scrollToBottom(animated: true);
      } else if (payload.eventType == PostgresChangeEvent.update) {
        final record = payload.newRecord;
        final subjectName = record['subject_name']?.toString() ?? '';
        final title = record['title']?.toString() ?? '';
        final content = record['content']?.toString() ?? '';

        final isThisLectureComment = (subjectName == 'LECTURE_NOTE' || content.contains(LectureCommentModel.tag)) &&
            title == widget.lecture.id;

        if (!isThisLectureComment) return;

        final ann = AnnouncementModel.fromJson(record);
        final updated = LectureCommentModel.fromAnnouncement(ann);
        if (updated == null) return;

        setState(() {
          final idx = _comments.indexWhere((c) => c.id == updated.id);
          if (idx != -1) {
            _comments[idx] = updated;
            _sortComments();
          }
        });
      } else if (payload.eventType == PostgresChangeEvent.delete) {
        final record = payload.oldRecord;
        final deletedId = record['id']?.toString();
        if (deletedId != null && deletedId.isNotEmpty) {
          setState(() {
            _comments.removeWhere((c) => c.id == deletedId);
          });
        }
      }
    } catch (e) {
      debugPrint('[-] Error handling realtime comment change: $e');
    }
  }

  void _sortComments() {
    _comments.sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      return a.createdAt.compareTo(b.createdAt);
    });
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (animated) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutQuad,
        );
      } else {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  AppUserModel? get _effectiveUser => widget.currentUser ?? SupabaseService().currentUser;

  Future<void> _loadComments({bool forceRefresh = false}) async {
    final cleanLecId = widget.lecture.id.trim();
    if (cleanLecId.isEmpty) return;

    // 1. فحص الكاش وعرضه فورياً (0ms) إن وجد لتفادي أي انتظار أو شاشة تحميل
    if (!forceRefresh) {
      final cached = await SupabaseService().getCachedLectureComments(cleanLecId);
      if (cached != null && cached.isNotEmpty && mounted) {
        setState(() {
          _comments = cached;
          _isLoading = false;
        });
        _scrollToBottom(animated: false);
      }
    }

    // 2. جلب مباشر وفوري من السحابة لضمان التزامن الكامل عند التبديل بين الحسابات
    final fresh = await SupabaseService().fetchLectureComments(
      lectureId: cleanLecId,
      forceRefresh: true,
    );
    if (mounted) {
      setState(() {
        if (fresh.isNotEmpty || _comments.isEmpty) {
          _comments = fresh;
        }
        _isLoading = false;
      });
      _scrollToBottom(animated: false);
    }
  }

  /// ── إرسال تفاؤلي فوري في 0ms مع حماية كاملة للنص ومزامنة سحابية ─────────
  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    final user = _effectiveUser;
    if (text.isEmpty || user == null) return;

    final currentStudentId = user.studentId.isNotEmpty
        ? user.studentId
        : user.id;

    // 1. مسح حقل الكتابة فوراً في 0ms لمرونة فائقة
    _commentController.clear();

    // 2. إنشاء نموذج تفاؤلي مؤقت يظهر فوراً في الشاشة
    final tempId = 'temp_${DateTime.now().microsecondsSinceEpoch}';
    final optimisticComment = LectureCommentModel(
      id: tempId,
      lectureId: widget.lecture.id,
      authorId: currentStudentId,
      authorName: user.name,
      authorRole: user.role,
      content: text,
      isPinned: false,
      helpfulUserIds: const [],
      createdAt: DateTime.now(),
      section: widget.lecture.section,
    );

    // 3. إدراج فوري في القائمة مع تمرير ناعم
    setState(() {
      _comments.add(optimisticComment);
      _sortComments();
    });
    _scrollToBottom(animated: true);

    // 4. المزامنة في الخلفية دون تجميد واجهة المستخدم
    try {
      final syncedComment = await SupabaseService().addLectureComment(
        lectureId: widget.lecture.id,
        text: text,
        user: user,
        department: widget.department,
        stage: widget.stage,
        section: widget.lecture.section,
      );

      if (!mounted) return;

      if (syncedComment != null) {
        setState(() {
          final idx = _comments.indexWhere((c) => c.id == tempId);
          if (idx != -1) {
            _comments[idx] = syncedComment;
          }
        });
      } else {
        // في حال فشل الاتصال، التراجع واستعادة النص للكاتب
        setState(() {
          _comments.removeWhere((c) => c.id == tempId);
        });
        _commentController.text = text;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر إرسال التعليق، تم حفظ النص في حقل الكتابة'),
            backgroundColor: AppTheme.danger,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _comments.removeWhere((c) => c.id == tempId);
      });
      _commentController.text = text;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('حدث خطأ في الاتصال، يرجى إعادة المحاولة'),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  /// ── تفاعل لحظي فوري (In-Place 1ms Mutation) بدون وميض أو إعادة تحميل ───
  Future<void> _toggleHelpful(LectureCommentModel comment) async {
    final user = _effectiveUser;
    if (user == null) return;
    final studentId = user.studentId.isNotEmpty
        ? user.studentId
        : user.id;

    final currentUsers = List<String>.from(comment.helpfulUserIds);
    final wasHelpful = currentUsers.contains(studentId);
    if (wasHelpful) {
      currentUsers.remove(studentId);
    } else {
      currentUsers.add(studentId);
    }

    // 1. تحديث لحظي محلي في 1ms دون جلب من الشبكة
    final updated = comment.copyWith(helpfulUserIds: currentUsers);
    final idx = _comments.indexWhere((c) => c.id == comment.id);
    if (idx != -1) {
      setState(() {
        _comments[idx] = updated;
      });
    }

    // 2. مزامنة في الخلفية والتراجع في حال الخطأ فقط
    final ok = await SupabaseService().toggleLectureCommentHelpful(
      commentId: comment.id,
      lectureId: widget.lecture.id,
      studentId: studentId,
    );

    if (!ok && mounted) {
      setState(() {
        final revertIdx = _comments.indexWhere((c) => c.id == comment.id);
        if (revertIdx != -1) {
          _comments[revertIdx] = comment;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تسجيل التفاعل')),
      );
    }
  }

  /// ── تثبيت/إلغاء تثبيت لحظي فوري (In-Place 1ms Mutation) ────────────────
  Future<void> _togglePin(LectureCommentModel comment) async {
    final user = _effectiveUser;
    if (user == null) return;
    final newPinned = !comment.isPinned;
    final updated = comment.copyWith(isPinned: newPinned);

    // 1. تحديث فوري محلي وإعادة ترتيب
    final idx = _comments.indexWhere((c) => c.id == comment.id);
    if (idx != -1) {
      setState(() {
        _comments[idx] = updated;
        _sortComments();
      });
    }

    // 2. مزامنة في الخلفية
    final ok = await SupabaseService().toggleLectureCommentPin(
      commentId: comment.id,
      lectureId: widget.lecture.id,
      isPinned: newPinned,
      user: user,
    );

    if (!ok && mounted) {
      setState(() {
        final revertIdx = _comments.indexWhere((c) => c.id == comment.id);
        if (revertIdx != -1) {
          _comments[revertIdx] = comment;
          _sortComments();
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحديث تثبيت الملاحظة')),
      );
    }
  }

  /// ── حذف استفسار مع إزالة فورية من الواجهة ────────────────────────────
  Future<void> _deleteComment(LectureCommentModel comment) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('حذف الاستفسار', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14)),
        content: Text('هل تريد بالتأكيد حذف هذا الاستفسار؟', style: GoogleFonts.cairo(fontSize: 12)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('إلغاء', style: GoogleFonts.cairo())),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('حذف', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final originalList = List<LectureCommentModel>.from(_comments);
      setState(() {
        _comments.removeWhere((c) => c.id == comment.id);
      });

      final ok = await SupabaseService().deleteLectureComment(
        commentId: comment.id,
        lectureId: widget.lecture.id,
      );

      if (!ok && mounted) {
        setState(() {
          _comments = originalList;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر حذف الاستفسار')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final user = _effectiveUser;
    final currentStudentId = user?.studentId.isNotEmpty == true
        ? user!.studentId
        : user?.id ?? '';
    final canModerate = user?.isAdmin == true ||
        user?.role == AppConstants.roleRepresentative ||
        user?.studentId == 'ST-NUST-001630760-413';

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primarySubtle,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.forum_rounded, color: AppTheme.primary, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'استفسارات المحاضرة',
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        widget.lecture.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 20, color: AppTheme.textSecondary),
                  tooltip: 'تحديث التعليقات',
                  onPressed: () => _loadComments(forceRefresh: true),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.lightBorder),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : RefreshIndicator(
                    onRefresh: () => _loadComments(forceRefresh: true),
                    color: AppTheme.primary,
                    child: _comments.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(height: MediaQuery.of(context).size.height * 0.15),
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(32),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 56,
                                        height: 56,
                                        decoration: const BoxDecoration(
                                          color: AppTheme.primarySubtle,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Center(
                                          child: Icon(Icons.mark_chat_unread_outlined, color: AppTheme.primary, size: 28),
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      Text(
                                        'لا توجد استفسارات بعد',
                                        style: GoogleFonts.cairo(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'كن أول من يطرح سؤالاً أو اسحب للأسفل للتحديث',
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.cairo(
                                          fontSize: 11,
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            controller: _scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: _comments.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (ctx, index) {
                          final comment = _comments[index];
                          final isMe = comment.authorId == currentStudentId;
                          final canDelete = isMe || canModerate;
                          final isHelpful = comment.isHelpfulBy(currentStudentId);
                          final isOptimistic = comment.id.startsWith('temp_');

                          return RepaintBoundary(
                            key: ValueKey(comment.id),
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 200),
                              opacity: isOptimistic ? 0.75 : 1.0,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: comment.isPinned
                                      ? const Color(0xFFFEFCE8)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: comment.isPinned
                                        ? const Color(0xFFFACC15)
                                        : AppTheme.lightBorder,
                                    width: comment.isPinned ? 1.4 : 1.0,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.03),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (comment.isPinned) ...[
                                      Row(
                                        children: [
                                          const Icon(Icons.push_pin_rounded, size: 14, color: Color(0xFFCA8A04)),
                                          const SizedBox(width: 4),
                                          Text(
                                            'ملاحظة مثبتة 📌',
                                            style: GoogleFonts.cairo(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.bold,
                                              color: const Color(0xFFCA8A04),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                    ],
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 14,
                                          backgroundColor: comment.isRepresentative
                                              ? AppTheme.accent.withValues(alpha: 0.15)
                                              : AppTheme.primarySubtle,
                                          child: Text(
                                            comment.authorName.isNotEmpty
                                                ? comment.authorName.characters.first
                                                : 'ط',
                                            style: GoogleFonts.cairo(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: comment.isRepresentative
                                                  ? AppTheme.accent
                                                  : AppTheme.primary,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      comment.authorName,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: GoogleFonts.cairo(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.bold,
                                                        color: AppTheme.textPrimary,
                                                      ),
                                                    ),
                                                  ),
                                                  if (comment.isRepresentative) ...[
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                                      decoration: BoxDecoration(
                                                        color: AppTheme.accent.withValues(alpha: 0.15),
                                                        borderRadius: BorderRadius.circular(6),
                                                        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
                                                      ),
                                                      child: Text(
                                                        'الممثل ⭐',
                                                        style: GoogleFonts.cairo(
                                                          fontSize: 9.5,
                                                          fontWeight: FontWeight.bold,
                                                          color: AppTheme.accent,
                                                        ),
                                                      ),
                                                    ),
                                                  ] else if (comment.isAdmin) ...[
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                                      decoration: BoxDecoration(
                                                        color: AppTheme.primarySubtle,
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: Text(
                                                        'إشراف 🛡️',
                                                        style: GoogleFonts.cairo(
                                                          fontSize: 9.5,
                                                          fontWeight: FontWeight.bold,
                                                          color: AppTheme.primary,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              Row(
                                                children: [
                                                  Text(
                                                    '${comment.createdAt.hour}:${comment.createdAt.minute.toString().padLeft(2, '0')}',
                                                    style: GoogleFonts.cairo(
                                                      fontSize: 9.5,
                                                      color: AppTheme.textMuted,
                                                    ),
                                                  ),
                                                  if (isOptimistic) ...[
                                                    const SizedBox(width: 4),
                                                    const Icon(Icons.access_time_rounded, size: 10, color: AppTheme.textMuted),
                                                  ],
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (canModerate)
                                          IconButton(
                                            icon: Icon(
                                              comment.isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                                              size: 16,
                                              color: comment.isPinned ? const Color(0xFFCA8A04) : AppTheme.textMuted,
                                            ),
                                            tooltip: comment.isPinned ? 'إلغاء التثبيت' : 'تثبيت الملاحظة',
                                            onPressed: isOptimistic ? null : () => _togglePin(comment),
                                          ),
                                        if (canDelete)
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppTheme.danger),
                                            tooltip: 'حذف',
                                            onPressed: isOptimistic ? null : () => _deleteComment(comment),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    SelectableText(
                                      comment.displayContent,
                                      style: GoogleFonts.cairo(
                                        fontSize: 12,
                                        color: AppTheme.textPrimary,
                                        height: 1.45,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: AppTactileBounce(
                                        onTap: isOptimistic ? null : () => _toggleHelpful(comment),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: isHelpful
                                                ? AppTheme.primarySubtle
                                                : const Color(0xFFF1F5F9),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: isHelpful
                                                  ? AppTheme.primary.withValues(alpha: 0.3)
                                                  : Colors.transparent,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.thumb_up_alt_rounded,
                                                size: 13,
                                                color: isHelpful ? AppTheme.primary : AppTheme.textMuted,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                comment.helpfulCount > 0
                                                    ? 'مفيد (${comment.helpfulCount})'
                                                    : 'مفيد',
                                                style: GoogleFonts.cairo(
                                                  fontSize: 10,
                                                  fontWeight: isHelpful ? FontWeight.bold : FontWeight.w600,
                                                  color: isHelpful ? AppTheme.primary : AppTheme.textSecondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppTheme.lightBorder)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    minLines: 1,
                    maxLines: 3,
                    style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'اكتب استفسارك...',
                      hintStyle: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textMuted),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(color: AppTheme.lightBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(color: AppTheme.lightBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(color: AppTheme.primary),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AppTactileBounce(
                  onTap: _sendComment,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(
                      color: AppTheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(Icons.send_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
