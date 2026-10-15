import 'web_reload_helper_stub.dart'
    if (dart.library.html) 'web_reload_helper_web.dart' as impl;

/// دالة موحدة متعددة المنصات لإعادة تحميل صفحة الويب وتفريغ الكاش
void triggerWebReload() => impl.triggerWebReload();
