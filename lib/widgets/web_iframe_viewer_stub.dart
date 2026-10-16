import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// بيئة الاختبارات أو المنصات غير الويب
Widget createWebIFrameWidget({
  required String url,
  required String title,
}) {
  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.picture_as_pdf_rounded, color: Colors.cyanAccent, size: 48),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () async {
            final uri = Uri.parse(url);
            try {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } catch (_) {}
          },
          icon: const Icon(Icons.open_in_new_rounded, size: 16),
          label: const Text('فتح المستند'),
        ),
      ],
    ),
  );
}
