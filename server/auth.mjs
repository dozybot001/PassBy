import * as oidc from 'openid-client';
import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';

export const ISSUER = 'https://account.tenon.asia/api/auth';
export const ROLE = 'https://tenon.asia/claims/platform_role';
export const TTL = 15 * 60 * 1000;
const token = () => randomBytes(32).toString('base64url');
export const digest = value => createHash('sha256').update(value).digest('base64url');
const equal = (a, b) => typeof a === 'string' && typeof b === 'string' && a.length === b.length && timingSafeEqual(Buffer.from(a), Buffer.from(b));
const failure = status => Object.assign(new Error('Authentication unavailable'), { status });

// Identity-only BFF: no notebook, recovery key, Apple token or password storage.
// Central tokens are discarded after the callback; opaque product sessions expire.
export class TenonAuth {
  constructor({ origin = 'https://tenon.asia', clientId, clientSecret, iosClientId, iosClientSecret, protocol = oidc, now = Date.now }) {
    if (origin !== 'https://tenon.asia' || !clientId || !clientSecret) throw Error('Incomplete authentication configuration');
    Object.assign(this, { origin, clientId, clientSecret, iosClientId, iosClientSecret, protocol, now });
    this.callback = origin + '/passby/api/auth/callback';
    this.iosCallback = origin + '/passby/api/auth/ios/callback';
    this.attempts = new Map(); this.sessions = new Map(); this.tickets = new Map();
  }
  sweep() {
    for (const map of [this.attempts, this.sessions, this.tickets]) for (const [key, value] of map) if (value.expires <= this.now()) map.delete(key);
  }
  async config(native = false) {
    if (native && (!this.iosClientId || !this.iosClientSecret)) throw failure(503);
    const slot = native ? 'iosConfiguration' : 'configuration';
    if (!this[slot]) {
      const config = await this.protocol.discovery(new URL(ISSUER), native ? this.iosClientId : this.clientId, undefined,
        this.protocol.ClientSecretBasic(native ? this.iosClientSecret : this.clientSecret), { timeout: 10, execute: [this.protocol.enableNonRepudiationChecks] });
      if (config.serverMetadata().issuer !== ISSUER) throw failure(503);
      this[slot] = config;
    }
    return this[slot];
  }
  cookie(name, value, age, sameSite = 'Strict') {
    return `__Secure-passby_${name}=${value}; Path=/passby/api; HttpOnly; Secure; SameSite=${sameSite}; Max-Age=${age}`;
  }
  cookieValue(req, name) {
    return req.headers.cookie?.match(new RegExp(`(?:^|;\\s*)__Secure-passby_${name}=([A-Za-z0-9_-]{43})(?:;|$)`))?.[1];
  }
  identity(req) {
    this.sweep();
    const bearer = req.headers.authorization?.match(/^Bearer ([A-Za-z0-9_-]{43})$/)?.[1];
    const key = digest(bearer || this.cookieValue(req, 'session') || '');
    const session = this.sessions.get(key);
    if (!session || session.expires <= this.now()) throw failure(401);
    return { key, session };
  }
  async start(req, res, url) {
    if (req.headers['sec-fetch-site'] === 'cross-site') throw failure(403);
    this.sweep();
    if (this.attempts.size >= 1000 || this.sessions.size >= 5000) throw failure(429);
    const native = url.searchParams.get('platform') === 'ios';
    const challenge = url.searchParams.get('challenge'), nativeState = url.searchParams.get('state');
    if (native && (!/^[A-Za-z0-9_-]{43}$/.test(challenge || '') || !/^[A-Za-z0-9_-]{43}$/.test(nativeState || ''))) throw failure(400);
    const config = await this.config(native), browser = token(), verifier = this.protocol.randomPKCECodeVerifier();
    const state = this.protocol.randomState(), nonce = this.protocol.randomNonce();
    const location = this.protocol.buildAuthorizationUrl(config, { redirect_uri: native ? this.iosCallback : this.callback, scope: 'openid profile email', state, nonce,
      code_challenge: await this.protocol.calculatePKCECodeChallenge(verifier), code_challenge_method: 'S256' });
    this.attempts.set(digest(browser), { verifier, state, nonce, expires: this.now() + 600000, native, challenge, nativeState });
    res.setHeader('Set-Cookie', this.cookie('attempt', browser, 600, 'Lax'));
    res.writeHead(303, { Location: location.href }).end();
  }
  async complete(req, res, url) {
    const key = digest(this.cookieValue(req, 'attempt') || ''), attempt = this.attempts.get(key);
    this.attempts.delete(key);
    res.setHeader('Set-Cookie', this.cookie('attempt', '', 0, 'Lax'));
    if (!attempt || attempt.expires <= this.now() || url.pathname !== (attempt.native ? new URL(this.iosCallback).pathname : new URL(this.callback).pathname)) throw failure(401);
    const config = await this.config(attempt.native);
    const tokens = await this.protocol.authorizationCodeGrant(config, url, { pkceCodeVerifier: attempt.verifier,
      expectedState: attempt.state, expectedNonce: attempt.nonce, idTokenExpected: true });
    const claims = tokens.claims();
    if (!claims || claims.iss !== ISSUER || typeof claims.sub !== 'string' || !claims.sub || !tokens.access_token || !(tokens.expires_in > 0)) throw failure(401);
    const info = await this.protocol.fetchUserInfo(config, tokens.access_token, claims.sub);
    if (info.sub !== claims.sub || info.email_verified !== true || !['admin', 'user'].includes(info[ROLE]) || claims[ROLE] !== info[ROLE]) throw failure(403);
    const expires = Math.min(this.now() + TTL, this.now() + tokens.expires_in * 1000, claims.exp * 1000);
    if (!Number.isFinite(expires) || expires <= this.now()) throw failure(401);
    const session = { issuer: ISSUER, sub: claims.sub, name: typeof info.name === 'string' ? info.name.slice(0, 120) : 'Tenon', role: info[ROLE], expires };
    if (attempt.native) {
      const ticket = token();
      this.tickets.set(digest(ticket), { ...attempt, session, expires: Math.min(expires, this.now() + 60000) });
      // A fixed product callback, never a caller-provided redirect. The ticket
      // is useless without the verifier held by the initiating iPhone.
      res.writeHead(303, { Location: `passby://auth?ticket=${ticket}&state=${attempt.nativeState}` }).end();
    } else {
      const sessionToken = token(); this.sessions.set(digest(sessionToken), session);
      res.setHeader('Set-Cookie', [this.cookie('attempt', '', 0, 'Lax'), this.cookie('session', sessionToken, Math.floor((expires - this.now()) / 1000))]);
      res.writeHead(303, { Location: '/passby/' }).end();
    }
  }
  exchange(body) {
    this.sweep();
    if (!/^[A-Za-z0-9_-]{43}$/.test(body.ticket || '') || !/^[A-Za-z0-9_-]{43,128}$/.test(body.verifier || '')) throw failure(400);
    const key = digest(body.ticket), ticket = this.tickets.get(key);
    // An intercepted ticket cannot consume the legitimate flow without PKCE.
    if (!ticket || ticket.expires <= this.now() || !equal(digest(body.verifier), ticket.challenge) || !equal(body.state, ticket.nativeState)) throw failure(401);
    this.tickets.delete(key);
    const sessionToken = token(); this.sessions.set(digest(sessionToken), ticket.session);
    return { token: sessionToken, identity: ticket.session };
  }
}

export async function readBody(req) {
  let body = '';
  for await (const chunk of req) { body += chunk; if (body.length > 2048) throw failure(413); }
  try { return JSON.parse(body); } catch { throw failure(400); }
}
