// Minimal service worker — required by Chrome for "Add to Home screen" /
// install-app installability. Does not cache anything; the app always
// loads fresh from Supabase and the network.
self.addEventListener('install', (event) => {
  self.skipWaiting();
});
self.addEventListener('activate', (event) => {
  self.clients.claim();
});
self.addEventListener('fetch', (event) => {
  // Pass-through: no offline caching, just satisfies the installability requirement.
});
