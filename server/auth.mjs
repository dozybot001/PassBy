import * as oidc from 'openid-client';
import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';

export const ISSUER = 'https://account.tenon.asia/api/auth';
export const ROLE = 'https://tenon.asia/claims/platform_role';
export const TTL = 30 * 24 * 60 * 60 * 1000;
export const NATIVE_TTL = TTL;
export const REFRESH_TTL = 30 * 24 * 60 * 60 * 1000;
// Builds 11/12 reject longer expiry values; keep their v2 protocol usable
// while v3 clients adopt 30-day sessions. Refresh credentials remain 30 days.
export const LEGACY_NATIVE_TTL = 15 * 60 * 1000;
const token = () => randomBytes(32).toString('base64url');
export const digest = value => createHash('sha256').update(value).digest('base64url');
const equal = (a, b) => typeof a === 'string' && typeof b === 'string' && a.length === b.length && timingSafeEqual(Buffer.from(a), Buffer.from(b));
const failure = status => Object.assign(new Error('Authentication unavailable'), { status });
const validRefresh = value => typeof value === 'string' && /^[A-Za-z0-9._~-]{32,4096}$/.test(value);

// Identity-only BFF: no notebook, recovery key, Apple token or password storage.
// Web tokens are discarded after the callback. Native refresh credentials
// pass through a one-use ticket to the device Keychain, never to cookies, logs
// or disk. Tickets are discarded within 60 seconds.
export class TenonAuth {
  constructor({ origin = 'https://tenon.asia', clientId, clientSecret, iosClientId, iosClientSecret, protocol = oidc, now = Date.now }) {
    if (!['https://tenon.asia', 'https://passby.tenon.asia'].includes(origin) || !clientId || !clientSecret) throw Error('Incomplete authentication configuration');
    Object.assign(this, { origin, clientId, clientSecret, iosClientId, iosClientSecret, protocol, now });
    this.basePath = origin === 'https://tenon.asia' ? '/passby/' : '/';
    this.apiPath = this.basePath + 'api';
    this.callback = origin + this.apiPath + '/auth/callback';
    this.iosCallback = origin + this.apiPath + '/auth/ios/callback';
    this.attempts = new Map(); this.sessions = new Map(); this.tickets = new Map();
    this.refreshing = new Map(); this.refreshLimits = new Map();
    this.nativeSessions = new Map();
  }
  sweep() {
    for (const map of [this.attempts, this.sessions, this.tickets]) for (const [key, value] of map) if (value.expires <= this.now()) map.delete(key);
    for (const [key, value] of this.refreshLimits) if (value.expires <= this.now()) this.refreshLimits.delete(key);
    for (const key of this.nativeSessions.keys()) if (!this.sessions.has(key)) this.nativeSessions.delete(key);
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
    return `__Secure-passby_${name}=${value}; Path=${this.apiPath}; HttpOnly; Secure; SameSite=${sameSite}; Max-Age=${age}`;
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
    const requestedVersion = url.searchParams.get('session_version');
    const sessionVersion = native && ['2', '3'].includes(requestedVersion) ? Number(requestedVersion) : undefined;
    const remembered = sessionVersion !== undefined;
    const challenge = url.searchParams.get('challenge'), nativeState = url.searchParams.get('state');
    if (native && (!/^[A-Za-z0-9_-]{43}$/.test(challenge || '') || !/^[A-Za-z0-9_-]{43}$/.test(nativeState || ''))) throw failure(400);
    const config = await this.config(native), browser = token(), verifier = this.protocol.randomPKCECodeVerifier();
    const state = this.protocol.randomState(), nonce = this.protocol.randomNonce();
    const location = this.protocol.buildAuthorizationUrl(config, { redirect_uri: native ? this.iosCallback : this.callback,
      scope: remembered ? 'openid profile email offline_access' : 'openid profile email', ...(remembered ? { prompt: 'consent' } : {}), state, nonce,
      code_challenge: await this.protocol.calculatePKCECodeChallenge(verifier), code_challenge_method: 'S256' });
    this.attempts.set(digest(browser), { verifier, state, nonce, expires: this.now() + 600000, native, remembered, sessionVersion, challenge, nativeState });
    res.setHeader('Set-Cookie', this.cookie('attempt', browser, 600, 'Lax'));
    if (url.searchParams.get('format') === 'json') {
      res.writeHead(200, { 'Content-Type': 'application/json' }).end(JSON.stringify({ url: location.href }));
    } else res.writeHead(303, { Location: location.href }).end();
  }
  async complete(req, res, url) {
    const key = digest(this.cookieValue(req, 'attempt') || ''), attempt = this.attempts.get(key);
    this.attempts.delete(key);
    res.setHeader('Set-Cookie', this.cookie('attempt', '', 0, 'Lax'));
    if (!attempt || attempt.expires <= this.now() || url.pathname !== (attempt.native ? new URL(this.iosCallback).pathname : new URL(this.callback).pathname)) throw failure(401);
    const config = await this.config(attempt.native);
    const tokens = await this.protocol.authorizationCodeGrant(config, url, { pkceCodeVerifier: attempt.verifier,
      expectedState: attempt.state, expectedNonce: attempt.nonce, idTokenExpected: true });
    const session = await this.verifiedIdentity(config, tokens, attempt.sessionVersion === 2 ? LEGACY_NATIVE_TTL : TTL);
    const refresh = attempt.remembered ? this.refreshCredential(tokens) : {};
    const expires = session.expires;
    if (attempt.native) {
      const ticket = token();
      this.tickets.set(digest(ticket), { ...attempt, session, ...refresh, expires: Math.min(expires, this.now() + 60000) });
      // A fixed product callback, never a caller-provided redirect. The ticket
      // is useless without the verifier held by the initiating iPhone.
      res.writeHead(303, { Location: `passby://auth?ticket=${ticket}&state=${attempt.nativeState}` }).end();
    } else {
      const sessionToken = token(); this.sessions.set(digest(sessionToken), session);
      res.setHeader('Set-Cookie', [this.cookie('attempt', '', 0, 'Lax'), this.cookie('session', sessionToken, Math.floor((expires - this.now()) / 1000))]);
      res.writeHead(303, { Location: this.basePath }).end();
    }
  }
  async verifiedIdentity(config, tokens, ttl = TTL) {
    const claims = tokens.claims();
    if (!claims || claims.iss !== ISSUER || typeof claims.sub !== 'string' || !claims.sub
      || !tokens.access_token || !Number.isFinite(tokens.expires_in) || tokens.expires_in <= 0
      || !Number.isFinite(claims.exp) || claims.exp * 1000 <= this.now()) throw failure(401);
    let info;
    try { info = await this.protocol.fetchUserInfo(config, tokens.access_token, claims.sub); }
    catch (error) {
      if ([401, 403].includes(error.status)) throw failure(401);
      throw failure(503);
    }
    if (info.sub !== claims.sub || info.email_verified !== true || !['admin', 'user'].includes(info[ROLE]) || claims[ROLE] !== info[ROLE]) throw failure(403);
    const verifiedAt = this.now();
    if (claims.exp * 1000 <= verifiedAt || !(tokens.expiresIn() > 0)) throw failure(401);
    // Central tokens must be valid now; the verified product session then has
    // its own lifetime, independent of OIDC token expiry. Only legacy native
    // v2 uses a shorter value for compatibility with already shipped clients.
    const expires = verifiedAt + ttl;
    return { issuer: ISSUER, sub: claims.sub, name: typeof info.name === 'string' ? info.name.slice(0, 120) : 'Tenon', role: info[ROLE], expires };
  }
  refreshCredential(tokens) {
    if (!validRefresh(tokens.refresh_token)) throw failure(401);
    // The registered native client's central refresh lifetime is 30 days;
    // renewing rotates the credential and starts a new bounded lifetime.
    return { refreshToken: tokens.refresh_token, refreshExpires: this.now() + REFRESH_TTL };
  }
  exchange(body) {
    this.sweep();
    if (!/^[A-Za-z0-9_-]{43}$/.test(body.ticket || '') || !/^[A-Za-z0-9_-]{43,128}$/.test(body.verifier || '')) throw failure(400);
    const key = digest(body.ticket), ticket = this.tickets.get(key);
    // An intercepted ticket cannot consume the legitimate flow without PKCE.
    if (!ticket || ticket.expires <= this.now() || !equal(digest(body.verifier), ticket.challenge) || !equal(body.state, ticket.nativeState)) throw failure(401);
    this.tickets.delete(key);
    const sessionToken = token(); this.sessions.set(digest(sessionToken), ticket.session);
    if (ticket.remembered) this.nativeSessions.set(digest(sessionToken), digest(ticket.refreshToken));
    return { token: sessionToken, identity: ticket.session,
      ...(ticket.remembered ? { version: ticket.sessionVersion, refreshToken: ticket.refreshToken, refreshExpires: ticket.refreshExpires } : {}) };
  }
  async refresh(body) {
    const sessionVersion = body.session_version ?? 2;
    if (this.origin !== 'https://tenon.asia' || !validRefresh(body.refreshToken)
      || body.issuer !== ISSUER || typeof body.sub !== 'string' || !body.sub || body.sub.length > 256
      || ![2, 3].includes(sessionVersion)) throw failure(400);
    this.sweep();
    const key = digest(body.refreshToken);
    const limit = this.refreshLimits.get(key) || { expires: this.now() + 60000, count: 0 };
    if (this.refreshLimits.size >= 1000 && !this.refreshLimits.has(key) || ++limit.count > 30 || this.sessions.size >= 5000) throw failure(429);
    this.refreshLimits.set(key, limit);
    // Coalesce concurrent retries; the central provider also has a bounded
    // rotation replay interval for a lost response or a restarted BFF.
    if (!this.refreshing.has(key)) {
      const operation = (async () => {
        const config = await this.config(true);
        let tokens;
        try { tokens = await this.protocol.refreshTokenGrant(config, body.refreshToken); }
        catch (error) {
          if (['invalid_grant', 'invalid_token'].includes(error.error)) throw failure(401);
          throw failure(503);
        }
        const identity = await this.verifiedIdentity(config, tokens);
        if (identity.issuer !== body.issuer || identity.sub !== body.sub) throw failure(401);
        const credential = this.refreshCredential(tokens);
        this.clearNativeAccess(key);
        return { identity, credential };
      })();
      this.refreshing.set(key, { sub: body.sub, operation, results: new Map() });
      operation.finally(() => this.refreshing.delete(key)).catch(() => {});
    }
    const flight = this.refreshing.get(key);
    if (flight.sub !== body.sub) throw failure(401);
    const { identity, credential } = await flight.operation;
    // Coalesce the central rotation across protocol versions, while each
    // caller receives the expiry its client understands.
    if (!flight.results.has(sessionVersion)) {
      const session = sessionVersion === 2 ? { ...identity, expires: identity.expires - TTL + LEGACY_NATIVE_TTL } : identity;
      const sessionToken = token(); this.sessions.set(digest(sessionToken), session);
      this.nativeSessions.set(digest(sessionToken), digest(credential.refreshToken));
      flight.results.set(sessionVersion, { token: sessionToken, identity: session, version: sessionVersion, ...credential });
    }
    return flight.results.get(sessionVersion);
  }
  async revoke(body) {
    if (this.origin !== 'https://tenon.asia' || !validRefresh(body.refreshToken)) throw failure(400);
    await this.protocol.tokenRevocation(await this.config(true), body.refreshToken, { token_type_hint: 'refresh_token' });
    this.clearNativeAccess(digest(body.refreshToken));
  }
  clearNativeAccess(credential) {
    for (const [key, value] of this.nativeSessions) if (value === credential) {
      this.sessions.delete(key); this.nativeSessions.delete(key);
    }
  }
}

export async function readBody(req) {
  let body = '';
  for await (const chunk of req) { body += chunk; if (body.length > 8192) throw failure(413); }
  try { const value = JSON.parse(body); if (!value || typeof value !== 'object' || Array.isArray(value)) throw Error(); return value; } catch { throw failure(400); }
}
