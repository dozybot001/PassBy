// PassBy LAN sync for the browser: the pairing code, the keys and the frames (docs/sync.md 6).
// Only WebCrypto is used. Nothing here touches the page or storage.
// scripts/sync-web-check.mjs runs this file against docs/sync-vectors.json.

export const ITERATIONS = 600000;
const PREFIX = new TextEncoder().encode('PassBy sync v1');
const CODE_ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
export const HELLO = '{"v":1,"hello":true}';

export class SyncError extends Error {
  // kind: unreachable, wrongCode, stopped, untrusted, failed
  constructor(kind) { super(kind); this.kind = kind; }
}

// The 12-character pairing code, or null. Spaces and dashes are ignored; I, L and O read as 1, 1 and 0.
export function canonicalCode(input) {
  let out = '';
  for (const ch of input) {
    if (/[\s\-\u2010-\u2015]/u.test(ch)) continue;
    let c = ch.toUpperCase();
    if (c === 'I' || c === 'L') c = '1'; else if (c === 'O') c = '0';
    if (c.length !== 1 || !CODE_ALPHABET.includes(c)) return null;
    out += c;
  }
  return out.length === 12 ? out : null;
}

// `10.1.2.3:52814` as { host, port }, or null. Names are not accepted, and only 10/8, 172.16/12 and
// 192.168/16 are: the page connects nowhere else.
export function privateAddress(text) {
  const m = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3}):(\d{1,5})$/.exec(text.trim());
  if (!m) return null;
  const [a, b, c, d, port] = m.slice(1).map(Number);
  if ([a, b, c, d].some(n => n > 255) || port < 1 || port > 65535) return null;
  if (!(a === 10 || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168))) return null;
  return { host: `${a}.${b}.${c}.${d}`, port };
}

const concat = (...parts) => {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let at = 0;
  for (const p of parts) { out.set(p, at); at += p.length; }
  return out;
};
const counterBytes = n => { const b = new Uint8Array(8); new DataView(b.buffer).setBigUint64(0, BigInt(n)); return b; };
const ascii = text => new TextEncoder().encode(text);

// The two keys of a session. They cannot be read back out of the browser unless `extractable` is set,
// which only the vector check does.
export async function deriveKeys(code, hostNonce, guestNonce, iterations = ITERATIONS, extractable = false) {
  const subtle = crypto.subtle;
  const password = await subtle.importKey('raw', ascii(code), 'PBKDF2', false, ['deriveBits']);
  const master = new Uint8Array(await subtle.deriveBits(
    { name: 'PBKDF2', hash: 'SHA-256', salt: concat(PREFIX, hostNonce, guestNonce), iterations }, password, 256));
  const base = await subtle.importKey('raw', master, 'HKDF', false, ['deriveKey']);
  master.fill(0);
  const key = info => subtle.deriveKey(
    { name: 'HKDF', hash: 'SHA-256', salt: new Uint8Array(0), info: ascii(info) }, base,
    { name: 'AES-GCM', length: 256 }, extractable, ['encrypt', 'decrypt']);
  return { guestToHost: await key('PassBy sync v1 guest to host'), hostToGuest: await key('PassBy sync v1 host to guest') };
}

const params = (hostNonce, guestNonce, direction, counter) => ({
  name: 'AES-GCM',
  iv: concat(new Uint8Array(4), counterBytes(counter)),
  additionalData: concat(PREFIX, hostNonce, guestNonce, new Uint8Array([direction]), counterBytes(counter)),
  tagLength: 128,
});

// direction: 0 guest to host, 1 host to guest. Returns ciphertext followed by the 16-byte tag.
export async function seal(key, hostNonce, guestNonce, direction, counter, plaintext) {
  return new Uint8Array(await crypto.subtle.encrypt(params(hostNonce, guestNonce, direction, counter), key, plaintext));
}

export async function open(key, hostNonce, guestNonce, direction, counter, sealed) {
  if (sealed.length < 16) throw new SyncError('untrusted');
  try {
    return new Uint8Array(await crypto.subtle.decrypt(params(hostNonce, guestNonce, direction, counter), key, sealed));
  } catch {
    throw new SyncError('untrusted');
  }
}

export const requestBody = (hostNonce, guestNonce, counter, sealed) => concat(hostNonce, guestNonce, counterBytes(counter), sealed);

const isHello = text => {
  try {
    const v = JSON.parse(text);
    return v && typeof v === 'object' && Object.keys(v).length === 2 && v.v === 1 && v.hello === true;
  } catch { return false; }
};

/**
 * One session with a phone that is listening. `post(path, bytes)` sends a request to the phone and
 * resolves to { status, body }; the page supplies it, so this file opens no connection itself.
 */
export class Session {
  constructor(post, iterations = ITERATIONS) {
    this.post = post;
    this.iterations = iterations;
    this.counter = 0;
    this.keys = null;
  }

  // Asks for a host nonce, derives the keys and exchanges greetings. Nothing of the notebook is sent
  // before the phone has shown, by answering the greeting, that it holds the code too.
  async start(code) {
    const begin = await this.request('/passby-sync/v1/begin', new Uint8Array(0));
    if (begin.length !== 16) throw new SyncError('untrusted');
    this.hostNonce = begin;
    this.guestNonce = crypto.getRandomValues(new Uint8Array(16));
    this.keys = await deriveKeys(code, this.hostNonce, this.guestNonce, this.iterations);
    if (!isHello(await this.send(HELLO))) throw new SyncError('untrusted');
  }

  // Sends the page's state and resolves to { state, summary } as merged by the phone.
  async exchange(state) {
    const answer = JSON.parse(await this.send(JSON.stringify({ v: 1, ...state })));
    const s = answer && answer.state;
    if (answer.v !== 1 || !s || !Array.isArray(s.entries) || !Array.isArray(s.folders) || !Array.isArray(s.tombstones)) throw new SyncError('untrusted');
    return { state: s, summary: answer.summary };
  }

  async send(text) {
    const counter = this.counter++;
    const sealed = await seal(this.keys.guestToHost, this.hostNonce, this.guestNonce, 0, counter, new TextEncoder().encode(text));
    const answer = await this.request('/passby-sync/v1/exchange', requestBody(this.hostNonce, this.guestNonce, counter, sealed));
    if (answer.length < 24 || new DataView(answer.buffer, answer.byteOffset, 8).getBigUint64(0) !== BigInt(counter)) throw new SyncError('untrusted');
    return new TextDecoder('utf-8', { fatal: true }).decode(await open(this.keys.hostToGuest, this.hostNonce, this.guestNonce, 1, counter, answer.subarray(8)));
  }

  async request(path, body) {
    let response;
    try {
      response = await this.post(path, body);
    } catch {
      throw new SyncError('unreachable');
    }
    if (response.status === 200) return response.body;
    throw new SyncError(response.status === 403 ? 'wrongCode' : response.status === 410 ? 'stopped' : 'failed');
  }

  close() {
    this.keys = null;
  }
}
