import 'package:flutter/material.dart';

/// بيئة الاختبارات أو المنصات غير الويب
Widget createWebIFrameWidget({
  required String url,
  required String title,
}) {
  return Center(
    child: Text(
      'عرض المستند: $title',
      style: const TextStyle(color: Colors.white),
    ),
  );
}
