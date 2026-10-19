import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants/app_constants.dart';

/// ويدجت ذكي وموحد لعرض الصور السحابية بدون مشاكل CORS
class AppNetworkImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? errorWidget;
  final Widget? placeholder;

  const AppNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.errorWidget,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    final cleanUrl = imageUrl.trim();
    if (cleanUrl.isEmpty) {
      return errorWidget ?? _defaultErrorWidget();
    }

    // 1. دعم الصور المشفرة بتنسيق Base64 Data URL
    if (cleanUrl.startsWith('data:image')) {
      try {
        final commaIdx = cleanUrl.indexOf(',');
        final base64Data = commaIdx != -1 ? cleanUrl.substring(commaIdx + 1) : cleanUrl;
        final bytes = base64Decode(base64Data);
        return Image.memory(
          bytes,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, __, ___) => errorWidget ?? _defaultErrorWidget(),
        );
      } catch (e) {
        debugPrint('[-] Error decoding base64 image: $e');
        return errorWidget ?? _defaultErrorWidget();
      }
    }

    // 2. حل روابط تيليجرام وشبكات الـ CDN لتخطي CORS
    final resolved = AppConstants.resolveImageUrl(cleanUrl);

    final bool hasFiniteWidth = width != null && width!.isFinite && width! > 0;
    final bool hasFiniteHeight = height != null && height!.isFinite && height! > 0;

    // على الويب نمنع تماماً تمرير cacheWidth/cacheHeight لمنع انهيار متصفحات الهواتف
    // وعلى المنصات الأخرى لا نمرره إلا إذا كانت الأبعاد محددة ومنتهية وليست infinity
    final int? targetCacheWidth = (!kIsWeb && hasFiniteWidth)
        ? (width! * 2.5).toInt().clamp(100, 1200)
        : null;
    final int? targetCacheHeight = (!kIsWeb && hasFiniteHeight)
        ? (height! * 2.5).toInt().clamp(100, 1200)
        : null;

    return Image.network(
      resolved,
      width: width,
      height: height,
      cacheWidth: targetCacheWidth,
      cacheHeight: targetCacheHeight,
      fit: fit,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return placeholder ??
            _ImageShimmerSkeleton(
              width: width,
              height: height,
            );
      },
      errorBuilder: (context, error, stackTrace) {
        debugPrint('[-] AppNetworkImage load error for $resolved: $error');
        return errorWidget ?? _defaultErrorWidget();
      },
    );
  }

  Widget _defaultErrorWidget() {
    return Container(
      width: width,
      height: height,
      color: const Color(0xFFF1F5F9),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.broken_image_outlined,
              color: const Color(0xFF94A3B8),
              size: (height != null && height!.isFinite && height! < 100) ? 20 : 28,
            ),
            if (height == null || (height!.isFinite && height! >= 100)) ...[
              const SizedBox(height: 6),
              Text(
                'تعذر تحميل الصورة',
                style: GoogleFonts.cairo(color: const Color(0xFF94A3B8), fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// هيكل عظمي مموج ناعم (Shimmer Skeleton) بألوان الهوية الأكاديمية لتحميل الصور بسلاسة فائقة
class _ImageShimmerSkeleton extends StatefulWidget {
  final double? width;
  final double? height;

  const _ImageShimmerSkeleton({this.width, this.height});

  @override
  State<_ImageShimmerSkeleton> createState() => _ImageShimmerSkeletonState();
}

class _ImageShimmerSkeletonState extends State<_ImageShimmerSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        final t = _animController.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Color.lerp(
              const Color(0xFFF1F5F9), // Slate-100
              const Color(0xFFE2E8F0), // Slate-200
              t,
            ),
          ),
          child: Center(
            child: Icon(
              Icons.image_outlined,
              color: Color.lerp(
                const Color(0xFFCBD5E1),
                const Color(0xFF94A3B8),
                t,
              ),
              size: 26,
            ),
          ),
        );
      },
    );
  }
}
