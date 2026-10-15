// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// إعادة تحميل الصفحة قسرياً في بيئة الويب مع كسر الكاش
void triggerWebReload() {
  try {
    final origin = html.window.location.origin;
    final path = html.window.location.pathname;
    final ts = DateTime.now().millisecondsSinceEpoch;
    html.window.location.replace('$origin$path?_v=$ts');
  } catch (_) {
    html.window.location.reload();
  }
}
