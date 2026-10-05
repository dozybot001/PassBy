import { ISSUER } from './auth.mjs';

const unavailable = (status = 503) => Object.assign(new Error('Product deletion unavailable'), { status });
const uuid = /^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i;

// Server-to-server deletion capability. Neither a browser-supplied subject nor
// a product administrator can authorize erasing another person's identity.
export class ProductDeletion {
  constructor({ auth, transport = fetch }) { Object.assign(this, { auth, transport }); }
  async call(operation, body) {
    const response = await this.transport(`${ISSUER}/product-deletion/${operation}`, {
      method: 'POST', redirect: 'error', signal: AbortSignal.timeout(10000),
      headers: { 'Content-Type': 'application/json', Authorization: `Basic ${Buffer.from(`${encodeURIComponent(this.auth.clientId)}:${encodeURIComponent(this.auth.clientSecret)}`).toString('base64')}` },
      body: JSON.stringify(body),
    });
    if (!response.ok) throw unavailable([401, 403].includes(response.status) ? 403 : 503);
    const text = await response.text();
    if (text.length > 32000) throw unavailable();
    try { return JSON.parse(text); } catch { throw unavailable(); }
  }
  async start(req) {
    const { session } = this.auth.identity(req);
    const result = await this.call('start', { sub: session.sub });
    let url; try { url = new URL(result.url); } catch { throw unavailable(); }
    if (url.origin !== 'https://account.tenon.asia' || url.pathname !== '/account/delete/' || url.username || url.password || url.hash ||
      !/^[A-Za-z0-9_-]{43}$/.test(url.searchParams.get('request') || '')) throw unavailable();
    return { url: url.href, expiresAt: result.expiresAt };
  }
  async execute(body) {
    if (Object.keys(body).some(key => !['operationId', 'grant'].includes(key)) || !uuid.test(body.operationId || '') || !/^[A-Za-z0-9_-]{43}$/.test(body.grant || '')) throw unavailable(400);
    const proof = await this.call('claim', body);
    if (proof.operationId !== body.operationId || proof.issuer !== ISSUER || proof.productId !== 'passby' || typeof proof.sub !== 'string' || !proof.sub || proof.sub.length > 256) throw unavailable(403);
    this.auth.sessionStore.deleteProduct(proof.issuer, proof.sub, body.operationId, this.auth.now(), { previouslyCompleted: proof.completed === true });
    // Storage contains product identities and token hashes only. Apple private
    // notebooks, local recovery keys and Keychain vaults are not server-owned.
    try { await this.call('finish', { ...body, status: 'completed' }); } catch { /* Durable receipt remains available for a central retry. */ }
    return { operationId: body.operationId, status: 'completed', deleted: true };
  }
}
