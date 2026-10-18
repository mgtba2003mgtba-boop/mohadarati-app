import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_theme.dart';

/// ويدجت استجابة فيزيائية ولمسية ناعمة (Tactile Spring Bounce Feedback)
/// يُعطي إحساساً فخماً بالأزرار والبطاقات مع ارتداد فيزيائي خفيف واهتزاز ناعم
class AppTactileBounce extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double lowerBound;
  final Duration duration;
  final bool enableHaptic;
  final bool enforceMinTouchTarget;
  final BorderRadius? borderRadius;

  const AppTactileBounce({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.lowerBound = 0.97,
    this.duration = const Duration(milliseconds: 130),
    this.enableHaptic = true,
    this.enforceMinTouchTarget = true,
    this.borderRadius,
  });

  @override
  State<AppTactileBounce> createState() => _AppTactileBounceState();
}

class _AppTactileBounceState extends State<AppTactileBounce>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      reverseDuration: widget.duration,
      lowerBound: 0.0,
      upperBound: 1.0,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: widget.lowerBound,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    if (widget.onTap != null || widget.onLongPress != null) {
      _controller.forward();
    }
  }

  void _onTapUp(TapUpDetails details) {
    if (widget.onTap != null || widget.onLongPress != null) {
      _controller.reverse();
    }
  }

  void _onTapCancel() {
    if (widget.onTap != null || widget.onLongPress != null) {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content = ScaleTransition(
      scale: _scaleAnimation,
      child: widget.child,
    );

    if (widget.enforceMinTouchTarget) {
      content = ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: AppTouchTarget.minSize,
          minHeight: AppTouchTarget.minSize,
        ),
        child: content,
      );
    }

    if (widget.onTap == null && widget.onLongPress == null) {
      return content;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: () {
        if (widget.enableHaptic) {
          HapticFeedback.lightImpact();
        }
        widget.onTap?.call();
      },
      onLongPress: () {
        if (widget.enableHaptic) {
          HapticFeedback.mediumImpact();
        }
        widget.onLongPress?.call();
      },
      child: content,
    );
  }
}
