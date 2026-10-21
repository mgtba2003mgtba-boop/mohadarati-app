import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../models/app_user_model.dart';
import '../models/lecture_model.dart';
import '../models/announcement_model.dart';
import '../models/student_model.dart';
import '../services/supabase_service.dart';
import 'app_tactile_bounce.dart';
import 'app_network_image.dart';
import 'app_fullscreen_modal.dart';

/// ── تبويب دليل وإدارة الطلاب وممثلي الشعب (صلاحيات المشرف العام) ───────────
class DashboardRepsDirectoryTab extends StatefulWidget {
  final List<AppUserModel> allUsers;
  final List<LectureModel> allLectures;
  final List<AnnouncementModel> allAnnouncements;
  final AppUserModel? currentUser;
  final VoidCallback onUsersUpdated;
  final void Function(String message, {bool isError})? onShowSnackbar;

  const DashboardRepsDirectoryTab({
    super.key,
    required this.allUsers,
    required this.allLectures,
    required this.allAnnouncements,
    required this.currentUser,
    required this.onUsersUpdated,
    this.onShowSnackbar,
  });

  @override
  State<DashboardRepsDirectoryTab> createState() => _DashboardRepsDirectoryTabState();
}

class _DashboardRepsDirectoryTabState extends State<DashboardRepsDirectoryTab> {
  final Map<String, String?> _photoCache = {};
  final Set<String> _pendingPhotoRequests = {};

  Future<void> _resolveStudentPhoto(String studentId) async {
    if (studentId.isEmpty || _pendingPhotoRequests.contains(studentId)) return;
    _pendingPhotoRequests.add(studentId);

    try {
      final res = await SupabaseService().attendanceClient
          .from('students')
          .select('photo_url')
          .eq('id', studentId)
          .maybeSingle();

      final rawUrl = res?['photo_url']?.toString();
      final url = (rawUrl != null && rawUrl.trim().isNotEmpty)
          ? rawUrl.trim()
          : (studentId.startsWith('ST-NUST-')
              ? 'https://f004.backblazeb2.com/file/mujtaba-student-photos/$studentId.jpg'
              : null);
      _photoCache[studentId] = url;
      if (mounted && url != null && url.isNotEmpty) {
        setState(() {});
      }
    } catch (_) {
      _photoCache[studentId] = null;
    } finally {
      _pendingPhotoRequests.remove(studentId);
    }
  }

  Widget _buildStudentAvatar(AppUserModel rep, Color avatarColor, {double size = 48}) {
    final photo = (rep.photoUrl != null && rep.photoUrl!.trim().isNotEmpty)
        ? rep.photoUrl
        : _photoCache[rep.studentId];
    final bool hasValidPhoto = photo != null && photo.trim().isNotEmpty;

    if (!hasValidPhoto && !_photoCache.containsKey(rep.studentId)) {
      _resolveStudentPhoto(rep.studentId);
    }

    return GestureDetector(
      onTap: hasValidPhoto
          ? () {
              AppFullscreenModal.show(
                context: context,
                title: rep.name,
                subtitle: '${rep.studentId} • ${rep.department} • ${rep.stage} (${rep.section ?? "غير محدد"})',
                imageUrl: photo,
              );
            }
          : null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: avatarColor.withValues(alpha: 0.12),
              border: Border.all(
                color: hasValidPhoto ? AppTheme.accent : avatarColor.withValues(alpha: 0.35),
                width: hasValidPhoto ? 2 : 1,
              ),
              boxShadow: hasValidPhoto
                  ? [
                      BoxShadow(
                        color: AppTheme.accent.withValues(alpha: 0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: ClipOval(
              child: hasValidPhoto
                  ? AppNetworkImage(
                      imageUrl: photo,
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                      errorWidget: Center(
                        child: Text(
                          rep.name.isNotEmpty ? rep.name[0] : 'S',
                          style: GoogleFonts.cairo(
                            fontWeight: FontWeight.bold,
                            fontSize: size * 0.4,
                            color: avatarColor,
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        rep.name.isNotEmpty ? rep.name[0] : 'S',
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.bold,
                          fontSize: size * 0.4,
                          color: avatarColor,
                        ),
                      ),
                    ),
            ),
          ),
          if (hasValidPhoto)
            Positioned(
              bottom: -1,
              right: -1,
              child: Container(
                padding: const EdgeInsets.all(1.5),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Container(
                  width: size * 0.25,
                  height: size * 0.25,
                  decoration: const BoxDecoration(
                    color: Color(0xFF10B981),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
  String _repDeptFilter = 'ALL';
  String _repSearchQuery = '';
  String _userDirectoryRoleFilter = 'ALL'; // 'ALL', 'REPS', 'STUDENTS'
  String _userDirectoryStageFilter = 'ALL';
  int _directoryDisplayLimit = 50;

  // إدارة شعب نظام البصمة
  String _selectedRepDept = AppConstants.departments.first;
  String _selectedRepStage = AppConstants.stages.first;
  String _selectedRepSection = 'A';
  List<String> _availableBiometricSections = ['A', 'B', 'C', 'D'];
  bool _isLoadingSections = false;

  List<AppUserModel> get _representatives =>
      widget.allUsers.where((u) => u.isRepresentative || u.canPublishLectures || u.canPublishAnnouncements).toList();

  @override
  void initState() {
    super.initState();
    _loadBiometricSections();
  }

  Future<void> _loadBiometricSections() async {
    setState(() => _isLoadingSections = true);
    final list = await SupabaseService().fetchBiometricSections(
      department: _selectedRepDept,
      stage: _selectedRepStage,
    );
    if (mounted) {
      setState(() {
        _availableBiometricSections = list;
        if (!_availableBiometricSections.contains(_selectedRepSection)) {
          _selectedRepSection = _availableBiometricSections.isNotEmpty ? _availableBiometricSections.first : 'A';
        }
        _isLoadingSections = false;
      });
    }
  }

  void _showAssignBiometricRepDialog({
    required String department,
    required String stage,
    required String section,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => _AssignBiometricRepDialog(
        department: department,
        stage: stage,
        section: section,
        allUsers: widget.allUsers,
        onSuccess: () {
          widget.onUsersUpdated();
          _loadBiometricSections();
        },
      ),
    );
  }

  void _showPromoteDialog(AppUserModel user) {
    String selectedRole = user.role;
    bool canLectures = user.canPublishLectures;
    bool canAnnouncements = user.canPublishAnnouncements;
    int selectedSemester = user.semester;
    final selectedSectionsSet = user.assignedSections.toSet();
    final sectionController = TextEditingController(
      text: selectedSectionsSet.isNotEmpty
          ? (selectedSectionsSet.toList()..sort()).join(', ')
          : (user.section ?? ''),
    );

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(
                'ترقية وإدارة صلاحيات: ${user.name}',
                style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'المعرف: ${user.studentId} • ${user.department}',
                      style: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFF94A3B8)),
                    ),
                    const Divider(color: AppTheme.lightBorder, height: 20),

                    Text('الدور والصلاحية الأكاديمية:', style: GoogleFonts.cairo(fontSize: 13, color: AppTheme.textPrimary)),
                    const SizedBox(height: 8),

                    _buildRoleRadio(
                      title: 'طالب (Student)',
                      subtitle: 'صلاحيات قراءة فقط',
                      roleValue: AppConstants.roleStudent,
                      groupValue: selectedRole,
                      onChanged: (val) {
                        setDialogState(() {
                          selectedRole = val!;
                          canLectures = false;
                          canAnnouncements = false;
                        });
                      },
                    ),
                    _buildRoleRadio(
                      title: 'ممثل الشعبة ⭐ (Representative)',
                      subtitle: 'صلاحيات نشر المحاضرات والتبليغات لشعبته فقط',
                      roleValue: AppConstants.roleRepresentative,
                      groupValue: selectedRole,
                      onChanged: (val) {
                        setDialogState(() {
                          selectedRole = val!;
                          canLectures = true;
                          canAnnouncements = true;
                        });
                      },
                    ),
                    _buildRoleRadio(
                      title: 'مشرف عام 🛡️ (Admin)',
                      subtitle: 'صلاحيات كاملة وغير مقيدة في كافة الأقسام والمراحل',
                      roleValue: AppConstants.roleAdmin,
                      groupValue: selectedRole,
                      onChanged: (val) {
                        setDialogState(() {
                          selectedRole = val!;
                          canLectures = true;
                          canAnnouncements = true;
                        });
                      },
                    ),

                    const Divider(color: AppTheme.lightBorder, height: 24),

                    Text('الشُعب المكلّف بإدارتها:', style: GoogleFonts.cairo(fontSize: 13, color: AppTheme.textPrimary)),
                    const SizedBox(height: 4),
                    Text(
                      'يمكن تعيين شعبة واحدة أو أكثر للممثل (مثال: A أو A, B)',
                      style: GoogleFonts.cairo(fontSize: 10, color: const Color(0xFF94A3B8)),
                    ),
                    const SizedBox(height: 8),

                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: ['A', 'B', 'C', 'D', 'E', 'ALL'].map((sec) {
                        final isSelected = selectedSectionsSet.contains(sec);
                        return FilterChip(
                          label: Text(
                            sec == 'ALL' ? 'كافة الشُعب' : 'شعبة $sec',
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? Colors.white : AppTheme.textPrimary,
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: AppTheme.primary,
                          backgroundColor: Colors.white,
                          checkmarkColor: Colors.white,
                          onSelected: (selected) {
                            setDialogState(() {
                              if (sec == 'ALL') {
                                if (selected) {
                                  selectedSectionsSet.clear();
                                  selectedSectionsSet.add('ALL');
                                } else {
                                  selectedSectionsSet.remove('ALL');
                                }
                              } else {
                                selectedSectionsSet.remove('ALL');
                                if (selected) {
                                  selectedSectionsSet.add(sec);
                                } else {
                                  selectedSectionsSet.remove(sec);
                                }
                              }
                              sectionController.text = (selectedSectionsSet.toList()..sort()).join(', ');
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),

                    TextField(
                      controller: sectionController,
                      style: GoogleFonts.cairo(fontSize: 12),
                      decoration: InputDecoration(
                        labelText: 'الشُعب المحددة نصياً',
                        labelStyle: GoogleFonts.cairo(fontSize: 11),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (val) {
                        final list = val.split(RegExp(r'[,،/\s]+')).map((s) => s.trim().toUpperCase()).where((s) => s.isNotEmpty);
                        selectedSectionsSet.clear();
                        selectedSectionsSet.addAll(list);
                      },
                    ),

                    const Divider(color: AppTheme.lightBorder, height: 24),

                    Text('الفصل الدراسي:', style: GoogleFonts.cairo(fontSize: 13, color: AppTheme.textPrimary)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: Center(child: Text('الفصل الأول (1)', style: GoogleFonts.cairo(fontSize: 11))),
                            selected: selectedSemester == 1,
                            onSelected: (s) {
                              if (s) setDialogState(() => selectedSemester = 1);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: Center(child: Text('الفصل الثاني (2)', style: GoogleFonts.cairo(fontSize: 11))),
                            selected: selectedSemester == 2,
                            onSelected: (s) {
                              if (s) setDialogState(() => selectedSemester = 2);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('إلغاء', style: GoogleFonts.cairo(color: const Color(0xFF94A3B8))),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final finalSection = sectionController.text.trim();
                    final okRole = await SupabaseService().updateUserRole(
                      studentId: user.studentId,
                      role: selectedRole,
                      canPublishLectures: canLectures,
                      canPublishAnnouncements: canAnnouncements,
                      section: finalSection.isNotEmpty ? finalSection : null,
                    );
                    if (selectedSemester != user.semester) {
                      await SupabaseService().updateUserSemester(
                        studentId: user.studentId,
                        semester: selectedSemester,
                      );
                    }
                    if (okRole) {
                      widget.onShowSnackbar?.call('تم تحديث صلاحيات ${user.name} بنجاح');
                      widget.onUsersUpdated();
                    } else {
                      widget.onShowSnackbar?.call('حدث خطأ أثناء تعديل الصلاحيات', isError: true);
                    }
                  },
                  child: Text('حفظ التعديل', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showBatchPromotionDialog() {
    String selectedDept = _repDeptFilter != 'ALL' ? _repDeptFilter : AppConstants.departments.first;
    String selectedStage = _userDirectoryStageFilter != 'ALL' ? _userDirectoryStageFilter : AppConstants.stages.first;
    int targetSemester = 2;
    bool isProcessing = false;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final matchingStudents = widget.allUsers.where((u) {
              final deptMatch = u.department == selectedDept || u.department.contains(selectedDept);
              final stageMatch = AppConstants.normalizeStage(u.stage) == AppConstants.normalizeStage(selectedStage);
              return deptMatch && stageMatch;
            }).toList();

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primarySubtle,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.school_rounded, color: AppTheme.primary, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'ترقية دفعة إلى الفصل الدراسي',
                      style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'اختر القسم والمرحلة المستهدفة لتحويل جميع طلابها دفعة واحدة إلى الفصل الدراسي المطلوب:',
                      style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 14),

                    DropdownButtonFormField<String>(
                      value: selectedDept,
                      dropdownColor: Colors.white,
                      style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'القسم الأكاديمي',
                        labelStyle: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textSecondary),
                        filled: true,
                        fillColor: AppTheme.lightSurface,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      items: AppConstants.departments.map((d) {
                        return DropdownMenuItem(value: d, child: Text(d, style: GoogleFonts.cairo(fontSize: 12)));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedDept = val);
                      },
                    ),
                    const SizedBox(height: 10),

                    DropdownButtonFormField<String>(
                      value: selectedStage,
                      dropdownColor: Colors.white,
                      style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'المرحلة',
                        labelStyle: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textSecondary),
                        filled: true,
                        fillColor: AppTheme.lightSurface,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      items: AppConstants.stages.map((s) {
                        return DropdownMenuItem(value: s, child: Text(s, style: GoogleFonts.cairo(fontSize: 12)));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedStage = val);
                      },
                    ),
                    const SizedBox(height: 12),

                    Text(
                      'الفصل الدراسي المستهدف:',
                      style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: Center(
                              child: Text(
                                'الفصل الثاني (2)',
                                style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.bold,
                                  color: targetSemester == 2 ? Colors.white : AppTheme.textPrimary,
                                ),
                              ),
                            ),
                            selected: targetSemester == 2,
                            selectedColor: AppTheme.primary,
                            onSelected: (s) {
                              if (s) setDialogState(() => targetSemester = 2);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: Center(
                              child: Text(
                                'الفصل الأول (1)',
                                style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.bold,
                                  color: targetSemester == 1 ? Colors.white : AppTheme.textPrimary,
                                ),
                              ),
                            ),
                            selected: targetSemester == 1,
                            selectedColor: AppTheme.primary,
                            onSelected: (s) {
                              if (s) setDialogState(() => targetSemester = 1);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF86EFAC)),
                      ),
                      child: Text(
                        'سيتم تطبيق الترقية على ${matchingStudents.length} طالب مسجل في هذه المرحلة والقسم.',
                        style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF15803D)),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isProcessing ? null : () => Navigator.pop(dialogCtx),
                  child: Text('إلغاء', style: GoogleFonts.cairo(color: AppTheme.textSecondary)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: isProcessing ? null : () async {
                    setDialogState(() => isProcessing = true);
                    final success = await SupabaseService().batchUpdateSemester(
                      department: selectedDept,
                      stage: selectedStage,
                      semester: targetSemester,
                    );
                    if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                    if (success) {
                      widget.onShowSnackbar?.call('تمت ترقية الدفعة بنجاح إلى الفصل $targetSemester');
                      widget.onUsersUpdated();
                    } else {
                      widget.onShowSnackbar?.call('حدث خطأ أثناء ترقية الدفعة', isError: true);
                    }
                  },
                  child: isProcessing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('تنفيذ الترقية الآن 🚀', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDemoteRep(AppUserModel rep) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('سحب تكليف الممثل', style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.bold)),
        content: Text('هل أنت متأكد من سحب صفة الممثل عن الطالب (${rep.name}) وإعادته كطالب عادي؟', style: GoogleFonts.cairo(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('إلغاء', style: GoogleFonts.cairo(color: AppTheme.textSecondary))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('تأكيد السحب', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await SupabaseService().updateUserRole(
        studentId: rep.studentId,
        role: AppConstants.roleStudent,
        canPublishLectures: false,
        canPublishAnnouncements: false,
      );
      if (success) {
        widget.onShowSnackbar?.call('تم سحب صفة الممثل بنجاح');
        widget.onUsersUpdated();
        _loadBiometricSections();
      }
    }
  }

  Widget _buildRoleRadio({
    required String title,
    required String subtitle,
    required String roleValue,
    required String groupValue,
    required ValueChanged<String?> onChanged,
  }) {
    final isSelected = roleValue == groupValue;
    return GestureDetector(
      onTap: () => onChanged(roleValue),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primarySubtle : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? AppTheme.primary : AppTheme.lightBorder),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              color: isSelected ? AppTheme.primary : const Color(0xFF94A3B8),
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.cairo(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                  Text(subtitle, style: GoogleFonts.cairo(fontSize: 10, color: const Color(0xFF94A3B8))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRepCard(AppUserModel rep) {
    final bool isRep = rep.isRepresentative || rep.canPublishLectures || rep.canPublishAnnouncements;
    final bool isAdmin = rep.isAdmin;

    Color avatarColor = AppTheme.primaryLight;
    if (isAdmin) {
      avatarColor = Colors.greenAccent;
    } else if (isRep) {
      avatarColor = AppTheme.accent;
    }

    final lecturesCount = widget.allLectures.where((l) => l.uploaderId == rep.studentId).length;
    final announcesCount = widget.allAnnouncements.where((a) => a.authorId == rep.studentId).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAdmin
              ? Colors.greenAccent.withValues(alpha: 0.5)
              : (isRep ? AppTheme.accent.withValues(alpha: 0.4) : AppTheme.lightBorder),
          width: isAdmin || isRep ? 1.5 : 1.0,
        ),
        boxShadow: AppShadows.subtle,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStudentAvatar(rep, avatarColor, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            rep.name,
                            style: GoogleFonts.cairo(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: avatarColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: avatarColor.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            isAdmin ? 'مشرف عام 🛡️' : (isRep ? 'ممثل الشعبة ⭐' : 'طالب 🎓'),
                            style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.bold, color: avatarColor),
                          ),
                        ),
                        const SizedBox(width: 6),
                        AppTactileBounce(
                          lowerBound: 0.92,
                          onTap: () async {
                            final nextSemester = rep.semester == 1 ? 2 : 1;
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                title: Text('تحويل الفصل الدراسي', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 15)),
                                content: Text(
                                  'هل تريد تحويل الطالب (${rep.name}) إلى الفصل الدراسي ${nextSemester == 2 ? "الثاني" : "الأول"}؟',
                                  style: GoogleFonts.cairo(fontSize: 13),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: Text('إلغاء', style: GoogleFonts.cairo(color: AppTheme.textSecondary)),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.primary,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: Text('تأكيد التحويل', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              final success = await SupabaseService().updateUserSemester(
                                studentId: rep.studentId,
                                semester: nextSemester,
                              );
                              if (success) {
                                widget.onUsersUpdated();
                                widget.onShowSnackbar?.call('تم تحويل ${rep.name} إلى الفصل $nextSemester بنجاح');
                              }
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: rep.semester == 2 ? const Color(0xFFF0FDF4) : const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: rep.semester == 2 ? const Color(0xFF86EFAC) : const Color(0xFFBFDBFE),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.swap_horiz_rounded,
                                  size: 13,
                                  color: rep.semester == 2 ? const Color(0xFF16A34A) : AppTheme.primary,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  'ف${rep.semester}',
                                  style: GoogleFonts.cairo(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: rep.semester == 2 ? const Color(0xFF16A34A) : AppTheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Text(
                          rep.studentId,
                          style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                        ),
                        Text('•', style: GoogleFonts.cairo(fontSize: 10, color: const Color(0xFFCBD5E1))),
                        Text(
                          rep.department,
                          style: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFF64748B)),
                        ),
                        Text('•', style: GoogleFonts.cairo(fontSize: 10, color: const Color(0xFFCBD5E1))),
                        Text(
                          rep.stage,
                          style: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFF64748B)),
                        ),
                        Text('•', style: GoogleFonts.cairo(fontSize: 10, color: const Color(0xFFCBD5E1))),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppTheme.lightSurface,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppTheme.lightBorder),
                          ),
                          child: Text(
                            'شعبة (${rep.section ?? "غير محدد"})',
                            style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primary),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.lightSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.lightBorder),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.menu_book_rounded, size: 14, color: AppTheme.primary),
                      const SizedBox(width: 4),
                      Text('محاضرات: $lecturesCount', style: GoogleFonts.cairo(fontSize: 10.5, color: AppTheme.textSecondary)),
                      const SizedBox(width: 10),
                      const Icon(Icons.campaign_rounded, size: 14, color: AppTheme.accent),
                      const SizedBox(width: 4),
                      Text('تبليغات: $announcesCount', style: GoogleFonts.cairo(fontSize: 10.5, color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.manage_accounts_rounded, color: AppTheme.primary, size: 20),
                  tooltip: 'إدارة الصلاحيات والترقية',
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                  onPressed: () => _showPromoteDialog(rep),
                ),
                if (isRep && !isAdmin) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.person_remove_rounded, color: AppTheme.danger, size: 18),
                    tooltip: 'سحب التكليف',
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(4),
                    onPressed: () => _confirmDemoteRep(rep),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.allUsers.where((user) {
      if (_userDirectoryRoleFilter == 'REPS') {
        if (!user.isRepresentative && !user.canPublishLectures && !user.canPublishAnnouncements) return false;
      } else if (_userDirectoryRoleFilter == 'STUDENTS') {
        if (!user.isStudent) return false;
      }

      final matchDept = _repDeptFilter == 'ALL' || user.department.contains(_repDeptFilter) || _repDeptFilter.contains(user.department);
      final matchStage = _userDirectoryStageFilter == 'ALL' ||
          AppConstants.normalizeStage(user.stage) == AppConstants.normalizeStage(_userDirectoryStageFilter);
      final q = _repSearchQuery.trim().toLowerCase();
      final matchSearch = q.isEmpty ||
          user.name.toLowerCase().contains(q) ||
          user.studentId.toLowerCase().contains(q) ||
          (user.section != null && user.section!.toLowerCase().contains(q)) ||
          user.department.toLowerCase().contains(q);
      return matchDept && matchStage && matchSearch;
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // بطاقة إدارة وتكليف ممثلي الشُعب
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.primary.withValues(alpha: 0.15),
                Colors.white,
              ],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.fingerprint_rounded, color: AppTheme.accent, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'إدارة وتكليف ممثلي الشُعب (نظام البصمة)',
                          style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                        Text(
                          'اختر القسم والمرحلة والشعبة لتعيين الممثل المعتمد من قاعدة بيانات البصمة',
                          style: GoogleFonts.cairo(fontSize: 10, color: const Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<String>(
                      value: _selectedRepDept,
                      dropdownColor: Colors.white,
                      style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'القسم الأكاديمي',
                        labelStyle: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textSecondary),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      items: AppConstants.departments.map((d) => DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedRepDept = val);
                          _loadBiometricSections();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      value: _selectedRepStage,
                      dropdownColor: Colors.white,
                      style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'المرحلة',
                        labelStyle: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textSecondary),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      items: AppConstants.stages.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedRepStage = val);
                          _loadBiometricSections();
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              Text(
                'شُعب المرحلة المعتمدة بالبصمة:',
                style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFFCBD5E1)),
              ),
              const SizedBox(height: 6),
              _isLoadingSections
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent))),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _availableBiometricSections.map((sec) {
                          final isSel = _selectedRepSection == sec;
                          final repCount = widget.allUsers.where((u) =>
                            u.isRepresentative &&
                            u.department == _selectedRepDept &&
                            AppConstants.normalizeStage(u.stage) == AppConstants.normalizeStage(_selectedRepStage) &&
                            u.hasSectionAccess(sec)
                          ).length;

                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(
                                'شعبة ($sec) ${repCount > 0 ? "★ ($repCount)" : ""}',
                                style: GoogleFonts.cairo(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isSel ? Colors.black : (repCount > 0 ? AppTheme.accent : const Color(0xFF94A3B8)),
                                ),
                              ),
                              selected: isSel,
                              selectedColor: AppTheme.accent,
                              backgroundColor: Colors.white,
                              side: BorderSide(color: isSel ? AppTheme.accent : AppTheme.lightBorder),
                              onSelected: (s) {
                                if (s) setState(() => _selectedRepSection = sec);
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),

              const Divider(color: AppTheme.lightBorder, height: 24),

              Builder(
                builder: (context) {
                  final currentReps = widget.allUsers.where((u) =>
                    u.isRepresentative &&
                    u.department == _selectedRepDept &&
                    AppConstants.normalizeStage(u.stage) == AppConstants.normalizeStage(_selectedRepStage) &&
                    u.hasSectionAccess(_selectedRepSection)
                  ).toList();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'ممثلو شعبة ($_selectedRepSection):',
                            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.accent),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.accent,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.black, size: 16),
                            label: Text(
                              'تكليف ممثل للشعبة ⭐',
                              style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
                            ),
                            onPressed: () => _showAssignBiometricRepDialog(
                              department: _selectedRepDept,
                              stage: _selectedRepStage,
                              section: _selectedRepSection,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      if (currentReps.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.lightBorder),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline_rounded, color: Color(0xFF94A3B8), size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'لا يوجد ممثل مكلف حالياً لشعبة ($_selectedRepSection). انقر على "تكليف ممثل للشعبة" لاختيار طالب من نظام البصمة.',
                                  style: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFF94A3B8)),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Column(
                          children: currentReps.map((rep) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                children: [
                                  _buildStudentAvatar(rep, AppTheme.accent, size: 36),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          rep.name,
                                          style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                        ),
                                        Text(
                                          '${rep.studentId} • مكلف بالشُعب: ${rep.sectionsDisplayLabel}',
                                          style: GoogleFonts.cairo(fontSize: 10, color: const Color(0xFF94A3B8)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit_note_rounded, color: AppTheme.accent, size: 18),
                                    tooltip: 'تعديل الصلاحيات',
                                    onPressed: () => _showPromoteDialog(rep),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.person_remove_rounded, color: AppTheme.danger, size: 18),
                                    tooltip: 'سحب التكليف',
                                    onPressed: () => _confirmDemoteRep(rep),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // رأس دليل الطلاب
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'دليل الطلاب والمسجلين في التطبيق',
                    style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                  Text(
                    '${filtered.length} مستخدم معروض من إجمالي ${widget.allUsers.length} طالب',
                    style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.accent),
                  ),
                ],
              ),
            ),
            AppTactileBounce(
              lowerBound: 0.92,
              onTap: _showBatchPromotionDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.primary, Color(0xFF6366F1)],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: AppShadows.subtle,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.school_rounded, color: Colors.white, size: 15),
                    const SizedBox(width: 5),
                    Text(
                      'ترقية دفعة إلى الفصل 2 🎓',
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ChoiceChip(
                label: Text('جميع المسجلين (${widget.allUsers.length})'),
                selected: _userDirectoryRoleFilter == 'ALL',
                onSelected: (s) => setState(() => _userDirectoryRoleFilter = 'ALL'),
                selectedColor: AppTheme.accent,
                labelStyle: GoogleFonts.cairo(
                  color: _userDirectoryRoleFilter == 'ALL' ? Colors.black : const Color(0xFF94A3B8),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: Text('ممثلو الشعب ⭐ (${_representatives.length})'),
                selected: _userDirectoryRoleFilter == 'REPS',
                onSelected: (s) => setState(() => _userDirectoryRoleFilter = 'REPS'),
                selectedColor: AppTheme.accent,
                labelStyle: GoogleFonts.cairo(
                  color: _userDirectoryRoleFilter == 'REPS' ? Colors.black : const Color(0xFF94A3B8),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: Text('الطلبة فقط 🎓 (${widget.allUsers.where((u) => u.isStudent).length})'),
                selected: _userDirectoryRoleFilter == 'STUDENTS',
                onSelected: (s) => setState(() => _userDirectoryRoleFilter = 'STUDENTS'),
                selectedColor: AppTheme.accent,
                labelStyle: GoogleFonts.cairo(
                  color: _userDirectoryRoleFilter == 'STUDENTS' ? Colors.black : const Color(0xFF94A3B8),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        TextField(
          style: GoogleFonts.cairo(color: AppTheme.textPrimary, fontSize: 13),
          onChanged: (val) => setState(() => _repSearchQuery = val),
          decoration: InputDecoration(
            hintText: 'ابحث بالاسم، المعرف الجامعي (ST-...)، الشعبة، أو القسم...',
            hintStyle: GoogleFonts.cairo(color: const Color(0xFF64748B), fontSize: 12),
            prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.accent, size: 20),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppTheme.lightBorder),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
        ),
        const SizedBox(height: 10),

        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('كافة الأقسام'),
                selected: _repDeptFilter == 'ALL',
                onSelected: (s) => setState(() => _repDeptFilter = 'ALL'),
                selectedColor: AppTheme.primaryLight,
                labelStyle: GoogleFonts.cairo(
                  color: _repDeptFilter == 'ALL' ? Colors.white : const Color(0xFF94A3B8),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              ...AppConstants.departments.map((dept) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(dept),
                    selected: _repDeptFilter == dept,
                    onSelected: (s) => setState(() => _repDeptFilter = s ? dept : 'ALL'),
                    selectedColor: AppTheme.primaryLight,
                    labelStyle: GoogleFonts.cairo(
                      color: _repDeptFilter == dept ? Colors.white : const Color(0xFF94A3B8),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 8),

        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('كافة المراحل'),
                selected: _userDirectoryStageFilter == 'ALL',
                onSelected: (s) => setState(() => _userDirectoryStageFilter = 'ALL'),
                selectedColor: AppTheme.primaryLight,
                labelStyle: GoogleFonts.cairo(
                  color: _userDirectoryStageFilter == 'ALL' ? Colors.white : const Color(0xFF94A3B8),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              ...AppConstants.stages.map((stage) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(stage),
                    selected: _userDirectoryStageFilter == stage,
                    onSelected: (s) => setState(() => _userDirectoryStageFilter = s ? stage : 'ALL'),
                    selectedColor: AppTheme.primaryLight,
                    labelStyle: GoogleFonts.cairo(
                      color: _userDirectoryStageFilter == stage ? Colors.white : const Color(0xFF94A3B8),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 14),

        if (filtered.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.lightBorder)),
            child: Center(child: Text('لم يتم العثور على طلاب أو ممثلين مطابقين للبحث', style: GoogleFonts.cairo(color: AppTheme.textMuted, fontSize: 13))),
          )
        else ...[
          ...filtered.take(_directoryDisplayLimit).map((user) => _buildRepCard(user)),
          if (filtered.length > _directoryDisplayLimit)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () => setState(() => _directoryDisplayLimit += 50),
                child: Text('عرض المزيد (${filtered.length - _directoryDisplayLimit} طالب إضافي)', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ],
    );
  }
}

/// نافذة اختيار وتكليف ممثل من نظام البصمة
class _AssignBiometricRepDialog extends StatefulWidget {
  final String department;
  final String stage;
  final String section;
  final List<AppUserModel> allUsers;
  final VoidCallback onSuccess;

  const _AssignBiometricRepDialog({
    required this.department,
    required this.stage,
    required this.section,
    required this.allUsers,
    required this.onSuccess,
  });

  @override
  State<_AssignBiometricRepDialog> createState() => _AssignBiometricRepDialogState();
}

class _AssignBiometricRepDialogState extends State<_AssignBiometricRepDialog> {
  bool _isLoading = true;
  List<StudentModel> _students = [];
  String _search = '';
  StudentModel? _selectedStudent;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _fetchStudents();
  }

  Future<void> _fetchStudents() async {
    try {
      final res = await SupabaseService().attendanceClient
          .from('students')
          .select('*')
          .eq('department', widget.department)
          .eq('stage', widget.stage)
          .eq('section', widget.section)
          .order('name');

      if (mounted) {
        setState(() {
          _students = (res as List).map((i) => StudentModel.fromJson(i)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _students.where((s) {
      final q = _search.trim().toLowerCase();
      if (q.isEmpty) return true;
      return s.name.toLowerCase().contains(q) || s.id.toLowerCase().contains(q);
    }).toList();

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text('تكليف ممثل لشعبة (${widget.section})', style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            TextField(
              decoration: InputDecoration(
                hintText: 'بحث باسم الطالب أو المعرف...',
                prefixIcon: const Icon(Icons.search, size: 18),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? Center(child: Text('لا يوجد طلاب في هذه الشعبة', style: GoogleFonts.cairo(fontSize: 12)))
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) {
                            final s = filtered[i];
                            final isSel = _selectedStudent?.id == s.id;
                            return ListTile(
                              selected: isSel,
                              selectedTileColor: AppTheme.primarySubtle,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              leading: ClipOval(
                                child: s.photoUrl != null && s.photoUrl!.isNotEmpty
                                    ? AppNetworkImage(
                                        imageUrl: s.photoUrl!,
                                        width: 38,
                                        height: 38,
                                        fit: BoxFit.cover,
                                        errorWidget: CircleAvatar(
                                          radius: 19,
                                          backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                                          child: Text(s.name.isNotEmpty ? s.name[0] : 'S'),
                                        ),
                                      )
                                    : CircleAvatar(
                                        radius: 19,
                                        backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                                        child: Text(s.name.isNotEmpty ? s.name[0] : 'S'),
                                      ),
                              ),
                              title: Text(s.name, style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold)),
                              subtitle: Text('${s.id} • ${s.hasFace ? "بصمة وجه معتمدة ✓" : "بدون بصمة"}', style: GoogleFonts.cairo(fontSize: 10)),
                              trailing: isSel ? const Icon(Icons.check_circle, color: AppTheme.primary) : null,
                              onTap: () => setState(() => _selectedStudent = s),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('إلغاء', style: GoogleFonts.cairo())),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          onPressed: _selectedStudent == null || _isSaving
              ? null
              : () async {
                  setState(() => _isSaving = true);
                  final ok = await SupabaseService().updateUserRole(
                    studentId: _selectedStudent!.id,
                    role: AppConstants.roleRepresentative,
                    canPublishLectures: true,
                    canPublishAnnouncements: true,
                    section: widget.section,
                    stage: widget.stage,
                    department: widget.department,
                  );
                  if (context.mounted) Navigator.pop(context);
                  if (ok) {
                    widget.onSuccess();
                  }
                },
          child: _isSaving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Text('تأكيد التكليف ⭐', style: GoogleFonts.cairo(color: Colors.white)),
        ),
      ],
    );
  }
}
