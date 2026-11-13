export const TENON_SESSION_TTL = 30 * 24 * 60 * 60 * 1000;
// Tenon Account answers at account.tenonai.cn since 2026-11-13. Identities keep
// the original issuer name below, which is a record key rather than an address.
export const TENON_ACCOUNT_ORIGINS = Object.freeze(['https://account.tenonai.cn']);

export function validIdentity(identity, now = Date.now()) {
  return identity?.issuer === 'https://account.tenon.asia/api/auth'
    && typeof identity.sub === 'string' && identity.sub.length > 0
    && ['admin', 'user'].includes(identity.role)
    && Number.isFinite(identity.expires) && identity.expires > now
    && identity.expires <= now + TENON_SESSION_TTL;
}

export function scheduleExpiry(expires, onExpire, { now = Date.now, schedule = setTimeout, cancel = clearTimeout } = {}) {
  let timer, stopped = false;
  function check() {
    if (stopped) return;
    const remaining = expires - now();
    if (remaining <= 0) { stopped = true; onExpire(); return; }
    // Browser timers overflow beyond roughly 25 days. Recheck daily without
    // changing the session's original deadline.
    timer = schedule(check, Math.min(remaining, 24 * 60 * 60 * 1000));
  }
  check();
  return () => { stopped = true; cancel(timer); };
}
export async function requestProductDeletion(transport = fetch) {
  const response = await transport('./api/auth/tenon/delete/start', { method: 'POST', credentials: 'same-origin',
    headers: { 'Content-Type': 'application/json' }, body: '{}' });
  if (!response.ok) throw Error('Deletion unavailable');
  const result = await response.json(), url = new URL(result.url);
  if (!TENON_ACCOUNT_ORIGINS.includes(url.origin) || url.pathname !== '/account/delete/' || url.username || url.password || url.hash || !/^[A-Za-z0-9_-]{43}$/.test(url.searchParams.get('request') || '')) throw Error('Invalid deletion URL');
  return url.href;
}
