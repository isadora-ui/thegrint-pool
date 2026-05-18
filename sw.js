// TheGrint World Cup Pool 2026 — Service Worker
// Busca sempre a versão mais recente do servidor (Network First)
// Sem cache de HTML — garante que o app sempre atualiza

self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  // Apaga TODOS os caches antigos
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(cacheNames.map((name) => caches.delete(name)));
    }).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const url = event.request.url;

  // Supabase, fontes e CDN: sempre da internet, sem cache
  if (
    url.includes('supabase.co') ||
    url.includes('fonts.googleapis.com') ||
    url.includes('fonts.gstatic.com') ||
    url.includes('cdn.jsdelivr.net')
  ) {
    return;
  }

  // HTML principal: NUNCA cachear — sempre busca versão nova
  if (url.endsWith('/') || url.includes('index.html')) {
    event.respondWith(
      fetch(event.request).catch(() => caches.match('/index.html'))
    );
    return;
  }

  // Demais assets: Network First
  event.respondWith(
    fetch(event.request).catch(() => caches.match(event.request))
  );
});
