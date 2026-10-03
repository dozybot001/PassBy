import { test } from 'node:test';
import assert from 'node:assert/strict';
import { TenonAuth, ISSUER, ROLE, digest, TTL } from '../auth.mjs';
import { createApp } from '../server.mjs';

function fixture(options = {}) {
  let now = 1000000, grants = 0;
  const info = { sub: 'test-user', name: 'Example', email_verified: true, [ROLE]: 'user' };
  const claims = { iss: ISSUER, sub: info.sub, exp: now / 1000 + 3600, [ROLE]: info[ROLE] };
  const protocol = {
    discovery: async () => ({ serverMetadata: () => ({ issuer: ISSUER }) }), ClientSecretBasic: () => {},
    randomPKCECodeVerifier: () => 'verifier', randomState: () => 'state', randomNonce: () => 'nonce',
    calculatePKCECodeChallenge: async () => 'challenge',
    buildAuthorizationUrl: (_, params) => { assert.equal(params.code_challenge_method, 'S256'); const target = new URL('https://account.tenon.asia/authorize');target.search = new URLSearchParams(params).toString();return target; },
    authorizationCodeGrant: async (_, url, checks) => {
      grants++; assert.deepEqual(checks, { pkceCodeVerifier: 'verifier', expectedState: 'state', expectedNonce: 'nonce', idTokenExpected: true });
      if (url.searchParams.get('state') !== checks.expectedState) throw Error('Invalid state');
      return { claims: () => claims, access_token: 'test-only', expires_in: 3600 };
    }, fetchUserInfo: async () => info,
  };
  const auth = new TenonAuth({ clientId: 'test', clientSecret: 'test-only', iosClientId: 'native-test', iosClientSecret: 'native-test-only', protocol, now: () => now, ...options });
  const req = { headers: {} }, res = { headers: {}, setHeader(k, v) { this.headers[k] = v; }, writeHead(s, h) { this.status = s; Object.assign(this.headers, h); return this; }, end() {} };
  return { auth, req, res, info, claims, advance: ms => { now += ms; }, grants: () => grants };
}
async function begin(f, suffix = '') {
  await f.auth.start(f.req, f.res, new URL('https://tenon.asia/passby/api/auth/start' + suffix));
  f.req.headers.cookie = f.res.headers['Set-Cookie'].split(';')[0];
}
const callback = (native = false) => new URL(`https://tenon.asia/passby/api/auth/${native ? 'ios/' : ''}callback?code=test&state=state`);
test('callback grants bounded independent session; token is never returned to the web', async () => {
  const f = fixture(); await begin(f); await f.auth.complete(f.req, f.res, callback());
  assert.equal(f.res.headers.Location, '/passby/');
  assert.match(f.res.headers['Set-Cookie'][1], /HttpOnly; Secure; SameSite=Strict/);
  f.req.headers.cookie = f.res.headers['Set-Cookie'][1].split(';')[0];
  const identity = f.auth.identity(f.req).session;
  assert.equal(identity.role, 'user'); assert.equal(identity.expires, 1000000 + TTL);
  assert.equal('access_token' in identity, false); assert.equal(f.grants(), 1);
  f.advance(TTL); assert.throws(() => f.auth.identity(f.req), { status: 401 });
});
test('missing cookie, wrong state, expired and replayed callbacks cannot grant sessions', async () => {
  for (const kind of ['missing', 'state', 'expired', 'replay']) {
    const f = fixture(); await begin(f);
    if (kind === 'missing') f.req.headers.cookie = '';
    if (kind === 'expired') f.advance(600000);
    const url = callback(); if (kind === 'state') url.searchParams.set('state', 'wrong');
    if (kind === 'replay') await f.auth.complete(f.req, f.res, url);
    await assert.rejects(f.auth.complete(f.req, f.res, url));
    if (kind !== 'missing') assert.equal(f.auth.attempts.size, 0);
  }
});
test('unverified, mismatched subject/role and expired central tokens are rejected', async () => {
  for (const mutate of [f => { f.info.email_verified = false; }, f => { f.info.sub = 'other'; }, f => { f.info[ROLE] = 'admin'; }, f => { f.claims.exp = 0; }, f => { f.claims.iss = 'https://attacker.invalid'; }]) {
    const f = fixture(); mutate(f); await begin(f); await assert.rejects(f.auth.complete(f.req, f.res, callback())); assert.equal(f.auth.sessions.size, 0);
  }
});
test('native callback is fixed, PKCE-bound, one-use and short-lived', async () => {
  const f = fixture(), verifier = 'x'.repeat(43), state = 's'.repeat(43);
  await begin(f, `?platform=ios&challenge=${digest(verifier)}&state=${state}`); await f.auth.complete(f.req, f.res, callback(true));
  const url = new URL(f.res.headers.Location); assert.equal(url.protocol, 'passby:'); assert.equal(url.host, 'auth');
  const ticket = url.searchParams.get('ticket');
  assert.throws(() => f.auth.exchange({ ticket, verifier: 'z'.repeat(43), state }), { status: 401 });
  const result = f.auth.exchange({ ticket, verifier, state }); assert.equal(result.identity.sub, 'test-user');
  assert.throws(() => f.auth.exchange({ ticket, verifier, state }), { status: 401 });
  assert.equal(f.auth.identity({ headers: { authorization: `Bearer ${result.token}` } }).session.sub, 'test-user');
});
test('native ticket expires and unsafe login starts are rejected', async () => {
  const f = fixture(), verifier = 'v'.repeat(43), state = 's'.repeat(43);
  await begin(f, `?platform=ios&challenge=${digest(verifier)}&state=${state}`); await f.auth.complete(f.req, f.res, callback(true));
  const ticket = new URL(f.res.headers.Location).searchParams.get('ticket'); f.advance(60000);
  assert.throws(() => f.auth.exchange({ ticket, verifier, state }), { status: 401 });
  await assert.rejects(f.auth.start({ headers: { 'sec-fetch-site': 'cross-site' } }, f.res, new URL('https://tenon.asia/passby/api/auth/start')), { status: 403 });
});
test('API rejects CSRF logout, unexpected methods and password/vault endpoints', async t => {
  const f = fixture(), server = createApp(f.auth); await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => server.close()); const origin = `http://127.0.0.1:${server.address().port}`;
  assert.equal((await fetch(origin + '/passby/api/health')).status, 200);
  assert.equal((await fetch(origin + '/passby/api/auth/session')).status, 401);
  assert.equal((await fetch(origin + '/passby/api/auth/logout', { method: 'POST', headers: { origin: 'https://attacker.invalid' } })).status, 403);
  assert.equal((await fetch(origin + '/passby/api/auth/exchange', { method: 'POST', body: 'invalid' })).status, 415);
  assert.equal((await fetch(origin + '/passby/api/vault', { method: 'POST', body: 'test-only' })).status, 404);
});

test('product sessions have a one-minute maximum lifetime', () => { assert.equal(TTL, 60000); });


test('dedicated web origin uses exact callbacks, host-only cookies and isolated sessions', async t => {
  const legacy = fixture(), web = fixture({ origin: 'https://passby.tenon.asia' });
  assert.equal(web.auth.callback, 'https://passby.tenon.asia/api/auth/callback');
  await web.auth.start(web.req, web.res, new URL('https://passby.tenon.asia/api/auth/start?format=json'));
  assert.equal(web.res.status, 200);
  assert.match(web.res.headers['Set-Cookie'], /Path=\/api; HttpOnly; Secure/);
  assert.doesNotMatch(web.res.headers['Set-Cookie'], /Domain=/);
  web.req.headers.cookie = web.res.headers['Set-Cookie'].split(';')[0];
  await assert.rejects(web.auth.complete(web.req, web.res, callback()), { status: 401 });
  await web.auth.start(web.req, web.res, new URL('https://passby.tenon.asia/api/auth/start'));
  web.req.headers.cookie = web.res.headers['Set-Cookie'].split(';')[0];
  await web.auth.complete(web.req, web.res, new URL('https://passby.tenon.asia/api/auth/callback?code=test&state=state'));
  assert.equal(web.res.headers.Location, '/');
  web.req.headers.cookie = web.res.headers['Set-Cookie'][1].split(';')[0];
  assert.equal(web.auth.identity(web.req).session.sub, 'test-user');
  assert.throws(() => legacy.auth.identity(web.req), { status: 401 });
  const server = createApp(legacy.auth, web.auth);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => server.close());
  const base = `http://127.0.0.1:${server.address().port}`;
  for (const path of ['/api/health', '/passby/api/health']) assert.equal((await fetch(base + path)).status, 200);
  const start = await fetch(base + '/api/auth/start?format=json');
  assert.equal(start.status, 200);
  const destination = new URL((await start.json()).url);
  assert.equal(destination.origin, 'https://account.tenon.asia');
  assert.equal(destination.searchParams.get('redirect_uri'), 'https://passby.tenon.asia/api/auth/callback');
  assert.equal(destination.searchParams.get('code_challenge_method'), 'S256');
  assert.match(start.headers.get('set-cookie'), /Path=\/api; HttpOnly; Secure; SameSite=Lax/);
  assert.equal((await fetch(base + '/api/auth/session', { headers: web.req.headers })).status, 200);
  assert.equal((await fetch(base + '/passby/api/auth/session', { headers: web.req.headers })).status, 401);
  assert.equal((await fetch(base + '/api/auth/logout', { method: 'POST', headers: { ...web.req.headers, origin: 'https://tenon.asia' } })).status, 403);
  assert.equal((await fetch(base + '/api/auth/logout', { method: 'POST', headers: { ...web.req.headers, origin: 'https://passby.tenon.asia' } })).status, 200);
  assert.equal((await fetch(base + '/api/auth/session', { headers: web.req.headers })).status, 401);
  assert.throws(() => new TenonAuth({ origin: 'https://attacker.invalid', clientId: 'test', clientSecret: 'test-only' }));
});
