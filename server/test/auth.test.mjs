import { test } from 'node:test';
import assert from 'node:assert/strict';
import { TenonAuth, ISSUER, ISSUERS, ROLE, digest, TTL, NATIVE_TTL, REFRESH_TTL, SESSION_VERSION } from '../auth.mjs';
import { createApp } from '../server.mjs';
import { SessionStore } from '../sessions.mjs';
import { DatabaseSync } from 'node:sqlite';
import { mkdtempSync, rmSync, readFileSync, statSync, chmodSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawn, spawnSync } from 'node:child_process';

function fixture(options = {}) {
  let now = 1000000, grants = 0;
  const issuedAt = now;
  const info = { sub: 'test-user', name: 'Example', email_verified: true, [ROLE]: 'user' };
  const claims = { iss: ISSUER, sub: info.sub, exp: now / 1000 + 3600, [ROLE]: info[ROLE] };
  const tokens = { claims: () => claims, access_token: 'test-only', expires_in: 3600, refresh_token: 'r'.repeat(32),
    expiresIn: () => Math.max(0, Math.floor(tokens.expires_in - (now - issuedAt) / 1000)) };
  const protocol = {
    discovery: async () => ({ serverMetadata: () => ({ issuer: ISSUER }) }), ClientSecretBasic: () => {},
    randomPKCECodeVerifier: () => 'verifier', randomState: () => 'state', randomNonce: () => 'nonce',
    calculatePKCECodeChallenge: async () => 'challenge',
    buildAuthorizationUrl: (_, params) => { assert.equal(params.code_challenge_method, 'S256'); const target = new URL('https://account.tenon.asia/authorize');target.search = new URLSearchParams(params).toString();return target; },
    authorizationCodeGrant: async (_, url, checks) => {
      grants++; assert.deepEqual(checks, { pkceCodeVerifier: 'verifier', expectedState: 'state', expectedNonce: 'nonce', idTokenExpected: true });
      if (url.searchParams.get('state') !== checks.expectedState) throw Error('Invalid state');
      return tokens;
    }, fetchUserInfo: async () => info,
  };
  const auth = new TenonAuth({ clientId: 'test', clientSecret: 'test-only', iosClientId: 'native-test', iosClientSecret: 'native-test-only', sessionStore: new SessionStore(':memory:'), protocol, now: () => now, ...options });
  const req = { headers: {} }, res = { headers: {}, setHeader(k, v) { this.headers[k] = v; }, writeHead(s, h) { this.status = s; Object.assign(this.headers, h); return this; }, end() {} };
  return { auth, req, res, info, claims, tokens, protocol, advance: ms => { now += ms; }, time: () => now, grants: () => grants };
}
async function begin(f, suffix = '') {
  await f.auth.start(f.req, f.res, new URL('https://tenon.asia/passby/api/auth/start' + suffix));
  f.req.headers.cookie = f.res.headers['Set-Cookie'].split(';')[0];
}
const callback = (native = false) => new URL(`https://tenon.asia/passby/api/auth/${native ? 'ios/' : ''}callback?code=test&state=state`);
test('callback grants an independent 30-day session even when central tokens expire in a minute', async () => {
  const f = fixture(); f.claims.exp = f.time() / 1000 + 60; f.tokens.expires_in = 60;
  await begin(f); await f.auth.complete(f.req, f.res, callback());
  assert.equal(f.res.headers.Location, '/passby/');
  assert.match(f.res.headers['Set-Cookie'][1], /HttpOnly; Secure; SameSite=Strict/);
  assert.match(f.res.headers['Set-Cookie'][1], /Max-Age=2592000$/);
  f.req.headers.cookie = f.res.headers['Set-Cookie'][1].split(';')[0];
  const identity = f.auth.identity(f.req).session;
  assert.equal(identity.role, 'user'); assert.equal(identity.expires, 1000000 + TTL);
  assert.equal('access_token' in identity, false); assert.equal(f.grants(), 1);
  f.advance(TTL - 1); assert.equal(f.auth.identity(f.req).session.expires, identity.expires);
  f.advance(1); assert.throws(() => f.auth.identity(f.req), { status: 401 });
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
  for (const mutate of [f => { f.info.email_verified = false; }, f => { f.info.sub = 'other'; }, f => { f.info[ROLE] = 'admin'; },
    f => { f.claims.exp = 0; }, f => { f.claims.exp = Infinity; }, f => { delete f.claims.exp; },
    f => { f.tokens.expires_in = 0; }, f => { f.tokens.expires_in = Infinity; }, f => { f.claims.iss = 'https://attacker.invalid'; }]) {
    const f = fixture(); mutate(f); await begin(f); await assert.rejects(f.auth.complete(f.req, f.res, callback())); assert.equal(f.auth.sessionCount, 0);
  }
});
test('callback and renewal reject tokens that expire while UserInfo verification is in flight', async () => {
  for (const expiry of ['id', 'access']) for (const phase of ['web', 'native', 'refresh']) {
    const f = fixture();
    if (expiry === 'id') f.claims.exp = f.time() / 1000 + 60;
    else f.tokens.expires_in = 60;
    f.protocol.fetchUserInfo = async () => { f.advance(60000); return f.info; };
    if (phase === 'refresh') {
      f.protocol.refreshTokenGrant = async () => f.tokens;
      await assert.rejects(f.auth.refresh({ refreshToken: f.tokens.refresh_token, issuer: ISSUER, sub: f.info.sub, session_version: 3 }), { status: 401 });
    } else if (phase === 'web') { await begin(f); await assert.rejects(f.auth.complete(f.req, f.res, callback()), { status: 401 }); }
    else {
      await begin(f, `?platform=ios&session_version=3&challenge=${digest('v'.repeat(43))}&state=${'s'.repeat(43)}`);
      await assert.rejects(f.auth.complete(f.req, f.res, callback(true)), { status: 401 });
    }
    assert.equal(f.auth.sessionCount, 0); assert.equal(f.auth.tickets.size, 0);
  }
});
test('native callback is fixed, PKCE-bound, one-use and short-lived', async () => {
  const f = fixture(), verifier = 'x'.repeat(43), state = 's'.repeat(43);
  await begin(f, `?platform=ios&session_version=3&challenge=${digest(verifier)}&state=${state}`); await f.auth.complete(f.req, f.res, callback(true));
  const url = new URL(f.res.headers.Location); assert.equal(url.protocol, 'passby:'); assert.equal(url.host, 'auth');
  const ticket = url.searchParams.get('ticket');
  assert.throws(() => f.auth.exchange({ ticket, verifier: 'z'.repeat(43), state }), { status: 401 });
  const result = f.auth.exchange({ ticket, verifier, state }); assert.equal(result.identity.sub, 'test-user');
  assert.equal(result.identity.expires, f.time() + TTL);
  assert.throws(() => f.auth.exchange({ ticket, verifier, state }), { status: 401 });
  assert.equal(f.auth.identity({ headers: { authorization: `Bearer ${result.token}` } }).session.sub, 'test-user');
});
test('native ticket expires and unsafe login starts are rejected', async () => {
  const f = fixture(), verifier = 'v'.repeat(43), state = 's'.repeat(43);
  await begin(f, `?platform=ios&session_version=3&challenge=${digest(verifier)}&state=${state}`); await f.auth.complete(f.req, f.res, callback(true));
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

test('errors are RFC 9457 problem details with a request ID, and rate limits say when to retry', async t => {
  const busy = { origin: 'https://passby.tenon.asia', apiPath: '/api', basePath: '/', publicOrigin() { return this.origin; },
    sessionStore: { health() { throw Object.assign(Error('busy'), { status: 429 }); } } };
  const f = fixture(), server = createApp(f.auth, busy); await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => server.close()); const origin = `http://127.0.0.1:${server.address().port}`;
  const missing = await fetch(origin + '/passby/api/auth/session');
  const body = await missing.json();
  assert.equal(missing.headers.get('content-type'), 'application/problem+json');
  assert.match(missing.headers.get('x-request-id'), /^[0-9a-f-]{36}$/);
  assert.deepEqual(body, { type: 'about:blank', title: 'Unauthorized', status: 401, error: 'authentication_unavailable', requestId: missing.headers.get('x-request-id') });
  const limited = await fetch(origin + '/api/health');
  assert.equal(limited.status, 429); assert.equal(limited.headers.get('retry-after'), '60');
  assert.equal((await limited.json()).title, 'Too Many Requests');
});

test('web, native and rotating refresh lifetimes are all 30 days', () => {
  assert.equal(TTL, 2592000000); assert.equal(NATIVE_TTL, TTL); assert.equal(REFRESH_TTL, TTL);
  assert.equal(SESSION_VERSION, 3);
});

async function rememberedGrant(f) {
  const verifier = 'v'.repeat(43), state = 's'.repeat(43);
  await begin(f, `?platform=ios&session_version=3&challenge=${digest(verifier)}&state=${state}`);
  const authorization = new URL(f.res.headers.Location);
  assert.equal(authorization.searchParams.get('scope'), 'openid profile email offline_access');
  assert.equal(authorization.searchParams.get('prompt'), 'consent');
  await f.auth.complete(f.req, f.res, callback(true));
  const ticket = new URL(f.res.headers.Location).searchParams.get('ticket');
  return f.auth.exchange({ ticket, verifier, state });
}
test('native v3 grants 30 days; browser sessions never receive refresh credentials', async () => {
  const f = fixture(); f.claims.exp = f.time() / 1000 + 60; f.tokens.expires_in = 60;
  const grant = await rememberedGrant(f);
  assert.equal(grant.version, 3); assert.equal(grant.refreshToken, f.tokens.refresh_token);
  assert.equal(grant.identity.expires, f.time() + TTL); assert.equal(grant.refreshExpires, f.time() + REFRESH_TTL);
  assert.equal(new URL(f.res.headers.Location).searchParams.has('refreshToken'), false);
  f.advance(TTL - 1);
  assert.equal(f.auth.identity({ headers: { authorization: `Bearer ${grant.token}` } }).session.expires, grant.identity.expires);
  f.advance(1); assert.throws(() => f.auth.identity({ headers: { authorization: `Bearer ${grant.token}` } }), { status: 401 });
  const web = fixture(); await begin(web);
  assert.equal(new URL(web.res.headers.Location).searchParams.get('scope'), 'openid profile email');
  await web.auth.complete(web.req, web.res, callback());
  web.req.headers.cookie = web.res.headers['Set-Cookie'][1].split(';')[0];
  assert.deepEqual(Object.keys(web.auth.identity(web.req).session).sort(), ['expires','issuer','name','role','sub']);
});
test('native v2, missing and unsupported protocol versions are rejected without downgrade', async () => {
  for (const version of [undefined, 2, 4, '3']) {
    const f = fixture();
    const start = `?platform=ios&challenge=${digest('v'.repeat(43))}&state=${'s'.repeat(43)}` + (version === undefined ? '' : `&session_version=${version}`);
    if (version !== '3') await assert.rejects(begin(f, start), { status: 400 });
    await assert.rejects(f.auth.refresh({ refreshToken: 'r'.repeat(32), issuer: ISSUER, sub: 'test-user', session_version: version }), { status: 400 });
    assert.equal(f.auth.sessionCount, 0);
  }
});
test('renewal verifies fresh central identity and rotates refresh credential', async () => {
  const f = fixture(); const original = await rememberedGrant(f);
  f.advance(NATIVE_TTL - 60000);
  f.protocol.refreshTokenGrant = async (_, refresh) => {
    assert.equal(refresh, original.refreshToken);
    return { ...f.tokens, claims: () => ({ ...f.claims, exp: f.time() / 1000 + 60 }), expires_in: 60, expiresIn: () => 60, refresh_token: 'n'.repeat(32) };
  };
  f.info.name = 'Updated'; f.info[ROLE] = f.claims[ROLE] = 'admin';
  const next = await f.auth.refresh({ refreshToken: original.refreshToken, issuer: ISSUER, sub: 'test-user', session_version: 3 });
  assert.equal(next.version, 3);
  assert.equal(next.identity.name, 'Updated'); assert.equal(next.identity.role, 'admin');
  assert.equal(next.identity.expires, f.time() + TTL); assert.equal(next.refreshExpires, f.time() + REFRESH_TTL);
  assert.equal(next.refreshToken, 'n'.repeat(32)); assert.ok(next.identity.expires > original.identity.expires);
  assert.equal(f.auth.identity({ headers: { authorization: `Bearer ${next.token}` } }).session.sub, 'test-user');
});
test('rotation retires previous native access and logout retires all retries of the same device credential', async () => {
  const f = fixture(); const original = await rememberedGrant(f);
  f.protocol.refreshTokenGrant = async () => ({ ...f.tokens, refresh_token: 'n'.repeat(32) });
  f.protocol.tokenRevocation = async () => {};
  const body = { refreshToken: original.refreshToken, issuer: ISSUER, sub: original.identity.sub, session_version: 3 };
  const next = await f.auth.refresh(body);
  assert.throws(() => f.auth.identity({ headers: { authorization: `Bearer ${original.token}` } }), { status: 401 });
  const replay = await f.auth.refresh(body);
  assert.equal(replay.refreshToken, next.refreshToken);
  await f.auth.revoke({ refreshToken: next.refreshToken });
  for (const value of [next.token, replay.token]) assert.throws(() => f.auth.identity({ headers: { authorization: `Bearer ${value}` } }), { status: 401 });
});
test('concurrent refreshes coalesce and a mismatched subject cannot reuse the in-flight result', async () => {
  const f = fixture(); let finish, calls = 0;
  f.protocol.refreshTokenGrant = async () => { calls++; await new Promise(resolve => { finish = resolve; }); return { ...f.tokens, refresh_token: 'n'.repeat(32) }; };
  const body = { refreshToken: 'r'.repeat(32), issuer: ISSUER, sub: 'test-user', session_version: 3 };
  const a = f.auth.refresh(body), b = f.auth.refresh(body);
  await assert.rejects(f.auth.refresh({ ...body, sub: 'other' }), { status: 401 });
  await Promise.resolve(); finish();
  assert.deepEqual(await a, await b); assert.equal(calls, 1);
});
test('revoked grants require login; network failure cannot issue an extended session', async () => {
  for (const [error, status] of [[Object.assign(Error(), { error: 'invalid_grant' }), 401], [Error('offline'), 503]]) {
    const f = fixture(); f.protocol.refreshTokenGrant = async () => { throw error; };
    await assert.rejects(f.auth.refresh({ refreshToken: 'r'.repeat(32), issuer: ISSUER, sub: 'test-user', session_version: 3 }), { status });
    assert.equal(f.auth.sessionCount, 0);
  }
});
test('renewal rejects mismatched, unverified or expired identities and missing rotated credentials', async () => {
  for (const mutate of [f => { f.info.email_verified = false; }, f => { f.claims.sub = f.info.sub = 'other'; },
    f => { f.info[ROLE] = 'admin'; }, f => { f.claims.exp = 0; }, f => { delete f.tokens.refresh_token; }]) {
    const f = fixture(); mutate(f); f.protocol.refreshTokenGrant = async () => f.tokens;
    await assert.rejects(f.auth.refresh({ refreshToken: 'r'.repeat(32), issuer: ISSUER, sub: 'test-user', session_version: 3 }));
    assert.equal(f.auth.sessionCount, 0);
  }
});
test('refresh and native logout enforce origin/content type and invoke central revocation', async t => {
  const f = fixture(); let revoked;
  f.protocol.refreshTokenGrant = async () => ({ ...f.tokens, refresh_token: 'n'.repeat(32) });
  f.protocol.tokenRevocation = async (_, value, options) => { revoked = value; assert.equal(options.token_type_hint, 'refresh_token'); };
  const web = fixture({ origin: 'https://passby.tenon.asia' });
  const server = createApp(f.auth, web.auth); await new Promise(resolve => server.listen(0, '127.0.0.1', resolve)); t.after(() => server.close());
  const base = `http://127.0.0.1:${server.address().port}`;
  const body = JSON.stringify({ refreshToken: 'r'.repeat(32), issuer: ISSUER, sub: 'test-user', session_version: 3 });
  const headers = { 'content-type': 'application/json' };
  assert.equal((await fetch(base + '/passby/api/auth/refresh', { method: 'POST', body, headers: { ...headers, origin: 'https://attacker.invalid' } })).status, 403);
  assert.equal((await fetch(base + '/api/auth/refresh', { method: 'POST', body, headers })).status, 400);
  assert.equal((await fetch(base + '/passby/api/auth/refresh', { method: 'POST', body })).status, 415);
  const refreshed = await fetch(base + '/passby/api/auth/refresh', { method: 'POST', body, headers });
  assert.equal(refreshed.status, 200); const next = await refreshed.json();
  const logout = await fetch(base + '/passby/api/auth/logout', { method: 'POST', headers: { ...headers, authorization: `Bearer ${next.token}` }, body: JSON.stringify({ refreshToken: next.refreshToken }) });
  assert.equal(logout.status, 200); assert.equal(revoked, next.refreshToken);
  assert.equal((await fetch(base + '/passby/api/auth/session', { headers: { authorization: `Bearer ${next.token}` } })).status, 401);
});


test('only a known login method reaches the authorization request', async () => {
  const f = fixture(); let options;
  const build = f.auth.protocol.buildAuthorizationUrl;
  f.auth.protocol.buildAuthorizationUrl = (config, values) => { options = values; return build(config, values); };
  await begin(f, '?format=json&method=apple');
  assert.equal(options.tenon_method, 'apple');
  await begin(f, '?format=json&method=https://evil.test');
  assert.equal(options.tenon_method, undefined);
  await begin(f, '?format=json');
  assert.equal(options.tenon_method, undefined);
});
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

test('both Tenon issuers name the same account, and each PassBy host gets its own callback', async () => {
  const NEXT = ISSUERS.find(issuer => issuer !== ISSUER); let live = false, options;
  const f = fixture({ hosts: ['https://tenon.asia', 'https://passby.tenonai.cn'] });
  f.protocol.discovery = async url => { if (url.href === NEXT && !live) throw Error('Not answering'); return { serverMetadata: () => ({ issuer: url.href }) }; };
  const build = f.protocol.buildAuthorizationUrl;
  f.protocol.buildAuthorizationUrl = (config, values) => { options = values; return build(config, values); };
  assert.equal(await f.auth.currentIssuer(), ISSUER);
  live = true; assert.equal(await f.auth.currentIssuer(), ISSUER);
  f.advance(10 * 60 * 1000); assert.equal(await f.auth.currentIssuer(), NEXT);
  f.claims.iss = NEXT;
  const start = 'https://passby.tenonai.cn/passby/api/auth/start';
  await f.auth.start(f.req, f.res, new URL(start));
  assert.equal(options.redirect_uri, 'https://passby.tenonai.cn/passby/api/auth/callback');
  f.req.headers.cookie = f.res.headers['Set-Cookie'].split(';')[0];
  await assert.rejects(f.auth.complete(f.req, f.res, callback()), { status: 401 });
  await f.auth.start(f.req, f.res, new URL(start));
  f.req.headers.cookie = f.res.headers['Set-Cookie'].split(';')[0];
  await f.auth.complete(f.req, f.res, new URL('https://passby.tenonai.cn/passby/api/auth/callback?code=test&state=state'));
  f.req.headers.cookie = f.res.headers['Set-Cookie'][1].split(';')[0];
  assert.equal(f.auth.identity(f.req).session.issuer, ISSUER);
  await assert.rejects(f.auth.start(f.req, f.res, new URL('https://passby.tenon.asia/passby/api/auth/start')), { status: 403 });
  assert.equal(f.auth.publicOrigin({ headers: { host: 'passby.tenonai.cn' } }), 'https://passby.tenonai.cn');
  assert.equal(f.auth.publicOrigin({ headers: { host: 'attacker.invalid' } }), 'https://tenon.asia');
  live = false; f.advance(10 * 60 * 1000); assert.equal(await f.auth.currentIssuer(), ISSUER);
  live = true; const grant = f.protocol.authorizationCodeGrant;
  f.protocol.authorizationCodeGrant = async () => { throw Error('Moved'); }; await begin(f);
  await assert.rejects(f.auth.complete(f.req, f.res, callback()));
  assert.equal(await f.auth.currentIssuer(), NEXT); f.protocol.authorizationCodeGrant = grant;
  f.claims.iss = 'https://attacker.invalid/api/auth'; await begin(f);
  await assert.rejects(f.auth.complete(f.req, f.res, callback()), { status: 401 });
});

test('before S2 the revocation command ends every iPhone session and refresh credential but no web session', async t => {
  const db = persistentStores(t), store = db.open(), now = Date.now(), native = 'https://tenon.asia', web = 'https://passby.tenon.asia';
  const person = { issuer: ISSUER, sub: 'test-user', name: 'Example', role: 'user', expires: now + TTL }, first = 'a'.repeat(32), second = 'b'.repeat(32);
  store.create(native, digest('old-app-token'), person, now, { nativeRefreshHash: digest(first) });
  store.create(native, digest('new-app-token'), person, now, { nativeRefreshHash: digest(second), retireRefreshHash: digest(first) });
  store.create(web, digest('web-token'), person, now);
  const run = spawnSync(process.execPath, ['revoke-sessions.mjs', native], { cwd: new URL('..', import.meta.url), env: { ...process.env, SESSION_DB: db.path }, encoding: 'utf8' });
  assert.equal(run.status, 0, run.stderr); assert.deepEqual(JSON.parse(run.stdout), { sessions: 1, credentials: 2 });
  assert.equal(store.get(native, digest('new-app-token'), now), undefined);
  for (const refresh of [first, second]) assert.throws(() => store.assertRefresh(native, ISSUER, 'test-user', digest(refresh), now), { status: 401 });
  assert.equal(store.get(web, digest('web-token'), now).sub, 'test-user');
  const f = fixture({ sessionStore: store, now: Date.now }), server = createApp(f.auth);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve)); t.after(() => server.close());
  const base = `http://127.0.0.1:${server.address().port}/passby/api/auth/`;
  assert.equal((await fetch(base + 'session', { headers: { authorization: 'Bearer ' + 'x'.repeat(43) } })).status, 401);
  const refreshed = await fetch(base + 'refresh', { method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ refreshToken: second, issuer: ISSUER, sub: 'test-user', session_version: 3 }) });
  assert.equal(refreshed.status, 401);
});

function persistentStores(t) {
  const directory = mkdtempSync(join(tmpdir(), 'passby-sessions-')), path = join(directory, 'sessions.sqlite'), stores = [];
  const open = () => { const store = new SessionStore(path); stores.push(store); return store; };
  t.after(() => { for (const store of stores) { try { store.close(); } catch {} } rmSync(directory, { recursive: true, force: true }); });
  return { directory, path, open };
}
const bearer = token => ({ headers: { authorization: `Bearer ${token}` } });
test('a separate process after restart restores only product identity and its original absolute deadline', async t => {
  const db = persistentStores(t), store = db.open(), f = fixture({ sessionStore: store });
  f.tokens.access_token = 'central-access-test-fixture'; f.tokens.refresh_token = 'refresh-test-fixture'.repeat(3);
  await begin(f); await f.auth.complete(f.req, f.res, callback());
  const cookie = f.res.headers['Set-Cookie'][1].split(';')[0]; f.req.headers.cookie = cookie;
  const original = f.auth.identity(f.req).session, key = f.auth.identity(f.req).key;
  const native = await rememberedGrant(f), nativeKey = digest(native.token);
  store.close();
  const child = spawnSync(process.execPath, ['--input-type=module', '-e', `
    import { SessionStore } from ${JSON.stringify(new URL('../sessions.mjs', import.meta.url).href)};
    const store = new SessionStore(process.argv[1]);
    console.log(JSON.stringify([store.get('https://tenon.asia', process.argv[2], Number(process.argv[4])),
      store.get('https://tenon.asia', process.argv[3], Number(process.argv[4]))])); store.close();
  `, db.path, key, nativeKey, String(f.time() + TTL - 1)], { encoding: 'utf8' });
  assert.equal(child.status, 0, child.stderr);
  assert.deepEqual(JSON.parse(child.stdout), [original, native.identity]);
  const reopened = fixture({ sessionStore: db.open() }); reopened.advance(TTL - 1);
  assert.equal(reopened.auth.identity({ headers: { cookie } }).session.expires, original.expires);
  assert.equal(reopened.grants(), 0); reopened.advance(1);
  assert.throws(() => reopened.auth.identity({ headers: { cookie } }), { status: 401 });
  assert.equal(reopened.auth.sessionCount, 0);
  assert.equal(statSync(db.directory).mode & 0o777, 0o700); assert.equal(statSync(db.path).mode & 0o777, 0o600);
  const persisted = readFileSync(db.path).toString('latin1');
  for (const value of [native.token, cookie.split('=')[1], f.tokens.access_token, f.tokens.refresh_token, 'verifier']) assert.equal(persisted.includes(value), false);
});
test('running and candidate connections share login, immediate logout and refresh revocation while origins stay isolated', async t => {
  const db = persistentStores(t), first = fixture({ sessionStore: db.open() }), candidate = fixture({ sessionStore: db.open() });
  const web = fixture({ origin: 'https://passby.tenon.asia', sessionStore: candidate.auth.sessionStore });
  const grant = await rememberedGrant(first);
  assert.deepEqual(candidate.auth.identity(bearer(grant.token)).session, grant.identity);
  assert.throws(() => web.auth.identity(bearer(grant.token)), { status: 401 });
  candidate.auth.logout(bearer(grant.token));
  assert.throws(() => first.auth.identity(bearer(grant.token)), { status: 401 });
  const device = await rememberedGrant(first), otherDevice = await rememberedGrant(candidate);
  const key = digest(device.token), refreshHash = digest(device.refreshToken), now = first.time();
  web.auth.sessionStore.create(web.auth.origin, key, device.identity, now, { nativeRefreshHash: refreshHash });
  candidate.protocol.tokenRevocation = async () => {};
  await candidate.auth.revoke({ refreshToken: device.refreshToken });
  for (const token of [device.token, otherDevice.token]) assert.throws(() => first.auth.identity(bearer(token)), { status: 401 });
  assert.equal(web.auth.identity(bearer(device.token)).session.expires, device.identity.expires);
  const restarted = fixture({ sessionStore: db.open() });
  for (const token of [grant.token, device.token, otherDevice.token]) assert.throws(() => restarted.auth.identity(bearer(token)), { status: 401 });
  web.auth.logout(bearer(device.token));
  assert.equal(db.open().get(web.auth.origin, key, now), undefined);
});
test('SQLite serializes writes across real processes and bounds expiry cleanup to each origin', async t => {
  const db = persistentStores(t), first = db.open(), second = db.open(), now = 1000000;
  const person = { issuer: ISSUER, sub: 'test-user', name: 'Example', role: 'user', expires: now + TTL };
  const key = digest('first-test-token'); first.create('https://tenon.asia', key, person, now);
  first.create('https://passby.tenon.asia', key, person, now);
  const child = spawn(process.execPath, ['--input-type=module', '-e', `
    import { DatabaseSync } from 'node:sqlite';
    const db = new DatabaseSync(process.argv[1]); db.exec('BEGIN IMMEDIATE');
    db.prepare('UPDATE product_sessions SET name=? WHERE origin=?').run('Concurrent', 'https://tenon.asia');
    console.log('locked'); setTimeout(() => { db.exec('COMMIT'); db.close(); }, 300);
  `, db.path], { stdio: ['ignore', 'pipe', 'pipe'] });
  let stderr = ''; child.stderr.on('data', value => { stderr += value; });
  const completed = new Promise((resolve, reject) => { child.once('error', reject); child.once('exit', code => code === 0 ? resolve() : reject(Error(stderr))); });
  await new Promise((resolve, reject) => { child.stdout.once('data', resolve); child.once('error', reject); child.once('exit', code => { if (code !== 0) reject(Error(stderr)); }); });
  second.create('https://tenon.asia', digest('second-test-token'), person, now);
  await completed;
  assert.equal(first.get('https://tenon.asia', key, now).name, 'Concurrent');
  second.prune('https://tenon.asia', person.expires);
  assert.equal(first.count('https://tenon.asia', now), 0);
  assert.equal(first.count('https://passby.tenon.asia', now), 1);
  assert.equal(first.get('https://passby.tenon.asia', key, person.expires), undefined);
});
test('failed rotation inserts roll back retirement and capacity is checked inside the transaction', t => {
  const db = persistentStores(t), store = db.open(), now = 1000000, key = digest('original-test-token'), oldHash = digest('original-test-refresh');
  const person = { issuer: ISSUER, sub: 'test-user', name: 'Example', role: 'user', expires: now + TTL };
  store.create('https://tenon.asia', key, person, now, { nativeRefreshHash: oldHash });
  const sql = new DatabaseSync(db.path); t.after(() => sql.close());
  sql.exec("CREATE TRIGGER reject_session BEFORE INSERT ON product_sessions BEGIN SELECT RAISE(ABORT, 'test write failure'); END");
  assert.throws(() => store.create('https://tenon.asia', digest('new-test-token'), person, now,
    { nativeRefreshHash: digest('new-test-refresh'), retireRefreshHash: oldHash }), { status: 503 });
  assert.deepEqual(store.get('https://tenon.asia', key, now), person); assert.equal(store.count('https://tenon.asia', now), 1);
  sql.exec('DROP TRIGGER reject_session; BEGIN IMMEDIATE');
  const insert = sql.prepare('INSERT INTO product_sessions VALUES(?,?,?,?,?,?,?,NULL)');
  for (let i = 1; i < 5000; i++) insert.run('https://tenon.asia', digest('capacity-fixture-' + i), ISSUER, person.sub, person.name, person.role, person.expires);
  sql.exec('COMMIT');
  assert.throws(() => store.create('https://tenon.asia', digest('overflow'), person, now), { status: 429 });
  assert.equal(store.count('https://tenon.asia', now), 5000);
  store.create('https://tenon.asia', digest('replacement'), person, now,
    { nativeRefreshHash: digest('replacement-refresh'), retireRefreshHash: oldHash });
  assert.equal(store.get('https://tenon.asia', key, now), undefined);
  assert.equal(store.count('https://tenon.asia', now), 5000);
});
test('database failures cannot sign in, exchange, renew, log out successfully or pass health', async t => {
  const db = persistentStores(t), store = db.open(), f = fixture({ sessionStore: store });
  await begin(f); store.close();
  await assert.rejects(f.auth.complete(f.req, f.res, callback()), { status: 503 });
  assert.equal(Array.isArray(f.res.headers['Set-Cookie']), false);
  assert.throws(() => f.auth.identity(bearer('t'.repeat(43))), { status: 503 });
  await assert.rejects(f.auth.refresh({ refreshToken: 'r'.repeat(32), issuer: ISSUER, sub: 'test-user', session_version: 3 }), { status: 503 });
  let revocations = 0; f.protocol.tokenRevocation = async () => { revocations++; };
  await assert.rejects(f.auth.revoke({ refreshToken: 'r'.repeat(32) }), { status: 503 }); assert.equal(revocations, 0);
  const server = createApp(f.auth); await new Promise(resolve => server.listen(0, '127.0.0.1', resolve)); t.after(() => server.close());
  const origin = `http://127.0.0.1:${server.address().port}`;
  assert.equal((await fetch(origin + '/passby/api/health')).status, 503);
  assert.equal((await fetch(origin + '/passby/api/auth/logout', { method: 'POST', headers: { origin: f.auth.origin } })).status, 503);
  const healthy = db.open(), native = fixture({ sessionStore: healthy }), verifier = 'v'.repeat(43), state = 's'.repeat(43);
  await begin(native, `?platform=ios&session_version=3&challenge=${digest(verifier)}&state=${state}`);
  await native.auth.complete(native.req, native.res, callback(true));
  const ticket = new URL(native.res.headers.Location).searchParams.get('ticket');
  const sql = new DatabaseSync(db.path); t.after(() => sql.close());
  sql.exec("CREATE TRIGGER reject_session BEFORE INSERT ON product_sessions BEGIN SELECT RAISE(ABORT, 'test write failure'); END");
  assert.throws(() => native.auth.exchange({ ticket, verifier, state }), { status: 503 });
  assert.equal(native.auth.tickets.size, 1); assert.equal(native.auth.sessionCount, 0);
  sql.exec('DROP TRIGGER reject_session');
  const original = native.auth.exchange({ ticket, verifier, state });
  native.protocol.refreshTokenGrant = async () => ({ ...native.tokens, refresh_token: 'n'.repeat(32) });
  sql.exec("CREATE TRIGGER reject_session BEFORE INSERT ON product_sessions BEGIN SELECT RAISE(ABORT, 'test write failure'); END");
  await assert.rejects(native.auth.refresh({ refreshToken: original.refreshToken, issuer: ISSUER, sub: original.identity.sub, session_version: 3 }), { status: 503 });
  assert.equal(native.auth.identity(bearer(original.token)).session.expires, original.identity.expires);
  assert.equal(native.auth.sessionCount, 1);
});
test('unsafe permissions, corrupt databases and unknown schemas fail closed without a memory fallback', t => {
  const db = persistentStores(t); db.open().close();
  chmodSync(db.path, 0o644); assert.throws(() => new SessionStore(db.path), { status: 503 }); chmodSync(db.path, 0o600);
  chmodSync(db.directory, 0o755); assert.throws(() => new SessionStore(db.path), { status: 503 }); chmodSync(db.directory, 0o700);
  const sql = new DatabaseSync(db.path); sql.exec('PRAGMA user_version=2'); sql.close();
  assert.throws(() => new SessionStore(db.path), { status: 503 });
  writeFileSync(db.path, 'test-only malformed database'); assert.throws(() => new SessionStore(db.path), { status: 503 });
});
test('two connections reject a late refresh after local logout, even while central revocation is still in flight', async t => {
  const db = persistentStores(t), first = fixture({ sessionStore: db.open() }), second = fixture({ sessionStore: db.open() });
  const original = await rememberedGrant(first);
  first.protocol.refreshTokenGrant = async () => ({ ...first.tokens, refresh_token: 'n'.repeat(32) });
  let finishIdentity, markIdentity, finishRevocation, markRevocation;
  const checking = new Promise(resolve => { markIdentity = resolve; }), revoking = new Promise(resolve => { markRevocation = resolve; });
  first.protocol.fetchUserInfo = async () => { await new Promise(resolve => { finishIdentity = resolve; markIdentity(); }); return first.info; };
  second.protocol.tokenRevocation = async () => { await new Promise(resolve => { finishRevocation = resolve; markRevocation(); }); };
  const refreshing = first.auth.refresh({ refreshToken: original.refreshToken, issuer: ISSUER, sub: original.identity.sub, session_version: 3 });
  const rejected = assert.rejects(refreshing, { status: 401 });
  await checking;
  const logout = second.auth.revoke({ refreshToken: original.refreshToken }); await revoking;
  assert.throws(() => first.auth.identity(bearer(original.token)), { status: 401 });
  finishIdentity(); await rejected;
  assert.equal(first.auth.sessionCount, 0);
  finishRevocation(); await logout;
  const restarted = db.open();
  assert.throws(() => restarted.create(first.auth.origin, digest('late-fixture'), original.identity, first.time(),
    { nativeRefreshHash: digest('n'.repeat(32)), retireRefreshHash: digest(original.refreshToken) }), { status: 401 });
});
test('logout using an old credential removes committed successors before a delayed refresh response reaches the device', async t => {
  const db = persistentStores(t), first = fixture({ sessionStore: db.open() }), second = fixture({ sessionStore: db.open() });
  const original = await rememberedGrant(first), body = { refreshToken: original.refreshToken, issuer: ISSUER, sub: original.identity.sub, session_version: 3 };
  first.protocol.refreshTokenGrant = async () => ({ ...first.tokens, refresh_token: 'n'.repeat(32) });
  const next = await first.auth.refresh(body); // Committed response, not yet adopted by the simulated device.
  first.protocol.refreshTokenGrant = async () => ({ ...first.tokens, refresh_token: 'p'.repeat(32) });
  const descendant = await first.auth.refresh({ ...body, refreshToken: next.refreshToken });
  const web = fixture({ origin: 'https://passby.tenon.asia', sessionStore: db.open() });
  web.auth.sessionStore.create(web.auth.origin, digest(descendant.token), descendant.identity, web.time(), { nativeRefreshHash: digest(descendant.refreshToken) });
  second.protocol.tokenRevocation = async () => { throw Error('test central outage'); };
  await assert.rejects(second.auth.revoke({ refreshToken: original.refreshToken }));
  for (const value of [original, next, descendant]) assert.throws(() => first.auth.identity(bearer(value.token)), { status: 401 });
  assert.equal(web.auth.identity(bearer(descendant.token)).session.expires, descendant.identity.expires);
  first.protocol.refreshTokenGrant = async () => ({ ...first.tokens, refresh_token: descendant.refreshToken });
  await assert.rejects(first.auth.refresh(body), { status: 401 });
  const restarted = db.open();
  assert.throws(() => restarted.create(first.auth.origin, digest('replay-fixture'), descendant.identity, first.time(),
    { nativeRefreshHash: digest(descendant.refreshToken) }), { status: 401 });
});
test('refresh digest history and revocation markers expire at 30 days and refuse capacity overflow atomically', t => {
  const db = persistentStores(t), store = db.open(), now = 1000000;
  const person = { issuer: ISSUER, sub: 'test-user', name: 'Example', role: 'user', expires: now + TTL };
  const first = digest('r-fixture'), next = digest('n-fixture');
  store.create('https://tenon.asia', digest('old-access'), person, now, { nativeRefreshHash: first });
  store.create('https://tenon.asia', digest('new-access'), person, now, { nativeRefreshHash: next, retireRefreshHash: first });
  store.revoke('https://tenon.asia', first, now);
  const sql = new DatabaseSync(db.path); t.after(() => sql.close());
  store.prune('https://tenon.asia', now + TTL - 1);
  assert.equal(sql.prepare('SELECT count(*) AS count FROM revoked_refresh').get().count, 2);
  assert.equal(sql.prepare('SELECT count(*) AS count FROM refresh_rotations').get().count, 1);
  store.prune('https://tenon.asia', now + TTL);
  for (const table of ['revoked_refresh', 'refresh_rotations']) assert.equal(sql.prepare(`SELECT count(*) AS count FROM ${table}`).get().count, 0);
  sql.exec('BEGIN IMMEDIATE');
  const mark = sql.prepare('INSERT INTO revoked_refresh VALUES(?,?,?)'), rotate = sql.prepare('INSERT INTO refresh_rotations VALUES(?,?,?,?)');
  for (let i = 0; i < 50000; i++) {
    mark.run('https://tenon.asia', digest('revoked-capacity-' + i), now + TTL);
    rotate.run('https://tenon.asia', digest('rotation-capacity-' + i), digest('rotated-capacity-' + i), now + TTL);
  }
  sql.exec('COMMIT');
  assert.throws(() => store.revoke('https://tenon.asia', first, now), { status: 429 });
  assert.throws(() => store.create('https://tenon.asia', digest('over-capacity-access'), person, now,
    { nativeRefreshHash: next, retireRefreshHash: first }), { status: 429 });
  assert.equal(store.count('https://tenon.asia', now), 0);
  assert.equal(sql.prepare('SELECT count(*) AS count FROM revoked_refresh').get().count, 50000);
  assert.equal(sql.prepare('SELECT count(*) AS count FROM refresh_rotations').get().count, 50000);
});
