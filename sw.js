const CACHE='nu-findit-shell-v3';
const CORE=['./','./index.html','./styles.css','./app.js','./config.js','./manifest.webmanifest','./assets/icon-192.png','./assets/icon-512.png'];
// Take over immediately so updates are never stuck behind an old worker.
self.addEventListener('install',e=>{self.skipWaiting();e.waitUntil(caches.open(CACHE).then(c=>c.addAll(CORE)))});
self.addEventListener('activate',e=>e.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim())));
// Network-first: always get the latest files when online; fall back to the cache only when offline.
self.addEventListener('fetch',e=>{
  const u=new URL(e.request.url);
  if(e.request.method!=='GET'||u.origin!==location.origin)return;
  e.respondWith(fetch(e.request,{cache:'no-cache'}).then(res=>{if(res.ok){const copy=res.clone();caches.open(CACHE).then(c=>c.put(e.request,copy))}return res}).catch(()=>caches.match(e.request).then(hit=>hit||caches.match('./index.html'))));
});
