import { ACCOUNT_ORIGINS, ISSUER, ISSUERS } from './auth.mjs';

const unavailable = (status = 503) => Object.assign(new Error('Product deletion unavailable'), { status });
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i;
const deadlines = Object.freeze({ start: 5000, claim: 5000, finish: 2000 });

// Server-to-server deletion capability. Neither a browser-supplied subject nor
// a product administrator can authorize erasing another person's identity.
export class ProductDeletion {
  constructor({ auth, transport = fetch, timeoutSignal = milliseconds => AbortSignal.timeout(milliseconds) }) {
    Object.assign(this, { auth, transport, timeoutSignal });
  }
  async call(operation, body) {
    const response = await this.transport(`${await this.auth.currentIssuer()}/product-deletion/${operation}`, {
      method: 'POST', redirect: 'error', signal: this.timeoutSignal(deadlines[operation]),
      headers: { 'Content-Type': 'application/json', Authorization: `Basic ${Buffer.from(`${encodeURIComponent(this.auth.clientId)}:${encodeURIComponent(this.auth.clientSecret)}`).toString('base64')}` },
      body: JSON.stringify(body),
    });
    if (!response.ok) throw unavailable([401, 403].includes(response.status) ? 403 : 503);
    const text = await response.text();
    if (text.length > 32000) throw unavailable();
    try {
      const result = JSON.parse(text);
      if (!result || typeof result !== 'object' || Array.isArray(result)) throw unavailable();
      return result;
    } catch { throw unavailable(); }
  }
  async start(req) {
    const { session } = this.auth.identity(req);
    const result = await this.call('start', { sub: session.sub });
    if (typeof result.url !== 'string') throw unavailable();
    let url; try { url = new URL(result.url); } catch { throw unavailable(); }
    if (!ACCOUNT_ORIGINS.includes(url.origin) || url.pathname !== '/account/delete/' || url.username || url.password || url.hash ||
      [...url.searchParams.keys()].length !== 1 || !/^[A-Za-z0-9_-]{43}$/.test(url.searchParams.get('request') || '') ||
      !Number.isSafeInteger(result.expiresAt) || result.expiresAt <= this.auth.now()) throw unavailable();
    // iPhone builds up to 1.2 accept only the old account host, which keeps redirecting with the query.
    if (this.auth.origin === 'https://tenon.asia') url.host = 'account.tenon.asia';
    return { url: url.href, expiresAt: result.expiresAt };
  }
  async execute(body) {
    if (!body || typeof body !== 'object' || Array.isArray(body) ||
      Object.keys(body).some(key => !['operationId', 'grant'].includes(key)) ||
      typeof body.operationId !== 'string' || !uuid.test(body.operationId) ||
      typeof body.grant !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(body.grant)) throw unavailable(400);
    const proof = await this.call('claim', body);
    if (proof.operationId !== body.operationId || !ISSUERS.includes(proof.issuer) || proof.productId !== 'passby' || typeof proof.sub !== 'string' || !proof.sub || proof.sub.length > 256) throw unavailable(403);
    this.auth.sessionStore.deleteProduct(ISSUER, proof.sub, body.operationId, this.auth.now(), { previouslyCompleted: proof.completed === true });
    // Storage contains product identities and token hashes only. Apple private
    // notebooks, local recovery keys and Keychain vaults are not server-owned.
    try { await this.call('finish', { ...body, status: 'completed' }); } catch { /* Durable receipt remains available for a central retry. */ }
    return { operationId: body.operationId, status: 'completed', deleted: true };
  }
}
