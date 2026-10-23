// ══════════════════════════════════════════════════════════════════════════════
// سكريبت خدمة الإشعارات الخفيف (Zero-Cache Push Notification Service Worker)
// مصمم خصيصاً لآيفون (iOS 16.4+ Standalone) وأندرويد دون تخزين أي كاش يسبب شاشة بيضاء
// ══════════════════════════════════════════════════════════════════════════════

self.addEventListener('install', function(event) {
  self.skipWaiting();
});

self.addEventListener('activate', function(event) {
  event.waitUntil(self.clients.claim());
});

// تمرير جميع طلبات الشبكة مباشرة دون أي اعتراض أو كاش (حفاظاً على استقرار الشبكات في العراق)
self.addEventListener('fetch', function(event) {
  return;
});

// استقبال رسائل إظهار الإشعارات المباشرة من الصفحة أو السحابة
self.addEventListener('message', function(event) {
  if (event.data && event.data.type === 'SHOW_NOTIFICATION') {
    var title = event.data.title || 'محاضراتي';
    var options = {
      body: event.data.body || '',
      icon: '/icons/Icon-192.png',
      badge: '/icons/Icon-192.png',
      tag: event.data.tag || ('nust_' + Date.now()),
      data: { url: event.data.url || '/' },
      renotify: true,
      vibrate: [200, 100, 200]
    };
    event.waitUntil(self.registration.showNotification(title, options));
  }
});

// استقبال Web Push الأحداث السحابية
self.addEventListener('push', function(event) {
  var data = {};
  if (event.data) {
    try {
      data = event.data.json();
    } catch (_) {
      data = { title: 'محاضراتي', body: event.data.text() };
    }
  }
  var title = data.title || '📢 تبليغ جامعي جديد';
  var options = {
    body: data.body || 'تم نشر تبليغ أو محاضرة جديدة في المنظومة الأكاديمية.',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag: data.tag || ('nust_' + Date.now()),
    data: { url: data.url || '/' },
    renotify: true,
    vibrate: [200, 100, 200]
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

// عند نقر الطالب على الإشعار في مركز إشعارات الهاتف
self.addEventListener('notificationclick', function(event) {
  event.notification.close();
  var targetUrl = (event.notification.data && event.notification.data.url) || '/';
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function(windowClients) {
      for (var i = 0; i < windowClients.length; i++) {
        var client = windowClients[i];
        if ('focus' in client) {
          return client.focus();
        }
      }
      if (clients.openWindow) {
        return clients.openWindow(targetUrl);
      }
    })
  );
});
