import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nust_student_portal/services/image_optimizer_service.dart';

void main() {
  group('ImageOptimizerService Unit Tests', () {
    test('Empty bytes returns safe fallback result', () async {
      final res = await ImageOptimizerService.optimizeBannerImage(
        rawBytes: Uint8List(0),
        originalFileName: 'test.png',
      );

      expect(res.bytes.isEmpty, isTrue);
      expect(res.originalSizeBytes, 0);
      expect(res.optimizedSizeBytes, 0);
      expect(res.savedPercentage, 0.0);
    });

    test('Large image (2000x1200) is downscaled and compressed to optimal banner bounds', () async {
      // إنتاج صورة اختبارية بدقة 2000x1200
      final testImg = img.Image(width: 2000, height: 1200);
      img.fill(testImg, color: img.ColorRgb8(27, 63, 182)); // Royal blue AppTheme.primary
      final rawPng = Uint8List.fromList(img.encodePng(testImg));

      expect(rawPng.length, greaterThan(0));

      final res = await ImageOptimizerService.optimizeBannerImage(
        rawBytes: rawPng,
        originalFileName: 'university_event_poster.png',
        maxWidth: 1440,
        maxHeight: 900,
        quality: 80,
      );

      // التأكد من تطبيق حدود الأبعاد المخصصة للبانر
      expect(res.width, lessThanOrEqualTo(1440));
      expect(res.height, lessThanOrEqualTo(900));

      // التأكد من استبدال الامتداد إلى jpg عالي الكفاءة
      expect(res.fileName.endsWith('.jpg'), isTrue);
      expect(res.fileName, 'university_event_poster.jpg');

      // التأكد من سلامة البايتات الناتجة كصورة صالحة
      final decodedOptimized = img.decodeImage(res.bytes);
      expect(decodedOptimized, isNotNull);
      expect(decodedOptimized!.width, res.width);
      expect(decodedOptimized.height, res.height);
    });

    test('Corrupt image data does not crash and falls back gracefully', () async {
      final corruptBytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final res = await ImageOptimizerService.optimizeBannerImage(
        rawBytes: corruptBytes,
        originalFileName: 'corrupt.jpg',
      );

      expect(res.bytes, corruptBytes);
      expect(res.originalSizeBytes, 8);
      expect(res.optimizedSizeBytes, 8);
    });
  });
}
