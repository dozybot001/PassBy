import { createServer } from 'node:http';
import { pathToFileURL } from 'node:url';
import { TenonAuth, readBody } from './auth.mjs';

export function createApp(legacyAuth, webAuth = null) {
  return createServer(async (req, res) => {
    res.setHeader('Cache-Control', 'no-store'); res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('X-Content-Type-Options', 'nosniff'); res.setHeader('X-Frame-Options', 'DENY');
    const json = (status, data) => res.writeHead(status, { 'Content-Type': 'application/json' }).end(JSON.stringify(data));
    const path = (req.url || '').split('?')[0];
    const auth = path.startsWith('/api/') ? webAuth : legacyAuth;
    if (!auth) return json(404, { error: 'not_found' });
    try {
      const url = new URL(req.url, auth.origin);
      const route = url.pathname.startsWith(auth.apiPath + '/') ? url.pathname.slice(auth.apiPath.length) : '';
      if (route === '/health' && req.method === 'GET') return json(200, { ok: true });
      if (route === '/auth/start' && req.method === 'GET') return await auth.start(req, res, url);
      if (['/auth/callback', '/auth/ios/callback'].includes(route) && req.method === 'GET') return await auth.complete(req, res, url);
      if (route === '/auth/session' && req.method === 'GET') return json(200, { identity: auth.identity(req).session });
      if (route === '/auth/exchange' && req.method === 'POST') {
        if (req.headers.origin && req.headers.origin !== auth.origin) return json(403, { error: 'forbidden' });
        if (req.headers['content-type'] !== 'application/json') return json(415, { error: 'invalid_request' });
        return json(200, auth.exchange(await readBody(req)));
      }
      if (route === '/auth/logout' && req.method === 'POST') {
        const bearer = /^Bearer [A-Za-z0-9_-]{43}$/.test(req.headers.authorization || '');
        if (!bearer && req.headers.origin !== auth.origin || req.headers.origin && req.headers.origin !== auth.origin) return json(403, { error: 'forbidden' });
        try { auth.sessions.delete(auth.identity(req).key); } catch {}
        res.setHeader('Set-Cookie', auth.cookie('session', '', 0)); return json(200, { ok: true });
      }
      return json(404, { error: 'not_found' });
    } catch (error) {
      // No callback URLs, central tokens, identity details or error payload logs.
      if ([auth.apiPath + '/auth/callback', auth.apiPath + '/auth/ios/callback'].includes(path)) {
        res.setHeader('Set-Cookie', auth.cookie('attempt', '', 0, 'Lax'));
        return res.writeHead(303, { Location: auth.basePath + '?auth_error=tenon' }).end();
      }
      return json(error.status || 503, { error: 'authentication_unavailable' });
    }
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const auth = new TenonAuth({ clientId: process.env.TENON_CLIENT_ID, clientSecret: process.env.TENON_CLIENT_SECRET, iosClientId: process.env.TENON_IOS_CLIENT_ID, iosClientSecret: process.env.TENON_IOS_CLIENT_SECRET });
  const webAuth = process.env.TENON_WEB_CLIENT_ID ? new TenonAuth({ origin: 'https://passby.tenon.asia', clientId: process.env.TENON_WEB_CLIENT_ID, clientSecret: process.env.TENON_WEB_CLIENT_SECRET }) : null;
  createApp(auth, webAuth).listen(Number(process.env.PORT || 7280), '127.0.0.1');
}
