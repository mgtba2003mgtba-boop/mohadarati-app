import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// نتيجة تحسين وضغط الصورة محلياً في الذاكرة
class OptimizedImageResult {
  final Uint8List bytes;
  final int originalSizeBytes;
  final int optimizedSizeBytes;
  final int width;
  final int height;
  final String fileName;

  const OptimizedImageResult({
    required this.bytes,
    required this.originalSizeBytes,
    required this.optimizedSizeBytes,
    required this.width,
    required this.height,
    required this.fileName,
  });

  /// نسبة تقليص وتوفير الحجم
  double get savedPercentage {
    if (originalSizeBytes <= 0) return 0.0;
    final saved = originalSizeBytes - optimizedSizeBytes;
    if (saved <= 0) return 0.0;
    return (saved / originalSizeBytes) * 100.0;
  }

  /// هل تم تقليص الحجم فعلياً
  bool get wasOptimized => optimizedSizeBytes < originalSizeBytes;
}

/// خدمة ضغط وتصغير الصور الذكية محلياً على العميل
class ImageOptimizerService {
  static const int defaultBannerMaxWidth = 1440;
  static const int defaultBannerMaxHeight = 900;
  static const int defaultQuality = 82;

  /// ضغط وتحسين صورة البوستر في الخلفية دون تجميد واجهة المستخدم
  static Future<OptimizedImageResult> optimizeBannerImage({
    required Uint8List rawBytes,
    required String originalFileName,
    int maxWidth = defaultBannerMaxWidth,
    int maxHeight = defaultBannerMaxHeight,
    int quality = defaultQuality,
  }) async {
    if (rawBytes.isEmpty) {
      return OptimizedImageResult(
        bytes: rawBytes,
        originalSizeBytes: 0,
        optimizedSizeBytes: 0,
        width: 0,
        height: 0,
        fileName: originalFileName,
      );
    }

    try {
      // على الويب نُشغل العملية مباشرة، وعلى الموبايل/الديسكتوب نستخدم compute لمنع تجميد الإطارات
      if (kIsWeb) {
        return _processImage(
          _ImageProcessParams(
            rawBytes: rawBytes,
            fileName: originalFileName,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            quality: quality,
          ),
        );
      } else {
        return await compute(
          _processImage,
          _ImageProcessParams(
            rawBytes: rawBytes,
            fileName: originalFileName,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            quality: quality,
          ),
        );
      }
    } catch (e) {
      debugPrint('[-] Image optimization failed, falling back to original: $e');
      return OptimizedImageResult(
        bytes: rawBytes,
        originalSizeBytes: rawBytes.length,
        optimizedSizeBytes: rawBytes.length,
        width: 0,
        height: 0,
        fileName: originalFileName,
      );
    }
  }

  static OptimizedImageResult _processImage(_ImageProcessParams params) {
    final raw = params.rawBytes;
    final decoded = img.decodeImage(raw);

    if (decoded == null) {
      return OptimizedImageResult(
        bytes: raw,
        originalSizeBytes: raw.length,
        optimizedSizeBytes: raw.length,
        width: 0,
        height: 0,
        fileName: params.fileName,
      );
    }

    // تصحيح زاوية ودوران الصورة حسب بيانات EXIF
    final oriented = img.bakeOrientation(decoded);

    int targetWidth = oriented.width;
    int targetHeight = oriented.height;

    // تصغير الأبعاد بنسب متطابقة إذا كانت الأبعاد تتجاوز الحد الأقصى للبانرات
    if (targetWidth > params.maxWidth || targetHeight > params.maxHeight) {
      final double widthRatio = params.maxWidth / targetWidth;
      final double heightRatio = params.maxHeight / targetHeight;
      final double scale = widthRatio < heightRatio ? widthRatio : heightRatio;

      targetWidth = (targetWidth * scale).round();
      targetHeight = (targetHeight * scale).round();
    }

    final img.Image resized = (targetWidth != oriented.width || targetHeight != oriented.height)
        ? img.copyResize(
            oriented,
            width: targetWidth,
            height: targetHeight,
            interpolation: img.Interpolation.linear,
          )
        : oriented;

    // ترميز بتنسيق JPEG عالي الكفاءة
    final Uint8List optimized = Uint8List.fromList(
      img.encodeJpg(resized, quality: params.quality),
    );

    // إذا تم تصغير الأبعاد أو كانت النتيجة المضغوطة أصغر نعتمد المحسّنة دائماً
    final bool dimensionsChanged = (targetWidth != oriented.width || targetHeight != oriented.height);
    final bool useOptimized = dimensionsChanged || (optimized.length < raw.length);
    final finalBytes = useOptimized ? optimized : raw;

    final String finalName = params.fileName.contains('.')
        ? '${params.fileName.substring(0, params.fileName.lastIndexOf('.'))}.jpg'
        : '${params.fileName}.jpg';

    return OptimizedImageResult(
      bytes: finalBytes,
      originalSizeBytes: raw.length,
      optimizedSizeBytes: finalBytes.length,
      width: resized.width,
      height: resized.height,
      fileName: finalName,
    );
  }
}

class _ImageProcessParams {
  final Uint8List rawBytes;
  final String fileName;
  final int maxWidth;
  final int maxHeight;
  final int quality;

  _ImageProcessParams({
    required this.rawBytes,
    required this.fileName,
    required this.maxWidth,
    required this.maxHeight,
    required this.quality,
  });
}
