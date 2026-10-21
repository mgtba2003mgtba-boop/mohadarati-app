import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nust_student_portal/services/offline_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OfflineSyncService & SyncMutation Unit Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('SyncMutation correctly serializes and deserializes', () {
      final now = DateTime.now();
      final mutation = SyncMutation(
        id: 'test_123',
        type: MutationType.addLectureComment,
        payload: {
          'lecture_id': 'lec_999',
          'content': 'تعليق تجريبي في وضع عدم الاتصال',
          'student_name': 'مجتبى',
        },
        createdAt: now,
        retryCount: 2,
      );

      final json = mutation.toJson();
      expect(json['id'], 'test_123');
      expect(json['type'], 'addLectureComment');
      expect(json['payload']['lecture_id'], 'lec_999');
      expect(json['retryCount'], 2);

      final restored = SyncMutation.fromJson(json);
      expect(restored.id, 'test_123');
      expect(restored.type, MutationType.addLectureComment);
      expect(restored.payload['lecture_id'], 'lec_999');
      expect(restored.retryCount, 2);
    });

    test('OfflineSyncService enqueues mutations and updates count', () async {
      final syncService = OfflineSyncService();
      await syncService.initialize();
      await syncService.clearQueue();

      expect(syncService.pendingCount, 0);
      expect(syncService.hasPending, false);

      await syncService.enqueue(
        type: MutationType.castPollVote,
        payload: {
          'announcement_id': 'ann_1',
          'option_index': 0,
          'student_id': 'ST-100',
        },
      );

      expect(syncService.pendingCount, 1);
      expect(syncService.hasPending, true);

      await syncService.clearQueue();
      expect(syncService.pendingCount, 0);
      expect(syncService.hasPending, false);
    });

    test('OfflineSyncService persists and restores from SharedPreferences', () async {
      final syncService = OfflineSyncService();
      await syncService.initialize();
      await syncService.clearQueue();

      await syncService.enqueue(
        type: MutationType.toggleReaction,
        payload: {
          'announcement_id': 'ann_55',
          'emoji': '❤️',
          'student_id': 'ST-413',
        },
      );

      expect(syncService.pendingCount, 1);

      // Re-initialize to test persistence
      final newServiceInstance = OfflineSyncService();
      await newServiceInstance.initialize();

      expect(newServiceInstance.pendingCount, 1);
      expect(newServiceInstance.pendingMutations.first.type, MutationType.toggleReaction);
      expect(newServiceInstance.pendingMutations.first.payload['emoji'], '❤️');

      await newServiceInstance.clearQueue();
    });
  });
}
