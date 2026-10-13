import 'package:flutter/widgets.dart';
import 'web_iframe_viewer_stub.dart'
    if (dart.library.html) 'web_iframe_viewer_web.dart';

/// واجهة موحدة لإنشاء عارض IFrame للمستندات والوسائط متوافق مع كافة المنصات
Widget buildWebIFrame({
  required String url,
  required String title,
}) {
  return createWebIFrameWidget(url: url, title: title);
}
