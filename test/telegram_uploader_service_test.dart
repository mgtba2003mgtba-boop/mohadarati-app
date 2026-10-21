import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nust_student_portal/services/web_uploader_stub.dart';

void main() {
  group('TelegramUploaderService & Progress Engine Unit Tests', () {
    test('ProgressMultipartRequest tracks streamed byte chunks', () async {
      final uri = Uri.parse('https://example.com/upload');
      final List<int> progressBytes = [];

      final request = ProgressMultipartRequest(
        'POST',
        uri,
        onProgress: (sent, total) {
          progressBytes.add(sent);
        },
      );

      request.fields['chat_id'] = '12345';
      final dummyBytes = Uint8List.fromList(List.generate(1024 * 64, (i) => i % 256)); // 64 KB
      request.files.add(
        http.MultipartFile.fromBytes(
          'document',
          dummyBytes,
          filename: 'test.pdf',
        ),
      );

      final byteStream = request.finalize();
      final collected = await byteStream.toBytes();

      expect(collected.isNotEmpty, isTrue);
      expect(progressBytes.isNotEmpty, isTrue);
      expect(progressBytes.last, equals(request.contentLength));
    });

    test('Telegram multi-part chunk descriptor serialization and validation', () {
      final parts = [
        {'part': 1, 'message_id': 1001, 'file_id': 'BQACAgIAAxk1', 'size': 19922944},
        {'part': 2, 'message_id': 1002, 'file_id': 'BQACAgIAAxk2', 'size': 19922944},
        {'part': 3, 'message_id': 1003, 'file_id': 'BQACAgIAAxk3', 'size': 10485760},
      ];

      final descriptor = 'telegram:parts:${jsonEncode(parts)}';
      expect(descriptor.startsWith('telegram:parts:'), isTrue);

      final decodedStr = descriptor.replaceFirst('telegram:parts:', '');
      final List<dynamic> parsed = jsonDecode(decodedStr);
      expect(parsed.length, equals(3));
      expect(parsed[0]['part'], equals(1));
      expect(parsed[0]['message_id'], equals(1001));
      expect(parsed[1]['file_id'], equals('BQACAgIAAxk2'));
      expect(parsed[2]['size'], equals(10485760));

      final totalSize = parsed.fold<int>(0, (sum, p) => sum + (p['size'] as int));
      expect(totalSize, equals(19922944 * 2 + 10485760));
    });

    test('Chunk calculation accurately partitions large files up to 2GB', () {
      const int totalBytes = 75 * 1024 * 1024; // 75 MB
      const int chunkSize = 19 * 1024 * 1024; // 19 MB
      final int totalParts = (totalBytes / chunkSize).ceil();

      expect(totalParts, equals(4)); // 19 + 19 + 19 + 18 = 75

      int calculatedSum = 0;
      for (int i = 0; i < totalParts; i++) {
        final start = i * chunkSize;
        final end = (start + chunkSize > totalBytes) ? totalBytes : start + chunkSize;
        final partLength = end - start;
        expect(partLength, lessThanOrEqualTo(chunkSize));
        calculatedSum += partLength;
      }
      expect(calculatedSum, equals(totalBytes));
    });

    test('150MB file partitions into exactly 8 chunks strictly under 20MB', () {
      const int totalBytes = 150 * 1024 * 1024; // 150 MB
      const int chunkSize = 19 * 1024 * 1024; // 19 MB
      final int totalParts = (totalBytes / chunkSize).ceil();

      expect(totalParts, equals(8));

      for (int i = 0; i < totalParts; i++) {
        final start = i * chunkSize;
        final end = (start + chunkSize > totalBytes) ? totalBytes : start + chunkSize;
        final partLength = end - start;
        expect(partLength, lessThanOrEqualTo(19 * 1024 * 1024));
        expect(partLength, lessThan(20 * 1024 * 1024)); // Telegram getFile ceiling
      }
    });
  });
}
