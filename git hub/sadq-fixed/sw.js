// SADQ Service Worker v3 — safe caching
const CACHE='sadq-v4';
const STATIC=['/','/index.html','/login.html','/css/main.css','/css/animations.css','/js/supabase-client.js','/manifest.json','/assets/icons/sadq-icon.svg','/download.jfif'];
self.addEventListener('install',e=>{e.waitUntil(caches.open(CACHE).then(c=>c.addAll(STATIC).catch(()=>{})));self.skipWaiting()});
self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(n=>n!==CACHE).map(n=>caches.delete(n)))));self.clients.claim()});
self.addEventListener('fetch',e=>{
  const u=new URL(e.request.url);
  if(u.hostname.includes('supabase'))return;
  const auth=['/dashboard','/admin-','/teacher-','/profile-','/subwing-d','/settings'];
  if(auth.some(p=>u.pathname.startsWith(p)))return;
  if(u.pathname.match(/\.(css|js|png|jpg|jpeg|jfif|svg|ico|woff2|mp4|webm)$/)){e.respondWith(caches.match(e.request).then(c=>c||fetch(e.request)));return}
  e.respondWith(fetch(e.request).then(r=>{if(r.ok&&e.request.method==='GET'){const c=r.clone();caches.open(CACHE).then(ca=>ca.put(e.request,c))}return r}).catch(()=>caches.match(e.request)));
});
