import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { mkdtempSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { SessionStore } from '../sessions.mjs';
import { TenonAuth, ISSUER, ROLE, TTL, digest } from '../auth.mjs';
import { ProductDeletion } from '../product-deletion.mjs';
import { createApp } from '../server.mjs';

const operationId = randomUUID(), grant = 'g'.repeat(43), now = 1000000;
const identity = sub => ({ issuer: ISSUER, sub, name: 'Example', role: 'user', expires: now + TTL });
const origins = ['https://tenon.asia', 'https://passby.tenon.asia'];
function fixture(store = new SessionStore(':memory:')) {
  const auth = new TenonAuth({ clientId: 'fixture', clientSecret: 'fixture-only', sessionStore: store, now: () => now });
  const options = { productId: 'passby', sub: 'person', operationId };
  const transport = async (url, init) => {
    assert.equal(init.redirect, 'error'); assert.match(init.headers.Authorization, /^Basic /);
    if (url.endsWith('/finish') && options.failFinish) throw Error('Fixture network failure');
    return Response.json(url.endsWith('/claim') ? { issuer: ISSUER, ...options } : url.endsWith('/start') ?
      { url: options.url || `https://account.tenon.asia/account/delete/?request=${grant}`, expiresAt: 'expiresAt' in options ? options.expiresAt : now + 10000 } : { status: 'completed' });
  };
  return { auth, store, options, transport, service: new ProductDeletion({ auth, transport }) };
}
test('deletion covers web and native sessions, persists and never erases a later login on retry', async t => {
  const directory = mkdtempSync(join(tmpdir(), 'passby-deletion-')); t.after(() => rmSync(directory, { recursive: true, force: true }));
  const path = join(directory, 'sessions.sqlite'), store = new SessionStore(path), f = fixture(store);
  for (const origin of origins) {
    store.create(origin, digest(origin), identity('person'), now, { nativeRefreshHash: digest('old-' + origin) });
    store.create(origin, digest('other-' + origin), identity('other'), now);
  }
  assert.deepEqual(await f.service.execute({ operationId, grant }), { operationId, status: 'completed', deleted: true });
  for (const origin of origins) {
    assert.equal(store.get(origin, digest(origin), now), undefined);
    assert.equal(store.get(origin, digest('other-' + origin), now).sub, 'other');
    assert.throws(() => store.assertRefresh(origin, ISSUER, 'person', digest('old-' + origin), now), { status: 401 });
  }
  store.close();
  const restarted = new SessionStore(path), again = fixture(restarted); t.after(() => restarted.close());
  restarted.create(origins[0], digest('new-login'), identity('person'), now, { nativeRefreshHash: digest('new-refresh') });
  await again.service.execute({ operationId, grant });
  assert.equal(restarted.get(origins[0], digest('new-login'), now).sub, 'person');
  restarted.assertRefresh(origins[0], ISSUER, 'person', digest('new-refresh'), now);
  assert.throws(() => restarted.assertRefresh(origins[0], ISSUER, 'person', digest('lost-old-credential'), now), { status: 401 });
});
test('deletion invalidates late callbacks and tickets across two persistent connections', async t => {
  const directory = mkdtempSync(join(tmpdir(), 'passby-generation-')); t.after(() => rmSync(directory, { recursive: true, force: true }));
  const first = new SessionStore(join(directory, 'sessions.sqlite')), second = new SessionStore(join(directory, 'sessions.sqlite'));
  t.after(() => { first.close(); second.close(); });
  const before = first.generation(); second.deleteProduct(ISSUER, 'person', operationId, now);
  assert.throws(() => first.create(origins[0], digest('late'), identity('person'), now, { authorizationGeneration: before }), { status: 401 });
  first.create(origins[0], digest('other'), identity('other'), now, { authorizationGeneration: before });
  assert.equal(first.get(origins[0], digest('other'), now).sub, 'other');
});
test('completed local deletion remains true during central outage; malformed or cross-product proofs have no effect', async () => {
  const f = fixture(); f.store.create(origins[0], digest('local'), identity('person'), now);
  for (const change of [{ productId: 'agenthub' }, { issuer: 'https://attacker.invalid' }, { operationId: randomUUID() }]) {
    Object.assign(f.options, { productId: 'passby', issuer: ISSUER, operationId }, change);
    await assert.rejects(f.service.execute({ operationId, grant }), { status: 403 });
    assert.equal(f.auth.sessionCount, 1);
  }
  Object.assign(f.options, { productId: 'passby', issuer: ISSUER, operationId, failFinish: true });
  await assert.rejects(f.service.execute({ operationId, grant, sub: 'forged' }), { status: 400 });
  assert.equal((await f.service.execute({ operationId, grant })).deleted, true);
  assert.equal(f.auth.sessionCount, 0);
  f.options.sub = 'different-person'; await assert.rejects(f.service.execute({ operationId, grant }), { status: 401 });
  f.store.close();
});
test('execute accepts only POST and verified grants; start requires the current local identity and origin', async t => {
  const f = fixture(); t.after(() => f.store.close());
  f.store.create(origins[0], digest('t'.repeat(43)), identity('person'), now);
  const server = createApp(f.auth, null, { deletionTransport: f.transport }); await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => server.close()); const endpoint = `http://127.0.0.1:${server.address().port}/passby/api/auth/tenon/delete/`;
  assert.equal((await fetch(endpoint + 'execute')).status, 405); assert.equal(f.auth.sessionCount, 1);
  const headers = { 'Content-Type': 'application/json', Authorization: 'Bearer ' + 't'.repeat(43) };
  assert.equal((await fetch(endpoint + 'start', { method: 'POST', headers: { ...headers, Origin: 'https://attacker.invalid' }, body: '{}' })).status, 403);
  assert.equal((await fetch(endpoint + 'start', { method: 'POST', headers, body: '{"sub":"forged"}' })).status, 400);
  assert.equal((await fetch(endpoint + 'start', { method: 'POST', headers, body: '{}' })).status, 200);
  f.options.url = 'https://attacker.invalid/account/delete/';
  assert.equal((await fetch(endpoint + 'start', { method: 'POST', headers, body: '{}' })).status, 503);
  assert.equal((await fetch(endpoint + 'execute', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ operationId, grant }) })).status, 200);
  assert.equal(f.auth.sessionCount, 0);
});
test('database failure never reports deletion success', async () => {
  const f = fixture(); f.store.close();
  await assert.rejects(f.service.execute({ operationId, grant }), { status: 503 });
});
test('the real native ticket and in-flight refresh cannot restore a deleted subject', async () => {
  for (const phase of ['ticket', 'refresh', 'callback']) {
    const f = fixture(), verifier = 'v'.repeat(43), nativeState = 's'.repeat(43);
    let resolveInfo;
    const info = { sub: 'person', name: 'Example', email_verified: true, [ROLE]: 'user' };
    const tokens = { claims: () => ({ iss: ISSUER, sub: 'person', exp: now / 1000 + 3600, [ROLE]: 'user' }), access_token: 'fixture-only', refresh_token: 'r'.repeat(32), expires_in: 3600, expiresIn: () => 3600 };
    const protocol = {
      discovery: async () => ({ serverMetadata: () => ({ issuer: ISSUER }) }), ClientSecretBasic() {},
      randomPKCECodeVerifier: () => verifier, randomState: () => 'state', randomNonce: () => 'nonce', calculatePKCECodeChallenge: async () => digest(verifier),
      buildAuthorizationUrl: () => new URL('https://account.tenon.asia/authorize'), authorizationCodeGrant: async () => tokens,
      refreshTokenGrant: async () => ({ ...tokens, refresh_token: 'new-'.repeat(10) }), fetchUserInfo: async () => phase === 'ticket' ? info : await new Promise(resolve => { resolveInfo = resolve; }),
    };
    Object.assign(f.auth, { protocol, iosClientId: 'native-fixture', iosClientSecret: 'fixture-only' });
    const req = { headers: {} }, res = { headers: {}, setHeader(k, v) { this.headers[k] = v; }, writeHead(status, headers) { Object.assign(this.headers, headers); return this; }, end() {} };
    let flight;
    if (phase === 'refresh') {
      f.store.create(origins[0], digest('old'), identity('person'), now, { nativeRefreshHash: digest(tokens.refresh_token) });
      flight = f.auth.refresh({ refreshToken: tokens.refresh_token, issuer: ISSUER, sub: 'person', session_version: 3 });
    } else {
      await f.auth.start(req, res, new URL(`${origins[0]}/passby/api/auth/start?platform=ios&session_version=3&challenge=${digest(verifier)}&state=${nativeState}`));
      req.headers.cookie = res.headers['Set-Cookie'].split(';')[0];
      flight = f.auth.complete(req, res, new URL(`${origins[0]}/passby/api/auth/ios/callback?code=fixture&state=state`));
    }
    if (phase === 'ticket') {
      await flight;
      const ticket = new URL(res.headers.Location).searchParams.get('ticket');
      await f.service.execute({ operationId, grant });
      assert.throws(() => f.auth.exchange({ ticket, verifier, state: nativeState }), { status: 401 });
    } else {
      while (!resolveInfo) await new Promise(resolve => setImmediate(resolve));
      await f.service.execute({ operationId, grant }); resolveInfo(info);
      await assert.rejects(flight, { status: 401 });
    }
    assert.equal(f.auth.sessionCount, 0); f.store.close();
  }
});

test('a lost local receipt cannot reuse a central completed operation to delete a new identity', async () => {
 const f = fixture(); f.store.create(origins[0], digest('new-product'), identity('person'), now);
 f.options.completed = true;
 await assert.rejects(f.service.execute({ operationId, grant }), { status: 503 });
 assert.equal(f.auth.sessionCount, 1); f.store.close();
});

test('start and claim have 5-second deadlines; a 2-second finish timeout still returns the committed result', async t => {
  const f = fixture(); t.after(() => f.store.close());
  const token = 't'.repeat(43), durations = [];
  f.store.create(origins[0], digest(token), identity('person'), now);
  const timeoutSignal = milliseconds => {
    durations.push(milliseconds);
    const controller = new AbortController();
    if (milliseconds === 2000) queueMicrotask(() => controller.abort(new DOMException('Fixture deadline', 'TimeoutError')));
    return controller.signal;
  };
  const transport = async (url, init) => {
    if (!url.endsWith('/finish')) return f.transport(url, init);
    assert.equal(f.auth.sessionCount, 0, 'deletion must commit before contacting finish');
    return new Promise((resolve, reject) => {
      init.signal.addEventListener('abort', () => reject(init.signal.reason), { once: true });
    });
  };
  const service = new ProductDeletion({ auth: f.auth, transport, timeoutSignal });
  await service.start({ headers: { authorization: `Bearer ${token}` } });
  assert.deepEqual(await service.execute({ operationId, grant }), { operationId, status: 'completed', deleted: true });
  assert.deepEqual(durations, [5000, 5000, 2000]);
  f.store.create(origins[0], digest('new-after-timeout'), identity('person'), now);
  await service.execute({ operationId, grant });
  assert.equal(f.store.get(origins[0], digest('new-after-timeout'), now).sub, 'person');
});

test('invalid deletion bodies and non-v4 operation IDs reject before requesting any proof', async t => {
  const f = fixture(); t.after(() => f.store.close());
  f.store.create(origins[0], digest('live'), identity('person'), now);
  const service = new ProductDeletion({ auth: f.auth, transport: () => { throw Error('Must not contact central service'); } });
  for (const body of [null, [], 'request', {}, { operationId: [operationId], grant },
    { operationId, grant: [grant] }, { operationId: operationId.slice(0, 14) + '1' + operationId.slice(15), grant },
    { operationId, grant, sub: 'forged' }]) {
    await assert.rejects(service.execute(body), { status: 400 });
    assert.equal(f.auth.sessionCount, 1);
  }
});

test('start accepts only one controlled request query and a future safe-integer expiry', async t => {
  const f = fixture(); t.after(() => f.store.close());
  const token = 't'.repeat(43), request = { headers: { authorization: `Bearer ${token}` } };
  f.store.create(origins[0], digest(token), identity('person'), now);
  const valid = `https://account.tenon.asia/account/delete/?request=${grant}`;
  for (const url of [`${valid}&request=${grant}`, `${valid}&other=1`, `${valid}#extra`,
    valid.replace('account.tenon.asia', 'account.tenon.asia.evil.example'), [valid]]) {
    f.options.url = url;
    await assert.rejects(f.service.start(request), { status: 503 });
  }
  f.options.url = valid;
  for (const expiresAt of [null, `${now + 10000}`, now, now - 1, now + 0.5, Number.MAX_SAFE_INTEGER + 1]) {
    f.options.expiresAt = expiresAt;
    await assert.rejects(f.service.start(request), { status: 503 });
  }
  delete f.options.expiresAt;
  assert.deepEqual(await f.service.start(request), { url: valid, expiresAt: now + 10000 });
});
