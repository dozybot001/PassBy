import { createServer } from 'node:http';
import { pathToFileURL } from 'node:url';
import { TenonAuth, readBody } from './auth.mjs';

export function createApp(auth) {
  return createServer(async (req, res) => {
    res.setHeader('Cache-Control', 'no-store'); res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('X-Content-Type-Options', 'nosniff'); res.setHeader('X-Frame-Options', 'DENY');
    const json = (status, data) => res.writeHead(status, { 'Content-Type': 'application/json' }).end(JSON.stringify(data));
    try {
      const url = new URL(req.url, 'https://tenon.asia');
      if (url.pathname === '/passby/api/health' && req.method === 'GET') return json(200, { ok: true });
      if (url.pathname === '/passby/api/auth/start' && req.method === 'GET') return await auth.start(req, res, url);
      if (['/passby/api/auth/callback', '/passby/api/auth/ios/callback'].includes(url.pathname) && req.method === 'GET') return await auth.complete(req, res, url);
      if (url.pathname === '/passby/api/auth/session' && req.method === 'GET') return json(200, { identity: auth.identity(req).session });
      if (url.pathname === '/passby/api/auth/exchange' && req.method === 'POST') {
        if (req.headers.origin && req.headers.origin !== auth.origin) return json(403, { error: 'forbidden' });
        if (req.headers['content-type'] !== 'application/json') return json(415, { error: 'invalid_request' });
        return json(200, auth.exchange(await readBody(req)));
      }
      if (url.pathname === '/passby/api/auth/logout' && req.method === 'POST') {
        const bearer = /^Bearer [A-Za-z0-9_-]{43}$/.test(req.headers.authorization || '');
        if (!bearer && req.headers.origin !== auth.origin || req.headers.origin && req.headers.origin !== auth.origin) return json(403, { error: 'forbidden' });
        try { auth.sessions.delete(auth.identity(req).key); } catch {}
        res.setHeader('Set-Cookie', auth.cookie('session', '', 0)); return json(200, { ok: true });
      }
      return json(404, { error: 'not_found' });
    } catch (error) {
      // No callback URLs, central tokens, identity details or error payload logs.
      if (/^\/passby\/api\/auth\/(?:ios\/)?callback(?:\?|$)/.test(req.url || '')) {
        res.setHeader('Set-Cookie', auth.cookie('attempt', '', 0, 'Lax'));
        return res.writeHead(303, { Location: '/passby/?auth_error=tenon' }).end();
      }
      return json(error.status || 503, { error: 'authentication_unavailable' });
    }
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const auth = new TenonAuth({ clientId: process.env.TENON_CLIENT_ID, clientSecret: process.env.TENON_CLIENT_SECRET, iosClientId: process.env.TENON_IOS_CLIENT_ID, iosClientSecret: process.env.TENON_IOS_CLIENT_SECRET });
  createApp(auth).listen(Number(process.env.PORT || 7280), '127.0.0.1');
}
