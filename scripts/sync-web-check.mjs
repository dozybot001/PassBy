// Runs the browser's sync code (public/app/sync.js) against docs/sync-vectors.json, and a whole
// session against a host built from the reference implementation.
// node scripts/sync-web-check.mjs
import { readFileSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import * as web from '../public/app/sync.js';
import * as ref from './sync-format.mjs';

const v = JSON.parse(readFileSync(new URL('../docs/sync-vectors.json', import.meta.url), 'utf8'));
let n = 0;
const ok = (cond, what) => { if (!cond) throw new Error('web check failed: ' + what); n += 1; };
const hex = b => Buffer.from(b).toString('hex');
const refused = async promise => { try { await promise; return false; } catch (e) { return e instanceof web.SyncError; } };

for (const c of v.codes) ok(web.canonicalCode(c.typed) === c.code, 'code ' + c.typed);
ok(web.HELLO === ref.HELLO, 'the greeting is the same text');

const hostNonce = Buffer.from(v.crypto.hostNonceHex, 'hex'), guestNonce = Buffer.from(v.crypto.guestNonceHex, 'hex');
const keys = await web.deriveKeys(web.canonicalCode(v.crypto.typed), hostNonce, guestNonce, v.crypto.iterations, true);
const raw = async key => hex(await crypto.subtle.exportKey('raw', key));
ok(await raw(keys.guestToHost) === v.crypto.guestToHostKeyHex && await raw(keys.hostToGuest) === v.crypto.hostToGuestKeyHex, 'keys');
for (const x of v.crypto.exchanges) {
  const req = Buffer.from(x.requestBodyBase64, 'base64'), res = Buffer.from(x.responseBodyBase64, 'base64');
  const sealed = await web.seal(keys.guestToHost, hostNonce, guestNonce, 0, x.counter, Buffer.from(x.requestPlaintext));
  ok(Buffer.from(web.requestBody(hostNonce, guestNonce, x.counter, sealed)).equals(req), 'request reproduced');
  ok(Buffer.from(await web.open(keys.hostToGuest, hostNonce, guestNonce, 1, x.counter, res.subarray(8))).toString() === x.responsePlaintext, 'response opens');
  ok(await refused(web.open(keys.hostToGuest, hostNonce, guestNonce, 0, x.counter, res.subarray(8))), 'other direction refused');
  ok(await refused(web.open(keys.hostToGuest, hostNonce, guestNonce, 1, x.counter + 1, res.subarray(8))), 'other counter refused');
  ok(await refused(web.open(keys.guestToHost, hostNonce, guestNonce, 1, x.counter, res.subarray(8))), 'other key refused');
}

for (const [text, good] of [['10.91.92.79:52814', true], [' 192.168.1.20:65535 ', true], ['172.31.0.1:1', true], ['172.32.0.1:80', false],
  ['8.8.8.8:80', false], ['127.0.0.1:80', false], ['192.168.1.20', false], ['192.168.1.256:80', false], ['192.168.1.20:0', false],
  ['192.168.1.20:65536', false], ['phone.local:80', false], ['http://10.0.0.1:80', false], ['10.0.0.1:80/x', false], ['10.0.0.1:80@evil.example', false]]) {
  ok((web.privateAddress(text) !== null) === good, 'address ' + text);
}

// A host from the reference implementation, in memory: the rules of docs/sync.md 6.2.
function host(code, iterations) {
  let state = { entries: [{ id: 'AAAAAAAA-0000-4000-8000-000000000001', title: 'on the phone', account: '', password: 'p', notes: '', updatedAt: 5, dirty: true }], folders: [], tombstones: [] };
  const pending = new Set();
  let session = null;
  const seen = [];
  return {
    seen,
    get state() { return state; },
    async post(path, body) {
      body = Buffer.from(body);
      seen.push({ path, length: body.length });
      if (path.endsWith('/begin')) {
        if (session) return { status: 403, body: new Uint8Array(0) };
        const nonce = randomBytes(16);
        pending.add(hex(nonce));
        return { status: 200, body: new Uint8Array(nonce) };
      }
      const hn = body.subarray(0, 16), gn = body.subarray(16, 32), counter = Number(body.readBigUInt64BE(32));
      try {
        let reply;
        if (!session) {
          if (!pending.delete(hex(hn))) return { status: 403, body: new Uint8Array(0) };
          const k = ref.deriveKeys(code, hn, gn, iterations);
          const plain = ref.open(k.guestToHost, hn, gn, 0, counter, body.subarray(40)).toString();
          if (counter !== 0 || plain !== ref.HELLO) return { status: 400, body: new Uint8Array(0) };
          session = { keys: k, last: 0 };
          reply = ref.HELLO;
        } else {
          if (counter <= session.last) return { status: 403, body: new Uint8Array(0) };
          const plain = JSON.parse(ref.open(session.keys.guestToHost, hn, gn, 0, counter, body.subarray(40)).toString());
          session.last = counter;
          const guest = { entries: plain.entries, folders: plain.folders, tombstones: plain.tombstones };
          const merged = ref.merge(state, guest, ' (Conflict copy)', () => 'CCCCCCCC-0000-4000-8000-00000000000' + (counter % 10));
          state = merged.state;
          reply = JSON.stringify({ v: 1, state, summary: ref.summary(guest, merged.state, merged.conflicts) });
        }
        return { status: 200, body: new Uint8Array(ref.responseBody(counter, ref.seal(session.keys.hostToGuest, hn, gn, 1, counter, Buffer.from(reply)))) };
      } catch (e) {
        return { status: e.code === 'refused' ? 403 : 400, body: new Uint8Array(0) };
      }
    },
  };
}

const code = 'AB3D9KXMP2QW';
{
  const h = host(code, 1000);
  const s = new web.Session(h.post, 1000);
  await s.start(code);
  const first = await s.exchange({ entries: [], folders: [], tombstones: [] });
  ok(first.state.entries.length === 1 && first.summary.added === 1, 'an empty page receives the notebook');
  const entry = { ...first.state.entries[0], password: 'changed in the browser', updatedAt: 99, dirty: true };
  const second = await s.exchange({ ...first.state, entries: [entry] });
  ok(h.state.entries[0].password === 'changed in the browser' && second.state.entries[0].dirty === false, 'a save reaches the phone');
  ok(h.seen[1].length === 40 + web.HELLO.length + 16, 'the first frame is the greeting only');
}
{
  const h = host(code, 1000);
  const s = new web.Session(h.post, 1000);
  let kind = null;
  try { await s.start('AB3D9KXMP2QX'); } catch (e) { kind = e.kind; }
  ok(kind === 'wrongCode', 'a wrong code is refused');
}
{
  // A host that does not hold the code gets the greeting and nothing else.
  const seen = [];
  const s = new web.Session(async (path, body) => { seen.push(body.length); return { status: 200, body: new Uint8Array(path.endsWith('/begin') ? 16 : 60) }; }, 1000);
  let kind = null;
  try { await s.start(code); } catch (e) { kind = e.kind; }
  ok(kind === 'untrusted' && seen.length === 2 && seen[1] === 40 + web.HELLO.length + 16, 'nothing is sent to a host without the code');
}
{
  const s = new web.Session(async () => { throw new TypeError('network'); }, 1000);
  let kind = null;
  try { await s.start(code); } catch (e) { kind = e.kind; }
  ok(kind === 'unreachable', 'a phone that does not answer');
}
console.log(`${n} web checks passed`);
