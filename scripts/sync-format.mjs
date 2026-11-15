// Reference implementation of PassBy LAN sync (docs/sync.md): keys, frames and the merge.
// `node scripts/sync-format.mjs` regenerates docs/sync-vectors.json and checks every vector.
// `node scripts/sync-format.mjs --check` only checks the committed vectors.
import { createCipheriv, createDecipheriv, createHash, hkdfSync, pbkdf2Sync } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';

export const ITERATIONS = 600_000;
const PREFIX = Buffer.from('PassBy sync v1', 'ascii');
const CODE_ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const UUID = /^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$/;

export class SyncError extends Error {
  constructor(code) { super(code); this.code = code; }
}

// ---- Pairing code and keys (docs/sync.md 6.3) ----

// The 12-character pairing code, or null. Spaces and dashes are ignored; I, L and O read as 1, 1 and 0.
export function canonicalCode(input) {
  let out = '';
  for (const ch of input) {
    if (/[\s\-‐-―]/u.test(ch)) continue;
    let c = ch.toUpperCase();
    if (c === 'I' || c === 'L') c = '1'; else if (c === 'O') c = '0';
    if (c.length !== 1 || !CODE_ALPHABET.includes(c)) return null;
    out += c;
  }
  return out.length === 12 ? out : null;
}

export function deriveKeys(code, hostNonce, guestNonce, iterations = ITERATIONS) {
  const salt = Buffer.concat([PREFIX, hostNonce, guestNonce]);
  const master = pbkdf2Sync(Buffer.from(code, 'ascii'), salt, iterations, 32, 'sha256');
  const key = info => Buffer.from(hkdfSync('sha256', master, Buffer.alloc(0), info, 32));
  return { guestToHost: key('PassBy sync v1 guest to host'), hostToGuest: key('PassBy sync v1 host to guest') };
}

const counterBytes = n => { const b = Buffer.alloc(8); b.writeBigUInt64BE(BigInt(n)); return b; };
const nonceFor = counter => Buffer.concat([Buffer.alloc(4), counterBytes(counter)]);
const aadFor = (hostNonce, guestNonce, direction, counter) =>
  Buffer.concat([PREFIX, hostNonce, guestNonce, Buffer.from([direction]), counterBytes(counter)]);

// direction: 0 guest to host, 1 host to guest. Returns ciphertext followed by the 16-byte tag.
export function seal(key, hostNonce, guestNonce, direction, counter, plaintext) {
  const cipher = createCipheriv('aes-256-gcm', key, nonceFor(counter));
  cipher.setAAD(aadFor(hostNonce, guestNonce, direction, counter));
  return Buffer.concat([cipher.update(plaintext), cipher.final(), cipher.getAuthTag()]);
}

export function open(key, hostNonce, guestNonce, direction, counter, sealed) {
  if (sealed.length < 16) throw new SyncError('refused');
  const decipher = createDecipheriv('aes-256-gcm', key, nonceFor(counter));
  decipher.setAAD(aadFor(hostNonce, guestNonce, direction, counter));
  decipher.setAuthTag(sealed.subarray(sealed.length - 16));
  try { return Buffer.concat([decipher.update(sealed.subarray(0, sealed.length - 16)), decipher.final()]); }
  catch { throw new SyncError('refused'); }
}

// What both sides send at counter 0, before any notebook content: the guest shows it holds the code,
// and the host's sealed answer shows the same. The state follows from counter 1 (docs/sync.md 6.2).
export const HELLO = '{"v":1,"hello":true}';

// The body of an exchange request and of its response.
export const requestBody = (hostNonce, guestNonce, counter, sealed) =>
  Buffer.concat([hostNonce, guestNonce, counterBytes(counter), sealed]);
export const responseBody = (counter, sealed) => Buffer.concat([counterBytes(counter), sealed]);

// ---- State (docs/sync.md 6.4) ----

const text = v => typeof v === 'string';
const time = v => Number.isSafeInteger(v) && v >= 0;
const up = id => id.toUpperCase();

// Checks a state and returns it with identifiers in upper case. Throws SyncError('invalid').
export function validate(state) {
  const bad = () => { throw new SyncError('invalid'); };
  if (!state || !Array.isArray(state.entries) || !Array.isArray(state.folders) || !Array.isArray(state.tombstones)) bad();
  const folders = state.folders.map(f => {
    if (!f || !text(f.id) || !UUID.test(f.id) || !text(f.name) || !time(f.updatedAt) || typeof f.dirty !== 'boolean') bad();
    return { id: up(f.id), name: f.name, updatedAt: f.updatedAt, dirty: f.dirty };
  });
  const folderIDs = new Set(folders.map(f => f.id));
  const entries = state.entries.map(e => {
    if (!e || !text(e.id) || !UUID.test(e.id) || !['title', 'account', 'password', 'notes'].every(k => text(e[k]))
      || !time(e.updatedAt) || typeof e.dirty !== 'boolean') bad();
    if (e.folderID !== undefined && (!text(e.folderID) || !UUID.test(e.folderID) || !folderIDs.has(up(e.folderID)))) bad();
    const out = { id: up(e.id), title: e.title, account: e.account, password: e.password, notes: e.notes, updatedAt: e.updatedAt, dirty: e.dirty };
    if (e.folderID !== undefined) out.folderID = up(e.folderID);
    return out;
  });
  const tombstones = state.tombstones.map(t => {
    if (!t || !text(t.id) || !UUID.test(t.id) || !['entry', 'folder'].includes(t.kind) || !time(t.deletedAt) || typeof t.dirty !== 'boolean') bad();
    return { id: up(t.id), kind: t.kind, deletedAt: t.deletedAt, dirty: t.dirty };
  });
  const unique = (list, kind) => new Set(list.map(x => x.id)).size === list.length
    && !list.some(x => tombstones.some(t => t.kind === kind && t.id === x.id));
  if (!unique(entries, 'entry') || !unique(folders, 'folder')) bad();
  for (const kind of ['entry', 'folder']) {
    const ids = tombstones.filter(t => t.kind === kind).map(t => t.id);
    if (new Set(ids).size !== ids.length) bad();
  }
  return { entries, folders, tombstones };
}

// ---- Merge (docs/sync.md 5) ----

const sameEntry = (a, b) => a.title === b.title && a.account === b.account && a.password === b.password
  && a.notes === b.notes && (a.folderID ?? null) === (b.folderID ?? null);
const stamp = x => x.live ? x.live.updatedAt : x.dead.deletedAt;

// One side's view of an identifier: a live item, a tombstone, or nothing.
function sides(state, kind) {
  const map = new Map();
  for (const item of kind === 'entry' ? state.entries : state.folders) map.set(item.id, { live: item, dirty: item.dirty });
  for (const t of state.tombstones) if (t.kind === kind) map.set(t.id, { dead: t, dirty: t.dirty });
  return map;
}

/**
 * Merges the host's and the guest's states. `marker` is appended to the title of a conflict copy;
 * `freshId` supplies the identifier of each copy, in ascending order of the entry's identifier.
 * Returns the merged state, with nothing dirty and everything sorted by identifier.
 */
export function merge(hostState, guestState, marker, freshId) {
  const host = validate(hostState), guest = validate(guestState);
  const out = { entries: [], folders: [], tombstones: [] };
  let conflicts = 0;
  for (const kind of ['folder', 'entry']) {
    const h = sides(host, kind), g = sides(guest, kind);
    const keep = x => {
      if (x.live) out[kind === 'entry' ? 'entries' : 'folders'].push({ ...x.live, dirty: false });
      else out.tombstones.push({ ...x.dead, dirty: false });
    };
    for (const id of [...new Set([...h.keys(), ...g.keys()])].sort()) {
      const a = h.get(id), b = g.get(id);
      if (!a || !b) { keep(a ?? b); continue; }
      const same = a.live && b.live ? (kind === 'entry' ? sameEntry(a.live, b.live) : a.live.name === b.live.name) : !a.live && !b.live;
      // The later one; the host's when they are equally late.
      const later = stamp(b) > stamp(a) ? b : a;
      if (same) { keep(a.live ? { live: { ...a.live, updatedAt: Math.max(a.live.updatedAt, b.live.updatedAt) } } : later); continue; }
      if (a.dirty !== b.dirty) { keep(a.dirty ? a : b); continue; }
      if (!a.dirty) { keep(later); continue; }
      // Both changed since they last agreed.
      if (a.live && b.live) {
        keep(later);
        if (kind === 'entry') {
          const loser = later === a ? b.live : a.live;
          out.entries.push({ ...loser, id: up(freshId()), title: loser.title + marker, dirty: false });
          conflicts += 1;
        }
      } else if (a.live || b.live) keep(a.live ? a : b); // an edit outlives a deletion
      else keep(later);
    }
  }
  const folderIDs = new Set(out.folders.map(f => f.id));
  for (const entry of out.entries) if (entry.folderID !== undefined && !folderIDs.has(entry.folderID)) delete entry.folderID;
  for (const list of [out.entries, out.folders]) list.sort((x, y) => (x.id < y.id ? -1 : x.id > y.id ? 1 : 0));
  out.tombstones.sort((x, y) => (x.kind + x.id < y.kind + y.id ? -1 : 1));
  return { state: out, conflicts };
}

// What changed for one side: entries it gained, entries whose content changed, entries it lost.
export function summary(before, after, conflicts) {
  const old = new Map(validate(before).entries.map(e => [e.id, e]));
  const now = new Map(after.entries.map(e => [e.id, e]));
  let added = 0, updated = 0, removed = 0;
  for (const [id, e] of now) { if (!old.has(id)) added += 1; else if (!sameEntry(old.get(id), e)) updated += 1; }
  for (const id of old.keys()) if (!now.has(id)) removed += 1;
  return { added: added - conflicts, updated, removed, conflicts };
}

// ---- Test vectors ----

const fixed = (label, length) => createHash('sha256').update(label).digest().subarray(0, length);
const hex = b => Buffer.from(b).toString('hex');
const E = (n, fields = {}) => ({ id: `00000000-0000-4000-8000-0000000000${n}`, title: 't' + n, account: '', password: 'p' + n, notes: '', updatedAt: 1000, dirty: false, ...fields });
const F = (n, fields = {}) => ({ id: `F0000000-0000-4000-8000-0000000000${n}`, name: 'f' + n, updatedAt: 1000, dirty: false, ...fields });
const T = (n, kind, fields = {}) => ({ id: `${kind === 'folder' ? 'F' : '0'}0000000-0000-4000-8000-0000000000${n}`, kind, deletedAt: 2000, dirty: true, ...fields });
const state = (entries = [], folders = [], tombstones = []) => ({ entries, folders, tombstones });
const COPY = n => `C0000000-0000-4000-8000-0000000000${n}`;

const MERGES = [
  { name: 'an empty guest receives everything and nothing is deleted', host: state([E('01'), E('02', { folderID: F('01').id })], [F('01')]), guest: state() },
  { name: 'only one side has an entry, a folder or a tombstone', host: state([E('01', { dirty: true })], [], [T('09', 'entry')]), guest: state([E('02', { dirty: true })], [F('02', { dirty: true })]) },
  { name: 'one side edited: the edit is taken, whatever the clocks say', host: state([E('01', { password: 'new', updatedAt: 500, dirty: true })]), guest: state([E('01', { updatedAt: 9000 })]) },
  { name: 'one side deleted: the deletion is taken', host: state([E('01')]), guest: state([], [], [T('01', 'entry')]) },
  { name: 'both edited differently: the later stays and the other becomes a conflict copy', host: state([E('01', { password: 'host', updatedAt: 3000, dirty: true })]), guest: state([E('01', { password: 'guest', updatedAt: 4000, dirty: true })]) },
  { name: 'both edited at the same time: the host stays', host: state([E('01', { notes: 'host', updatedAt: 3000, dirty: true })]), guest: state([E('01', { notes: 'guest', updatedAt: 3000, dirty: true })]) },
  { name: 'both made the same edit: one entry, no copy', host: state([E('01', { password: 'same', updatedAt: 3000, dirty: true })]), guest: state([E('01', { password: 'same', updatedAt: 4000, dirty: true })]) },
  { name: 'an edit outlives a deletion made on the other side', host: state([], [], [T('01', 'entry', { deletedAt: 9000 })]), guest: state([E('01', { password: 'kept', updatedAt: 3000, dirty: true })]) },
  { name: 'neither is marked but they differ: the later wins', host: state([E('01', { password: 'old', updatedAt: 1000 })], [], [T('02', 'entry', { deletedAt: 5000, dirty: false })]), guest: state([E('01', { password: 'newer', updatedAt: 2000 }), E('02', { updatedAt: 4000 })]) },
  { name: 'folders: the later name wins without a copy, and a deleted folder leaves its entries unfiled', host: state([E('01', { folderID: F('01').id }), E('02', { folderID: F('02').id })], [F('01', { name: 'host', updatedAt: 3000, dirty: true }), F('02')]), guest: state([E('01', { folderID: F('01').id }), E('02')], [F('01', { name: 'guest', updatedAt: 4000, dirty: true })], [T('02', 'folder')]) },
  { name: 'identifiers are compared without regard to case', host: state([E('0a', { password: 'x', dirty: true })]), guest: state([{ ...E('0A'), id: E('0a').id.toLowerCase() }]) },
];

const INVALID = [
  { name: 'duplicate entry identifiers', state: state([E('01'), E('01')]) },
  { name: 'an entry points to a folder that is not there', state: state([E('01', { folderID: F('01').id })]) },
  { name: 'an identifier that is both an entry and its tombstone', state: state([E('01')], [], [T('01', 'entry')]) },
  { name: 'a missing field', state: state([{ id: E('01').id, title: 't', updatedAt: 1, dirty: false }]) },
  { name: 'a time that is not a whole number', state: state([E('01', { updatedAt: 1.5 })]) },
  { name: 'an unknown tombstone kind', state: state([], [], [{ ...T('01', 'entry'), kind: 'note' }]) },
];

function build() {
  const hostNonce = fixed('host nonce', 16), guestNonce = fixed('guest nonce', 16);
  const typed = 'ab3d-9kxm p2qw';
  const code = canonicalCode(typed);
  const iterations = 100_000;
  const keys = deriveKeys(code, hostNonce, guestNonce, iterations);
  const request = Buffer.from(JSON.stringify({ v: 1, ...state([E('01', { dirty: true })]) }), 'utf8');
  const response = Buffer.from(JSON.stringify({ v: 1, state: state([E('01')]), summary: { added: 0, updated: 0, removed: 0, conflicts: 0 } }), 'utf8');
  let copies = 0;
  return {
    format: 1,
    generatedBy: 'scripts/sync-format.mjs',
    codes: [
      { typed, code }, { typed: 'AB3D9KXMP2QW', code }, { typed: 'il0o-1111-2222', code: '1100-1111-2222'.replaceAll('-', '') },
      { typed: 'AB3D-9KXM-P2Q', code: null }, { typed: 'AB3D-9KXM-P2QU', code: null },
    ],
    crypto: {
      note: 'Vectors use 100,000 iterations so tests stay fast; the apps use 600,000.',
      typed, code, iterations, hostNonceHex: hex(hostNonce), guestNonceHex: hex(guestNonce),
      guestToHostKeyHex: hex(keys.guestToHost), hostToGuestKeyHex: hex(keys.hostToGuest),
      exchanges: [[0, Buffer.from(HELLO), Buffer.from(HELLO)], [1, request, response], [2, request, response]].map(([counter, req, res]) => ({
        counter,
        hello: counter === 0,
        requestPlaintext: req.toString('utf8'),
        requestBodyBase64: requestBody(hostNonce, guestNonce, counter, seal(keys.guestToHost, hostNonce, guestNonce, 0, counter, req)).toString('base64'),
        responsePlaintext: res.toString('utf8'),
        responseBodyBase64: responseBody(counter, seal(keys.hostToGuest, hostNonce, guestNonce, 1, counter, res)).toString('base64'),
      })),
    },
    merges: MERGES.map(m => {
      const ids = [];
      const result = merge(m.host, m.guest, ' (Conflict copy)', () => { const id = COPY(String(++copies).padStart(2, '0')); ids.push(id); return id; });
      return { ...m, marker: ' (Conflict copy)', copyIds: ids, result: result.state, conflicts: result.conflicts,
        guestSummary: summary(m.guest, result.state, result.conflicts), hostSummary: summary(m.host, result.state, result.conflicts) };
    }),
    invalid: INVALID,
  };
}

function check(v) {
  let n = 0;
  const ok = (cond, what) => { if (!cond) throw new Error('vector failed: ' + what); n += 1; };
  for (const c of v.codes) ok(canonicalCode(c.typed) === c.code, 'code ' + c.typed);
  const hostNonce = Buffer.from(v.crypto.hostNonceHex, 'hex'), guestNonce = Buffer.from(v.crypto.guestNonceHex, 'hex');
  const keys = deriveKeys(canonicalCode(v.crypto.typed), hostNonce, guestNonce, v.crypto.iterations);
  ok(hex(keys.guestToHost) === v.crypto.guestToHostKeyHex && hex(keys.hostToGuest) === v.crypto.hostToGuestKeyHex, 'keys');
  ok(v.crypto.exchanges[0].hello && v.crypto.exchanges[0].requestPlaintext === HELLO && v.crypto.exchanges[0].responsePlaintext === HELLO, 'hello comes first');
  for (const x of v.crypto.exchanges) {
    const req = Buffer.from(x.requestBodyBase64, 'base64'), res = Buffer.from(x.responseBodyBase64, 'base64');
    ok(req.subarray(0, 16).equals(hostNonce) && req.subarray(16, 32).equals(guestNonce) && req.readBigUInt64BE(32) === BigInt(x.counter), 'request header');
    ok(open(keys.guestToHost, hostNonce, guestNonce, 0, x.counter, req.subarray(40)).toString('utf8') === x.requestPlaintext, 'request opens');
    ok(open(keys.hostToGuest, hostNonce, guestNonce, 1, x.counter, res.subarray(8)).toString('utf8') === x.responsePlaintext, 'response opens');
    ok(requestBody(hostNonce, guestNonce, x.counter, seal(keys.guestToHost, hostNonce, guestNonce, 0, x.counter, Buffer.from(x.requestPlaintext))).equals(req), 'request reproduced');
    // A frame must not open under the other direction, another counter or the other key.
    for (const [key, dir, counter] of [[keys.guestToHost, 1, x.counter], [keys.guestToHost, 0, x.counter + 1], [keys.hostToGuest, 0, x.counter]]) {
      let refused = false;
      try { open(key, hostNonce, guestNonce, dir, counter, req.subarray(40)); } catch { refused = true; }
      ok(refused, 'misuse refused');
    }
  }
  for (const m of v.merges) {
    const ids = [...m.copyIds];
    const result = merge(m.host, m.guest, m.marker, () => ids.shift());
    ok(JSON.stringify(result.state) === JSON.stringify(m.result) && result.conflicts === m.conflicts, 'merge: ' + m.name);
    ok(JSON.stringify(summary(m.guest, result.state, result.conflicts)) === JSON.stringify(m.guestSummary), 'guest summary: ' + m.name);
    ok(JSON.stringify(summary(m.host, result.state, result.conflicts)) === JSON.stringify(m.hostSummary), 'host summary: ' + m.name);
    // Merging the result with itself changes nothing.
    ok(JSON.stringify(merge(result.state, result.state, m.marker, () => { throw new Error('no copy expected'); }).state) === JSON.stringify(m.result), 'stable: ' + m.name);
  }
  for (const i of v.invalid) {
    let code = null;
    try { validate(i.state); } catch (e) { code = e.code; }
    ok(code === 'invalid', 'invalid: ' + i.name);
  }
  return n;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const path = new URL('../docs/sync-vectors.json', import.meta.url);
  if (!process.argv.includes('--check')) writeFileSync(path, JSON.stringify(build(), null, 2) + '\n');
  console.log(`${check(JSON.parse(readFileSync(path, 'utf8')))} checks passed`);
}
