export const TENON_SESSION_TTL = 30 * 24 * 60 * 60 * 1000;

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
