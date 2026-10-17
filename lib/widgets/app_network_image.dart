import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';

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

    return Image.network(
      resolved,
      width: width,
      height: height,
      fit: fit,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return placeholder ??
            Container(
              width: width,
              height: height,
              color: AppTheme.primarySubtle,
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
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
      color: AppTheme.primary,
      child: const Center(
        child: Icon(Icons.image_outlined, color: Colors.white54, size: 28),
      ),
    );
  }
}
