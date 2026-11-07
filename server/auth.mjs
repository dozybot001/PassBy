import * as oidc from 'openid-client';
import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';

// PassBy records identities under the original issuer. Tenon's move to
// tenonai.cn renames the issuer once without changing `sub`, so tokens from
// either issuer name the same account. The first issuer whose discovery
// answers with its own address is current.
export const ISSUER = 'https://account.tenon.asia/api/auth';
export const ISSUERS = Object.freeze((process.env.TENON_ISSUERS || 'https://account.tenonai.cn/api/auth https://account.tenon.asia/api/auth').split(/\s+/).filter(Boolean));
export const ACCOUNT_ORIGINS = Object.freeze(ISSUERS.map(issuer => new URL(issuer).origin));
const DISCOVERY_TTL = 10 * 60 * 1000;
export const ROLE = 'https://tenon.asia/claims/platform_role';
export const TTL = 30 * 24 * 60 * 60 * 1000;
export const NATIVE_TTL = TTL;
export const REFRESH_TTL = 30 * 24 * 60 * 60 * 1000;
export const SESSION_VERSION = 3;
const token = () => randomBytes(32).toString('base64url');
export const digest = value => createHash('sha256').update(value).digest('base64url');
const equal = (a, b) => typeof a === 'string' && typeof b === 'string' && a.length === b.length && timingSafeEqual(Buffer.from(a), Buffer.from(b));
const failure = status => Object.assign(new Error('Authentication unavailable'), { status });
const validRefresh = value => typeof value === 'string' && /^[A-Za-z0-9._~-]{32,4096}$/.test(value);

// Identity-only BFF: no notebook, recovery key, Apple token or password storage.
// Web tokens are discarded after the callback. Native refresh credentials
// pass through a one-use ticket to the device Keychain, never to cookies, logs
// or disk. Tickets are discarded within 60 seconds.
const LOGIN_METHODS = new Set(['apple', 'github', 'email']);
export class TenonAuth {
  // `origin` names the session slot; `hosts` are the public origins that serve it.
  // `webSignIn: false` keeps a slot to iPhone sign-in, so an old domain issues no browser sessions.
  constructor({ origin = 'https://tenon.asia', hosts = [origin], webSignIn = true, clientId, clientSecret, iosClientId, iosClientSecret, sessionStore, protocol = oidc, now = Date.now }) {
    if (!['https://tenon.asia', 'https://passby.tenon.asia'].includes(origin) || !hosts.includes(origin) || hosts.some(host => new URL(host).origin !== host || !host.startsWith('https://'))
      || !clientId || !clientSecret || !sessionStore) throw Error('Incomplete authentication configuration');
    Object.assign(this, { origin, hosts, webSignIn, clientId, clientSecret, iosClientId, iosClientSecret, sessionStore, protocol, now });
    this.basePath = origin === 'https://tenon.asia' ? '/passby/' : '/';
    this.apiPath = this.basePath + 'api';
    this.callback = origin + this.apiPath + '/auth/callback';
    this.iosCallback = origin + this.apiPath + '/auth/ios/callback';
    this.attempts = new Map(); this.tickets = new Map();
    this.refreshing = new Map(); this.refreshLimits = new Map();
  }
  // Caddy forwards only its configured sites; anything else keeps the slot's own origin.
  publicOrigin(req) { return this.hosts.find(host => host === 'https://' + req.headers.host) || this.origin; }
  get sessionCount() { return this.sessionStore.count(this.origin, this.now()); }
  sweep() {
    for (const map of [this.attempts, this.tickets]) for (const [key, value] of map) if (value.expires <= this.now()) map.delete(key);
    for (const [key, value] of this.refreshLimits) if (value.expires <= this.now()) this.refreshLimits.delete(key);
    this.sessionStore.prune(this.origin, this.now());
  }
  async config(native = false) {
    if (native && (!this.iosClientId || !this.iosClientSecret)) throw failure(503);
    const slot = native ? 'iosConfiguration' : 'configuration', cached = this[slot];
    if (cached && cached.checked + DISCOVERY_TTL > this.now()) return cached.config;
    for (const issuer of ISSUERS) {
      try {
        const config = await this.protocol.discovery(new URL(issuer), native ? this.iosClientId : this.clientId, undefined,
          this.protocol.ClientSecretBasic(native ? this.iosClientSecret : this.clientSecret), { timeout: 10, execute: [this.protocol.enableNonRepudiationChecks] });
        if (config.serverMetadata().issuer !== issuer) continue;
        this[slot] = { config, checked: this.now() };
        return config;
      } catch { /* Not answering yet, or no longer this issuer. */ }
    }
    if (cached) { cached.checked = this.now(); return cached.config; }
    throw failure(503);
  }
  // A failed exchange may mean Tenon just switched issuer; look again next time.
  recheck(native) { const cached = this[native ? 'iosConfiguration' : 'configuration']; if (cached) cached.checked = -Infinity; }
  async currentIssuer() { return (await this.config()).serverMetadata().issuer; }
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
    const session = this.sessionStore.get(this.origin, key, this.now());
    if (!session || session.expires <= this.now()) throw failure(401);
    return { key, session };
  }
  async start(req, res, url) {
    if (req.headers['sec-fetch-site'] === 'cross-site' || !this.hosts.includes(url.origin)) throw failure(403);
    this.sweep();
    if (this.attempts.size >= 1000 || this.sessionCount >= 5000) throw failure(429);
    const native = url.searchParams.get('platform') === 'ios';
    if (!native && !this.webSignIn) throw failure(404);
    const challenge = url.searchParams.get('challenge'), nativeState = url.searchParams.get('state');
    if (native && (url.searchParams.get('session_version') !== String(SESSION_VERSION)
      || !/^[A-Za-z0-9_-]{43}$/.test(challenge || '') || !/^[A-Za-z0-9_-]{43}$/.test(nativeState || ''))) throw failure(400);
    const authorizationGeneration = this.sessionStore.generation();
    const config = await this.config(native), browser = token(), verifier = this.protocol.randomPKCECodeVerifier();
    const state = this.protocol.randomState(), nonce = this.protocol.randomNonce();
    // The chosen method only selects the central page; identity checks are unchanged.
    const method = url.searchParams.get('method');
    const location = this.protocol.buildAuthorizationUrl(config, { redirect_uri: url.origin + this.apiPath + (native ? '/auth/ios/callback' : '/auth/callback'),
      scope: native ? 'openid profile email offline_access' : 'openid profile email', ...(native ? { prompt: 'consent' } : {}), state, nonce,
      code_challenge: await this.protocol.calculatePKCECodeChallenge(verifier), code_challenge_method: 'S256',
      ...(LOGIN_METHODS.has(method) ? { tenon_method: method } : {}) });
    this.attempts.set(digest(browser), { verifier, state, nonce, expires: this.now() + 600000, native, challenge, nativeState, authorizationGeneration, host: url.origin });
    res.setHeader('Set-Cookie', this.cookie('attempt', browser, 600, 'Lax'));
    if (url.searchParams.get('format') === 'json') {
      res.writeHead(200, { 'Content-Type': 'application/json' }).end(JSON.stringify({ url: location.href }));
    } else res.writeHead(303, { Location: location.href }).end();
  }
  async complete(req, res, url) {
    const key = digest(this.cookieValue(req, 'attempt') || ''), attempt = this.attempts.get(key);
    this.attempts.delete(key);
    res.setHeader('Set-Cookie', this.cookie('attempt', '', 0, 'Lax'));
    if (!attempt || attempt.expires <= this.now() || url.origin !== attempt.host || url.pathname !== (attempt.native ? new URL(this.iosCallback).pathname : new URL(this.callback).pathname)) throw failure(401);
    const config = await this.config(attempt.native);
    const tokens = await this.protocol.authorizationCodeGrant(config, url, { pkceCodeVerifier: attempt.verifier,
      expectedState: attempt.state, expectedNonce: attempt.nonce, idTokenExpected: true }).catch(error => { this.recheck(attempt.native); throw error; });
    const session = await this.verifiedIdentity(config, tokens);
    this.sessionStore.assertGeneration(session.issuer, session.sub, attempt.authorizationGeneration);
    const refresh = attempt.native ? this.refreshCredential(tokens) : {};
    const expires = session.expires;
    if (attempt.native) {
      const ticket = token();
      this.tickets.set(digest(ticket), { ...attempt, session, ...refresh, expires: Math.min(expires, this.now() + 60000) });
      // A fixed product callback, never a caller-provided redirect. The ticket
      // is useless without the verifier held by the initiating iPhone.
      res.writeHead(303, { Location: `passby://auth?ticket=${ticket}&state=${attempt.nativeState}` }).end();
    } else {
      const sessionToken = token(); this.sessionStore.create(this.origin, digest(sessionToken), session, this.now(), { authorizationGeneration: attempt.authorizationGeneration });
      res.setHeader('Set-Cookie', [this.cookie('attempt', '', 0, 'Lax'), this.cookie('session', sessionToken, Math.floor((expires - this.now()) / 1000))]);
      res.writeHead(303, { Location: this.basePath }).end();
    }
  }
  async verifiedIdentity(config, tokens) {
    const claims = tokens.claims();
    if (!claims || claims.iss !== config.serverMetadata().issuer || typeof claims.sub !== 'string' || !claims.sub
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
    // its own lifetime, independent of OIDC token expiry.
    const expires = verifiedAt + TTL;
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
    const sessionToken = token();
    this.sessionStore.create(this.origin, digest(sessionToken), ticket.session, this.now(), { nativeRefreshHash: digest(ticket.refreshToken), authorizationGeneration: ticket.authorizationGeneration });
    this.tickets.delete(key);
    return { token: sessionToken, identity: ticket.session, version: SESSION_VERSION,
      refreshToken: ticket.refreshToken, refreshExpires: ticket.refreshExpires };
  }
  async refresh(body) {
    if (this.origin !== 'https://tenon.asia' || !validRefresh(body.refreshToken)
      || body.issuer !== ISSUER || typeof body.sub !== 'string' || !body.sub || body.sub.length > 256
      || body.session_version !== SESSION_VERSION) throw failure(400);
    this.sweep();
    const key = digest(body.refreshToken);
    this.sessionStore.assertRefresh(this.origin, body.issuer, body.sub, key, this.now());
    const authorizationGeneration = this.sessionStore.generation();
    const limit = this.refreshLimits.get(key) || { expires: this.now() + 60000, count: 0 };
    if (this.refreshLimits.size >= 1000 && !this.refreshLimits.has(key) || ++limit.count > 30) throw failure(429);
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
          this.recheck(true); throw failure(503);
        }
        const identity = await this.verifiedIdentity(config, tokens);
        if (identity.issuer !== body.issuer || identity.sub !== body.sub) throw failure(401);
        const credential = this.refreshCredential(tokens);
        if (credential.refreshToken === body.refreshToken) throw failure(401);
        const sessionToken = token();
        // Retiring the old credential's sessions and persisting the response
        // is one transaction. No token is returned before it commits.
        this.sessionStore.create(this.origin, digest(sessionToken), identity, this.now(), {
          nativeRefreshHash: digest(credential.refreshToken), retireRefreshHash: key, authorizationGeneration });
        return { token: sessionToken, identity, version: SESSION_VERSION, ...credential };
      })();
      this.refreshing.set(key, { sub: body.sub, operation });
      operation.finally(() => this.refreshing.delete(key)).catch(() => {});
    }
    const flight = this.refreshing.get(key);
    if (flight.sub !== body.sub) throw failure(401);
    return flight.operation;
  }
  async revoke(body) {
    if (this.origin !== 'https://tenon.asia' || !validRefresh(body.refreshToken)) throw failure(400);
    this.sessionStore.revoke(this.origin, digest(body.refreshToken), this.now());
    await this.protocol.tokenRevocation(await this.config(true), body.refreshToken, { token_type_hint: 'refresh_token' });
  }
  logout(req) {
    const bearer = req.headers.authorization?.match(/^Bearer ([A-Za-z0-9_-]{43})$/)?.[1];
    this.sessionStore.delete(this.origin, digest(bearer || this.cookieValue(req, 'session') || ''));
  }
}

export async function readBody(req) {
  let body = '';
  for await (const chunk of req) { body += chunk; if (body.length > 8192) throw failure(413); }
  try { const value = JSON.parse(body); if (!value || typeof value !== 'object' || Array.isArray(value)) throw Error(); return value; } catch { throw failure(400); }
}
