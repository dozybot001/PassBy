// Writes the PassBy export file (docs/export-format.md) with WebCrypto only.
const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const ITERATIONS = 600000;
const text = new TextEncoder();

// 20 Crockford Base32 characters from the system random source, shown as four groups of five.
export function newExportCode(random = bytes => crypto.getRandomValues(bytes)) {
  const values = random(new Uint8Array(20));
  // 256 is a multiple of 32, so the low five bits are uniform.
  const code = Array.from(values, value => ALPHABET[value & 31]).join('');
  return code.match(/.{5}/g).join('-');
}

export async function exportNotebook(vault, code, { now = new Date(), salt, nonce } = {}) {
  const secret = text.encode(code.replaceAll('-', ''));
  if (secret.length !== 20) throw new Error('Invalid export code');
  salt ??= crypto.getRandomValues(new Uint8Array(16));
  nonce ??= crypto.getRandomValues(new Uint8Array(12));
  const base = await crypto.subtle.importKey('raw', secret, 'PBKDF2', false, ['deriveBits']);
  const master = await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt, iterations: ITERATIONS }, base, 256);
  const hkdf = await crypto.subtle.importKey('raw', master, 'HKDF', false, ['deriveKey']);
  const derive = (info, algorithm, usages) => crypto.subtle.deriveKey(
    { name: 'HKDF', hash: 'SHA-256', salt: new Uint8Array(0), info: text.encode(info) }, hkdf, algorithm, false, usages);
  const encryptKey = await derive('PassBy export v1 encrypt', { name: 'AES-GCM', length: 256 }, ['encrypt']);
  const checkKey = await derive('PassBy export v1 check', { name: 'HMAC', hash: 'SHA-256', length: 256 }, ['sign']);
  const check = new Uint8Array(await crypto.subtle.sign('HMAC', checkKey, text.encode('PassBy export key check'))).subarray(0, 16);

  const header = new Uint8Array(58);
  header.set(text.encode('PASSBYEX'), 0);
  header[8] = 1; header[9] = 1;
  new DataView(header.buffer).setUint32(10, ITERATIONS);
  header.set(salt, 14); header.set(nonce, 30); header.set(check, 42);

  const plaintext = JSON.stringify({
    format: 1,
    exportedAt: now.toISOString().replace(/\.\d{3}Z$/, 'Z'),
    folders: vault.folders.map(folder => ({ id: folder.id.toUpperCase(), name: folder.name })),
    entries: vault.entries.map(entry => ({
      id: entry.id.toUpperCase(), title: entry.title, account: entry.account, password: entry.password, notes: entry.notes,
      ...(entry.folderID ? { folderID: entry.folderID.toUpperCase() } : {}),
    })),
  });
  const body = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce, additionalData: header }, encryptKey, text.encode(plaintext)));
  const file = new Uint8Array(header.length + body.length);
  file.set(header); file.set(body, header.length);
  return file;
}

export function exportFileName(now = new Date()) {
  const pad = value => String(value).padStart(2, '0');
  return `PassBy-${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}.passby`;
}
