// Angels - service worker.
// Solo recibe los recordatorios del check-in. No guarda nada en cache: la
// app siempre se carga fresca de la red.
self.addEventListener('install', function(){ self.skipWaiting(); });
self.addEventListener('activate', function(event){ event.waitUntil(self.clients.claim()); });

self.addEventListener('push', function(event){
  var data = {};
  try { data = event.data ? event.data.json() : {}; }
  catch(e){ data = { body: event.data ? event.data.text() : '' }; }
  var title = data.title || 'Angels';
  var options = {
    body: data.body || 'Te falta el check-in.',
    icon: '/icons/icon-192.png',
    badge: '/icons/badge-96.png',
    tag: data.tag || 'angels',
    renotify: true,
    data: { url: data.url || '/' }
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', function(event){
  event.notification.close();
  var url = (event.notification.data && event.notification.data.url) || '/';
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function(list){
      for (var i = 0; i < list.length; i++) {
        var c = list[i];
        try {
          if ('navigate' in c && 'focus' in c) {
            return c.navigate(url).then(function(w){ return (w || c).focus(); }).catch(function(){ return c.focus(); });
          }
        } catch(e){}
      }
      if (self.clients.openWindow) return self.clients.openWindow(url);
    })
  );
});
