import { NotebookError } from './crypto.mjs';

// Store an opaque CryptoKey, never the recovery phrase, passwords or auth tokens.
// This is browser-local authorization, not hardware-backed key protection.
export function bindingID(identity, appleUser) {
  if (identity?.issuer !== 'https://account.tenon.asia/api/auth' || !identity.sub || !appleUser) throw new NotebookError('locked');
  return JSON.stringify([identity.issuer, identity.sub, appleUser]);
}
export class TrustedBrowser {
  async request(binding, mode, operation) {
    if (!globalThis.indexedDB) throw new NotebookError('browserStorage');
    const db = await new Promise((resolve, reject) => {
      const open = indexedDB.open('passby-trusted-browser', 1);
      open.onupgradeneeded = () => open.result.createObjectStore('keys');
      open.onsuccess = () => resolve(open.result);
      open.onerror = () => reject(new NotebookError('browserStorage'));
    });
    try {
      return await new Promise((resolve, reject) => {
        const transaction = db.transaction('keys', mode);
        const request = operation(transaction.objectStore('keys'), binding);
        transaction.oncomplete = () => resolve(request.result);
        transaction.onerror = transaction.onabort = () => reject(new NotebookError('browserStorage'));
      });
    } finally { db.close(); }
  }
  get(binding) { return this.request(binding, 'readonly', (store, id) => store.get(id)); }
  async save(binding, key) {
    if (!key || key.type !== 'secret' || key.extractable || key.algorithm?.name !== 'AES-GCM' || key.algorithm.length !== 256) throw new NotebookError('invalidKey');
    await this.request(binding, 'readwrite', (store, id) => store.put(key, id));
  }
  forget(binding) { return this.request(binding, 'readwrite', (store, id) => store.delete(id)); }
}
