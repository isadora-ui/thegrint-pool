// TheGrint World Cup Pool 2026 — Service Worker
const CACHE_NAME = 'thegrint-pool-v1';

// Arquivos que serão salvos no cache para carregamento mais rápido
const STATIC_ASSETS = [
  '/',
  '/index.html',
  'https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap',
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2'
];

// Instala o service worker e faz cache dos arquivos estáticos
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      // Tenta fazer cache dos assets, mas não falha se algum não carregar
      return Promise.allSettled(
        STATIC_ASSETS.map(url => cache.add(url).catch(() => {}))
      );
    })
  );
  self.skipWaiting();
});

// Ativa e remove caches antigos
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames
          .filter((name) => name !== CACHE_NAME)
          .map((name) => caches.delete(name))
      );
    })
  );
  self.clients.claim();
});

// Estratégia: Network First (tenta buscar da internet, cai no cache se offline)
self.addEventListener('fetch', (event) => {
  // Ignora requisições do Supabase (dados em tempo real sempre da internet)
  if (event.request.url.includes('supabase.co')) {
    return;
  }

  event.respondWith(
    fetch(event.request)
      .then((response) => {
        // Se conseguiu da internet, salva uma cópia no cache
        if (response && response.status === 200) {
          const responseClone = response.clone();
          caches.open(CACHE_NAME).then((cache) => {
            cache.put(event.request, responseClone);
          });
        }
        return response;
      })
      .catch(() => {
        // Se não tiver internet, tenta servir do cache
        return caches.match(event.request).then((cached) => {
          if (cached) return cached;
          // Fallback para a página principal se offline
          return caches.match('/index.html');
        });
      })
  );
});
