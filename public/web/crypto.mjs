const aad = new TextEncoder().encode('PassBy.local-notebook.v1');
export class NotebookError extends Error {
  constructor(code) { super(code); this.code = code; }
}
export async function recoveryKey(text) {
  const hex = text.replace(/[\s-]/gu, '').toUpperCase();
  if (!/^[0-9A-F]{68}$/.test(hex)) throw new NotebookError('invalidKey');
  const bytes = Uint8Array.from(hex.match(/../g), x => parseInt(x, 16));
  try {
    const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes.subarray(0, 32)));
    if ((digest[0] ^ bytes[32]) | (digest[1] ^ bytes[33])) throw new NotebookError('invalidKey');
    return await crypto.subtle.importKey('raw', bytes.subarray(0, 32), 'AES-GCM', false, ['encrypt', 'decrypt']);
  } finally { bytes.fill(0); }
}
export async function openNotebook(data, key) {
  const bytes = new Uint8Array(data);
  if (bytes.length < 28 || bytes.length > 16 * 1024 * 1024) throw new NotebookError('invalidNotebook');
  let plain;
  try {
    plain = new Uint8Array(await crypto.subtle.decrypt({ name: 'AES-GCM', iv: bytes.subarray(0, 12), additionalData: aad, tagLength: 128 }, key, bytes.subarray(12)));
  } catch { throw new NotebookError('wrongKey'); }
  try { return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(plain)); }
  catch { throw new NotebookError('invalidNotebook'); }
  finally { plain.fill(0); }
}
export async function sealNotebook(vault, key) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const plain = new TextEncoder().encode(JSON.stringify(vault));
  try {
    const ciphertext = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv, additionalData: aad, tagLength: 128 }, key, plain));
    const combined = new Uint8Array(12 + ciphertext.length);
    combined.set(iv); combined.set(ciphertext, 12);
    return combined;
  } finally { plain.fill(0); }
}
function randomIndex(limit) {
  const ceiling = 0x100000000 - (0x100000000 % limit);
  const word = new Uint32Array(1);
  do { crypto.getRandomValues(word); } while (word[0] >= ceiling);
  return word[0] % limit;
}
export function generatePassword(length = 16, options = { upper: true, lower: true, digits: true, symbols: true }) {
  if (!Number.isInteger(length) || length < 8 || length > 4096) throw new NotebookError('invalidLength');
  const groups = [options.upper && 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', options.lower && 'abcdefghijklmnopqrstuvwxyz', options.digits && '0123456789', options.symbols && '!@#$%^&*()-_=+[]{};:,.?'].filter(Boolean);
  if (!groups.length) throw new NotebookError('selectCharacters');
  const alphabet = groups.join('');
  const chars = groups.map(group => group[randomIndex(group.length)]);
  while (chars.length < length) chars.push(alphabet[randomIndex(alphabet.length)]);
  for (let i = chars.length - 1; i > 0; i--) { const j = randomIndex(i + 1); [chars[i], chars[j]] = [chars[j], chars[i]]; }
  return chars.join('');
}
