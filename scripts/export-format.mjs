// Reference implementation of the PassBy export file (docs/export-format.md).
// `node scripts/export-format.mjs` regenerates docs/export-vectors.json and checks every vector.
// `node scripts/export-format.mjs --check` only checks the committed vectors.
import { createCipheriv, createDecipheriv, createHash, createHmac, hkdfSync, pbkdf2Sync, timingSafeEqual } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';

export const MAGIC = Buffer.from('PASSBYEX', 'ascii');
export const HEADER_LENGTH = 58;
export const DEFAULT_ITERATIONS = 600_000;
export const MIN_ITERATIONS = 100_000;
export const MAX_ITERATIONS = 10_000_000;
const CODE_ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
// Characters trimmed from a passphrase and removed from an export code (docs/export-format.md §2).
const SPACE = new Set([0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0x85, 0xA0, 0x1680, 0x2000, 0x2001, 0x2002, 0x2003,
  0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF]);
const DASH = new Set([0x2D, 0x2010, 0x2011, 0x2012, 0x2013, 0x2014, 0x2015]);

export class ExportError extends Error {
  constructor(code) { super(code); this.code = code; }
}

// Returns the canonical export code, or null when the input is not one.
export function canonicalCode(input) {
  let out = '';
  for (const ch of input) {
    const cp = ch.codePointAt(0);
    if (SPACE.has(cp) || DASH.has(cp)) continue;
    let c = cp >= 0x61 && cp <= 0x7A ? String.fromCharCode(cp - 32) : ch;
    if (c === 'I' || c === 'L') c = '1';
    else if (c === 'O') c = '0';
    if (!CODE_ALPHABET.includes(c)) return null;
    out += c;
  }
  return out.length === 20 ? out : null;
}

function trimSpace(input) {
  const chars = [...input];
  let start = 0, end = chars.length;
  while (start < end && SPACE.has(chars[start].codePointAt(0))) start++;
  while (end > start && SPACE.has(chars[end - 1].codePointAt(0))) end--;
  return chars.slice(start, end).join('');
}

// Bytes fed to PBKDF2 for what the person typed when importing.
export function secretBytes(input) {
  const code = canonicalCode(input);
  if (code) return { kind: 'code', bytes: Buffer.from(code, 'ascii') };
  return { kind: 'passphrase', bytes: Buffer.from(trimSpace(input).normalize('NFC'), 'utf8') };
}

// Rules for a passphrase the person sets when exporting; returns null when it is acceptable.
export function passphraseProblem(input) {
  if (trimSpace(input) !== input) return 'surroundingSpace';
  if (canonicalCode(input)) return 'looksLikeCode';
  if ([...input.normalize('NFC')].length < 12) return 'tooShort';
  return null;
}

export function deriveKeys(secret, salt, iterations) {
  const master = pbkdf2Sync(secret, salt, iterations, 32, 'sha256');
  const encrypt = Buffer.from(hkdfSync('sha256', master, Buffer.alloc(0), 'PassBy export v1 encrypt', 32));
  const checkKey = Buffer.from(hkdfSync('sha256', master, Buffer.alloc(0), 'PassBy export v1 check', 32));
  const check = createHmac('sha256', checkKey).update('PassBy export key check', 'ascii').digest().subarray(0, 16);
  return { master, encrypt, checkKey, check };
}

export function encode({ secret, salt, nonce, iterations = DEFAULT_ITERATIONS, plaintext }) {
  const keys = deriveKeys(secret, salt, iterations);
  const header = Buffer.alloc(HEADER_LENGTH);
  MAGIC.copy(header, 0);
  header[8] = 1;
  header[9] = 1;
  header.writeUInt32BE(iterations, 10);
  salt.copy(header, 14);
  nonce.copy(header, 30);
  keys.check.copy(header, 42);
  const cipher = createCipheriv('aes-256-gcm', keys.encrypt, nonce);
  cipher.setAAD(header);
  const body = Buffer.concat([cipher.update(plaintext), cipher.final(), cipher.getAuthTag()]);
  return { file: Buffer.concat([header, body]), keys };
}

export function decode(file, input) {
  if (file.length < HEADER_LENGTH + 16 || !file.subarray(0, 8).equals(MAGIC)) throw new ExportError('notExport');
  if (file[8] !== 1 || file[9] !== 1) throw new ExportError('update');
  const iterations = file.readUInt32BE(10);
  if (iterations < MIN_ITERATIONS || iterations > MAX_ITERATIONS) throw new ExportError('damaged');
  const header = file.subarray(0, HEADER_LENGTH);
  const keys = deriveKeys(secretBytes(input).bytes, file.subarray(14, 30), iterations);
  if (!timingSafeEqual(keys.check, file.subarray(42, 58))) throw new ExportError('wrongCode');
  const decipher = createDecipheriv('aes-256-gcm', keys.encrypt, file.subarray(30, 42));
  decipher.setAAD(header);
  decipher.setAuthTag(file.subarray(file.length - 16));
  let plaintext;
  try { plaintext = Buffer.concat([decipher.update(file.subarray(HEADER_LENGTH, file.length - 16)), decipher.final()]); }
  catch { throw new ExportError('damaged'); }
  let notebook;
  try { notebook = JSON.parse(plaintext.toString('utf8')); } catch { throw new ExportError('damaged'); }
  if (!Number.isInteger(notebook?.format)) throw new ExportError('damaged');
  if (notebook.format !== 1) throw new ExportError('update');
  validate(notebook);
  return notebook;
}

const UUID = /^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$/;
function validate(n) {
  const text = v => typeof v === 'string';
  const ok = text(n.exportedAt) && !Number.isNaN(Date.parse(n.exportedAt))
    && Array.isArray(n.folders) && Array.isArray(n.entries)
    && n.folders.every(f => UUID.test(f?.id) && text(f.name))
    && n.entries.every(e => UUID.test(e?.id) && ['title', 'account', 'password', 'notes'].every(k => text(e[k]))
      && (e.folderID === undefined || UUID.test(e.folderID)));
  if (!ok) throw new ExportError('damaged');
  const folderIDs = new Set(n.folders.map(f => f.id.toUpperCase()));
  const entryIDs = new Set(n.entries.map(e => e.id.toUpperCase()));
  if (folderIDs.size !== n.folders.length || entryIDs.size !== n.entries.length
    || n.entries.some(e => e.folderID !== undefined && !folderIDs.has(e.folderID.toUpperCase()))) {
    throw new ExportError('damaged');
  }
}

// ---- Test vectors ----

const fixed = (label, length) => createHash('sha256').update(label).digest().subarray(0, length);
const hex = b => Buffer.from(b).toString('hex');

const SAMPLE = {
  format: 1,
  exportedAt: '2026-11-14T12:00:00Z',
  folders: [{ id: '6F1C2A4E-8B3D-4C5E-9F60-1A2B3C4D5E6F', name: '工作 Work' }],
  entries: [
    { id: '0E8F6A2B-1C3D-4E5F-8A9B-0C1D2E3F4A5B', title: '个人邮箱', account: 'alex@example.com',
      password: 'p@ss 密码 🔑', notes: '第一行\nsecond line', folderID: '6F1C2A4E-8B3D-4C5E-9F60-1A2B3C4D5E6F' },
    { id: 'A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D', title: 'Café', account: '', password: 'x', notes: '' },
  ],
};
const EMPTY = { format: 1, exportedAt: '2026-11-14T12:00:00Z', folders: [], entries: [] };

const VALID = [
  { name: 'export code', typed: '7K3M9-Q2XHB-R8T4V-W6YZ0', equivalents: ['7k3m9 q2xhb r8t4v w6yz0', '7K3M9Q2XHBR8T4VW6YZO', ' 7k3m9-q2xhb-r8t4v-w6yzo '], iterations: DEFAULT_ITERATIONS, notebook: SAMPLE },
  { name: 'export code with I and L', typed: 'IL000-11111-22222-33333', equivalents: ['1100011111222223333 3', 'il0oo-1lI1l-22222-33333'], iterations: MIN_ITERATIONS, notebook: EMPTY },
  { name: 'Chinese passphrase', typed: '  我的密码本备份口令二〇二六  ', iterations: MIN_ITERATIONS, notebook: SAMPLE },
  { name: 'passphrase with emoji (surrogate pair)', typed: 'Backup 🔐 notebook 2026', iterations: MIN_ITERATIONS, notebook: SAMPLE },
  { name: 'passphrase typed with combining marks (NFD)', typed: 'Café crème brûlée', iterations: MIN_ITERATIONS, notebook: SAMPLE },
];

function buildVectors() {
  const valid = VALID.map(v => {
    const { kind, bytes } = secretBytes(v.typed);
    const salt = fixed(`${v.name} salt`, 16), nonce = fixed(`${v.name} nonce`, 12);
    const plaintext = JSON.stringify(v.notebook);
    const { file, keys } = encode({ secret: bytes, salt, nonce, iterations: v.iterations, plaintext: Buffer.from(plaintext, 'utf8') });
    return {
      name: v.name, typed: v.typed, equivalentInputs: v.equivalents ?? [], kind, secretHex: hex(bytes),
      iterations: v.iterations, saltHex: hex(salt), nonceHex: hex(nonce),
      masterKeyHex: hex(keys.master), encryptKeyHex: hex(keys.encrypt), checkKeyHex: hex(keys.checkKey), checkHex: hex(keys.check),
      plaintext, fileBase64: file.toString('base64'),
    };
  });
  const base = Buffer.from(valid[2].fileBase64, 'base64');
  const typed = valid[2].typed;
  const tweak = (fn) => { const b = Buffer.from(base); fn(b); return b.toString('base64'); };
  const invalid = [
    { name: 'wrong passphrase', typed: '我的密码本备份口令二〇二七', fileBase64: base.toString('base64'), error: 'wrongCode' },
    { name: 'ciphertext changed', typed, fileBase64: tweak(b => { b[HEADER_LENGTH] ^= 1; }), error: 'damaged' },
    { name: 'nonce changed', typed, fileBase64: tweak(b => { b[30] ^= 1; }), error: 'damaged' },
    { name: 'tag changed', typed, fileBase64: tweak(b => { b[b.length - 1] ^= 1; }), error: 'damaged' },
    { name: 'iterations below range', typed, fileBase64: tweak(b => b.writeUInt32BE(MIN_ITERATIONS - 1, 10)), error: 'damaged' },
    { name: 'iterations above range', typed, fileBase64: tweak(b => b.writeUInt32BE(MAX_ITERATIONS + 1, 10)), error: 'damaged' },
    { name: 'unknown format version', typed, fileBase64: tweak(b => { b[8] = 2; }), error: 'update' },
    { name: 'unknown key derivation', typed, fileBase64: tweak(b => { b[9] = 2; }), error: 'update' },
    { name: 'not an export file', typed, fileBase64: tweak(b => { b[0] = 0x58; }), error: 'notExport' },
    { name: 'truncated file', typed, fileBase64: base.subarray(0, HEADER_LENGTH + 15).toString('base64'), error: 'notExport' },
  ];
  const passphraseRules = [
    { typed: 'short 密码', problem: 'tooShort' },
    { typed: ' leading space passphrase', problem: 'surroundingSpace' },
    { typed: 'abcde-fghjk-mnpqr-stvwx', problem: 'looksLikeCode' },
    { typed: '我的密码本备份口令二〇二六', problem: null },
  ];
  return { format: 'PassBy export v1', generatedBy: 'scripts/export-format.mjs', valid, invalid, passphraseRules };
}

function check(vectors) {
  let count = 0;
  for (const v of vectors.valid) {
    const file = Buffer.from(v.fileBase64, 'base64');
    for (const input of [v.typed, ...v.equivalentInputs]) {
      if (hex(secretBytes(input).bytes) !== v.secretHex) throw new Error(`${v.name}: secret bytes for ${JSON.stringify(input)}`);
      const notebook = decode(file, input);
      if (JSON.stringify(notebook) !== v.plaintext) throw new Error(`${v.name}: plaintext`);
      count++;
    }
    const again = encode({ secret: Buffer.from(v.secretHex, 'hex'), salt: Buffer.from(v.saltHex, 'hex'), nonce: Buffer.from(v.nonceHex, 'hex'), iterations: v.iterations, plaintext: Buffer.from(v.plaintext, 'utf8') });
    if (again.file.toString('base64') !== v.fileBase64) throw new Error(`${v.name}: encode is not deterministic`);
  }
  for (const v of vectors.invalid) {
    try { decode(Buffer.from(v.fileBase64, 'base64'), v.typed); throw new Error(`${v.name}: expected ${v.error}`); }
    catch (e) { if (!(e instanceof ExportError) || e.code !== v.error) throw new Error(`${v.name}: got ${e.code ?? e.message}, expected ${v.error}`); }
    count++;
  }
  for (const r of vectors.passphraseRules) {
    if (passphraseProblem(r.typed) !== r.problem) throw new Error(`passphrase rule ${JSON.stringify(r.typed)}`);
    count++;
  }
  return count;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const path = new URL('../docs/export-vectors.json', import.meta.url);
  const vectors = process.argv.includes('--check') ? JSON.parse(readFileSync(path, 'utf8')) : buildVectors();
  const count = check(vectors);
  if (!process.argv.includes('--check')) writeFileSync(path, JSON.stringify(vectors, null, 2) + '\n');
  console.log(`${count} checks passed`);
}
