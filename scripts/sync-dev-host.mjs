// A sync host on this Mac built from the reference implementation (docs/sync.md 6.2), for trying a guest.
// usage: node scripts/sync-dev-host.mjs <repo> <ip> <port> <code> <allowed origin> [stateFile]
import { createServer } from 'node:http';
import { randomBytes, randomUUID } from 'node:crypto';
import { readFileSync, existsSync } from 'node:fs';
const [repo, ip, port, code, origin, stateFile] = process.argv.slice(2);
const S = await import(`${repo}/scripts/sync-format.mjs`);
let state = stateFile && existsSync(stateFile) ? JSON.parse(readFileSync(stateFile, 'utf8')) : { entries: [], folders: [], tombstones: [] };
const pending = new Set(); let session = null;
const cors = { 'Access-Control-Allow-Origin': origin, 'Access-Control-Allow-Methods': 'POST', 'Access-Control-Allow-Headers': 'content-type', 'Cache-Control': 'no-store' };
createServer((req, res) => {
  const chunks = [];
  req.on('data', c => chunks.push(c));
  req.on('end', () => {
    const body = Buffer.concat(chunks);
    const send = (status, out = Buffer.alloc(0)) => { console.log(req.method, req.url, body.length, 'origin', req.headers.origin, '->', status, out.length); res.writeHead(status, { ...cors, 'Content-Length': out.length, Connection: 'close' }); res.end(out); };
    if (req.headers.host !== `${ip}:${port}`) return req.socket.destroy();
    if (req.headers.origin && req.headers.origin !== origin) return send(403);
    if (req.method === 'OPTIONS') return send(204);
    if (req.method === 'POST' && req.url === '/passby-sync/v1/begin') { if (session || pending.size >= 4) return send(403); const n = randomBytes(16); pending.add(n.toString('hex')); return send(200, n); }
    if (req.method === 'POST' && req.url === '/passby-sync/v1/exchange') {
      try {
        const hn = body.subarray(0, 16), gn = body.subarray(16, 32), counter = Number(body.readBigUInt64BE(32));
        let reply;
        if (!session) {
          if (!pending.delete(hn.toString('hex'))) return send(403);
          const keys = S.deriveKeys(code, hn, gn);
          const plain = S.open(keys.guestToHost, hn, gn, 0, counter, body.subarray(40)).toString('utf8');
          if (counter !== 0 || plain !== S.HELLO) return send(400);
          session = { keys, last: 0, hn: hn.toString('hex'), gn: gn.toString('hex') }; pending.clear();
          reply = S.HELLO;
        } else {
          if (session.hn !== hn.toString('hex') || session.gn !== gn.toString('hex') || counter <= session.last) return send(403);
          const plain = JSON.parse(S.open(session.keys.guestToHost, hn, gn, 0, counter, body.subarray(40)).toString('utf8'));
          session.last = counter;
          const guest = { entries: plain.entries, folders: plain.folders, tombstones: plain.tombstones };
          const merged = S.merge(state, guest, ' (Conflict copy)', () => randomUUID());
          const summary = S.summary(guest, merged.state, merged.conflicts);
          state = merged.state;
          console.log('host now:', state.entries.map(e => e.title + '=' + e.password).join(' | '), 'tombstones', state.tombstones.length, 'guest summary', JSON.stringify(summary));
          reply = JSON.stringify({ v: 1, state, summary });
        }
        return send(200, S.responseBody(counter, S.seal(session.keys.hostToGuest, hn, gn, 1, counter, Buffer.from(reply, 'utf8'))));
      } catch (e) { return send(e.code === 'refused' ? 403 : 400); }
    }
    send(400);
  });
}).listen(Number(port), process.env.BIND || ip, () => console.log('listening', ip, port));
