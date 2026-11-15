// A sync guest on this Mac built from the reference implementation (docs/sync.md 6.2).
// usage: node scripts/sync-dev-guest.mjs <repo> <connect host:port> <Host header> <code> <stateJson>
import { randomBytes } from 'node:crypto';
import { request } from 'node:http';
const [repo, target, hostHeader, code, stateJson] = process.argv.slice(2);
const S = await import(`${repo}/scripts/sync-format.mjs`);
const [h, p] = target.split(':');
const post = (path, body) => new Promise((resolve, reject) => {
  const req = request({ host: h, port: Number(p), path, method: 'POST', headers: { Host: hostHeader, 'Content-Length': body.length, 'Content-Type': 'application/octet-stream' } }, res => {
    const chunks = []; res.on('data', c => chunks.push(c)); res.on('end', () => resolve({ status: res.statusCode, body: Buffer.concat(chunks) }));
  });
  req.on('error', reject); req.end(body);
});
const begin = await post('/passby-sync/v1/begin', Buffer.alloc(0));
console.log('begin', begin.status, begin.body.length);
if (begin.status !== 200) process.exit(0);
const hn = begin.body, gn = randomBytes(16);
const keys = S.deriveKeys(S.canonicalCode(code), hn, gn);
const send = async (counter, text) => {
  const r = await post('/passby-sync/v1/exchange', S.requestBody(hn, gn, counter, S.seal(keys.guestToHost, hn, gn, 0, counter, Buffer.from(text))));
  return { status: r.status, text: r.status === 200 ? S.open(keys.hostToGuest, hn, gn, 1, counter, r.body.subarray(8)).toString('utf8') : null };
};
const hello = await send(0, S.HELLO);
console.log('hello', hello.status, hello.text === S.HELLO);
if (hello.status !== 200) process.exit(0);
let state = JSON.parse(stateJson);
for (let counter = 1; counter <= 2; counter++) {
  const r = await send(counter, JSON.stringify({ v: 1, ...state }));
  console.log('exchange', counter, r.status);
  if (r.status !== 200) break;
  const answer = JSON.parse(r.text);
  console.log('summary', JSON.stringify(answer.summary), 'titles:', answer.state.entries.map(e => e.title).join(' | '));
  state = answer.state;
  const e = state.entries.find(x => x.title === 'q'); if (e) { e.notes = 'edited on the Mac ' + counter; e.updatedAt = Date.now(); e.dirty = true; }
}
const again = await post('/passby-sync/v1/begin', Buffer.alloc(0));
console.log('begin after pairing', again.status);
