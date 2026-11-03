import { createServer } from 'node:http';
import { randomUUID } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { TenonAuth, readBody } from './auth.mjs';
import { SessionStore } from './sessions.mjs';
import { ProductDeletion } from './product-deletion.mjs';

const TITLES = { 400: 'Bad Request', 401: 'Unauthorized', 403: 'Forbidden', 404: 'Not Found', 405: 'Method Not Allowed',
  413: 'Content Too Large', 415: 'Unsupported Media Type', 429: 'Too Many Requests', 503: 'Service Unavailable' };

export function createApp(primaryAuth, webAuth = null, { deletionTransport = fetch } = {}) {
  const deletion = new Map([primaryAuth, webAuth].filter(Boolean).map(auth => [auth, new ProductDeletion({ auth, transport: deletionTransport })]));
  return createServer(async (req, res) => {
    res.setHeader('Cache-Control', 'no-store'); res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('X-Content-Type-Options', 'nosniff'); res.setHeader('X-Frame-Options', 'DENY');
    const json = (status, data) => res.writeHead(status, { 'Content-Type': 'application/json' }).end(JSON.stringify(data));
    const path = (req.url || '').split('?')[0];
    // Support can locate a failure by this ID. Logs carry only the ID, path and status.
    const requestId = randomUUID(); res.setHeader('X-Request-Id', requestId);
    const log = status => { if (status >= 500 || [403, 429].includes(status)) console.error(JSON.stringify({ time: new Date().toISOString(), requestId, path, status })); };
    // RFC 9457 problem details; `error` stays for existing clients.
    const problem = (status, error) => {
      if (status === 429) res.setHeader('Retry-After', '60');
      log(status);
      res.writeHead(status, { 'Content-Type': 'application/problem+json' })
        .end(JSON.stringify({ type: 'about:blank', title: TITLES[status] || 'Error', status, error, requestId }));
    };
    const auth = path.startsWith('/api/') ? webAuth : primaryAuth;
    if (!auth) return problem(404, 'not_found');
    try {
      const url = new URL(req.url, auth.origin);
      const route = url.pathname.startsWith(auth.apiPath + '/') ? url.pathname.slice(auth.apiPath.length) : '';
      if (['/auth/tenon/delete/start', '/auth/tenon/delete/execute'].includes(route)) {
        if (req.method !== 'POST') { res.setHeader('Allow', 'POST'); return problem(405, 'method_not_allowed'); }
        if (!/^application\/json(?:;|$)/i.test(req.headers['content-type'] || '')) return problem(415, 'invalid_request');
        const body = await readBody(req);
        if (route.endsWith('/start')) {
          const bearer = /^Bearer [A-Za-z0-9_-]{43}$/.test(req.headers.authorization || '');
          if (req.headers['sec-fetch-site'] === 'cross-site' || req.headers.origin && req.headers.origin !== auth.origin || !bearer && req.headers.origin !== auth.origin) return problem(403, 'forbidden');
          if (Object.keys(body).length) return problem(400, 'invalid_request');
          return json(200, await deletion.get(auth).start(req));
        }
        if (req.headers.origin && req.headers.origin !== 'https://account.tenon.asia') return problem(403, 'forbidden');
        return json(200, await deletion.get(auth).execute(body));
      }
      if (route === '/health' && req.method === 'GET') { auth.sessionStore.health(); return json(200, { ok: true, sessionStorage: 'sqlite' }); }
      if (route === '/auth/start' && req.method === 'GET') return await auth.start(req, res, url);
      if (['/auth/callback', '/auth/ios/callback'].includes(route) && req.method === 'GET') return await auth.complete(req, res, url);
      if (route === '/auth/session' && req.method === 'GET') return json(200, { identity: auth.identity(req).session });
      if (['/auth/exchange', '/auth/refresh'].includes(route) && req.method === 'POST') {
        if (req.headers.origin && req.headers.origin !== auth.origin) return problem(403, 'forbidden');
        if (req.headers['content-type'] !== 'application/json') return problem(415, 'invalid_request');
        const body = await readBody(req);
        return json(200, route === '/auth/refresh' ? await auth.refresh(body) : auth.exchange(body));
      }
      if (route === '/auth/logout' && req.method === 'POST') {
        const bearer = /^Bearer [A-Za-z0-9_-]{43}$/.test(req.headers.authorization || '');
        if (!bearer && req.headers.origin !== auth.origin || req.headers.origin && req.headers.origin !== auth.origin) return problem(403, 'forbidden');
        auth.logout(req);
        if (req.headers['content-type'] === 'application/json') await auth.revoke(await readBody(req));
        res.setHeader('Set-Cookie', auth.cookie('session', '', 0)); return json(200, { ok: true });
      }
      return problem(404, 'not_found');
    } catch (error) {
      // No callback URLs, central tokens, identity details or error payload logs.
      if ([auth.apiPath + '/auth/callback', auth.apiPath + '/auth/ios/callback'].includes(path)) {
        log(error.status || 503);
        res.setHeader('Set-Cookie', auth.cookie('attempt', '', 0, 'Lax'));
        return res.writeHead(303, { Location: auth.basePath + '?auth_error=tenon&request_id=' + requestId }).end();
      }
      return problem(error.status || 503, 'authentication_unavailable');
    }
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.umask(0o077);
  const sessionPath = process.env.SESSION_DB || '/data/sessions.sqlite';
  if (sessionPath === ':memory:') throw Error('Persistent session storage is required');
  const sessionStore = new SessionStore(sessionPath);
  const auth = new TenonAuth({ clientId: process.env.TENON_CLIENT_ID, clientSecret: process.env.TENON_CLIENT_SECRET, iosClientId: process.env.TENON_IOS_CLIENT_ID, iosClientSecret: process.env.TENON_IOS_CLIENT_SECRET, sessionStore });
  const webAuth = process.env.TENON_WEB_CLIENT_ID ? new TenonAuth({ origin: 'https://passby.tenon.asia', clientId: process.env.TENON_WEB_CLIENT_ID, clientSecret: process.env.TENON_WEB_CLIENT_SECRET, sessionStore }) : null;
  // The container listens on its private network; the host publishes the port on 127.0.0.1 only.
  createApp(auth, webAuth).listen(Number(process.env.PORT || 7280), process.env.HOST || '127.0.0.1');
}
