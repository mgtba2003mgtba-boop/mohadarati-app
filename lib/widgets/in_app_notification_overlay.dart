import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/app_notification_service.dart';
import '../screens/announcements_screen.dart';

/// طبقة عائمة تعرض إشعارات فورية متدفقة أعلى الشاشة بنمط هواتف آيفون وأندرويد
class InAppNotificationOverlay extends StatefulWidget {
  final Widget child;

  const InAppNotificationOverlay({super.key, required this.child});

  @override
  State<InAppNotificationOverlay> createState() => _InAppNotificationOverlayState();
}

class _InAppNotificationOverlayState extends State<InAppNotificationOverlay>
    with SingleTickerProviderStateMixin {
  StreamSubscription<AppNotificationItem>? _subscription;
  AppNotificationItem? _currentItem;
  Timer? _dismissTimer;

  late final AnimationController _animController;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_animController);

    _subscription = AppNotificationService.instance.notificationStream.listen((item) {
      _showNotification(item);
    });
  }

  void _showNotification(AppNotificationItem item) {
    _dismissTimer?.cancel();
    setState(() {
      _currentItem = item;
    });

    _animController.forward(from: 0.0);

    // إخفاء تلقائي بعد 5.5 ثوانٍ
    _dismissTimer = Timer(const Duration(milliseconds: 5500), () {
      _hideNotification();
    });
  }

  void _hideNotification() {
    _dismissTimer?.cancel();
    _animController.reverse().then((_) {
      if (mounted) {
        setState(() {
          _currentItem = null;
        });
      }
    });
  }

  void _onNotificationTapped() {
    final item = _currentItem;
    _hideNotification();

    if (item == null) return;

    if (item.type == AppNotificationType.announcement) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AnnouncementsScreen()),
      );
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _subscription?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_currentItem != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: SlideTransition(
                  position: _slideAnimation,
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: Dismissible(
                      key: ValueKey(_currentItem!.id),
                      direction: DismissDirection.up,
                      onDismissed: (_) => _hideNotification(),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _onNotificationTapped,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFF38BDF8).withValues(alpha: 0.4),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.35),
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: _currentItem!.type == AppNotificationType.announcement
                                        ? const Color(0xFF0284C7)
                                        : const Color(0xFF4F46E5),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    _currentItem!.type == AppNotificationType.announcement
                                        ? Icons.campaign_rounded
                                        : Icons.menu_book_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _currentItem!.title,
                                        style: GoogleFonts.cairo(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: const Color(0xFF38BDF8),
                                        ),
                                      ),
                                      Text(
                                        _currentItem!.message,
                                        style: GoogleFonts.cairo(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                          height: 1.3,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                IconButton(
                                  icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 18),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: _hideNotification,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
