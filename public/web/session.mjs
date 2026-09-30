import { recoveryKey, openNotebook, sealNotebook, NotebookError } from './crypto.mjs';
import { validateVault, mergeVault } from './model.mjs';
export class NotebookSession {
  constructor(cloud) { this.cloud = cloud; this.generation = 0; this.busy = false; }
  lock() { this.generation++; this.key = null; this.vault = null; this.base = null; this.record = null; this.busy = false; }
  check(generation) { if (generation !== this.generation) throw new NotebookError('locked'); }
  async unlock(text) {
    const generation = ++this.generation;
    const key = await recoveryKey(text);
    const data = await this.cloud.fetch(); this.check(generation);
    const vault = validateVault(await openNotebook(data.bytes, key)); this.check(generation);
    this.key = key; this.vault = vault; this.base = structuredClone(vault); this.record = data.record;
    return vault;
  }
  async refresh() {
    if (!this.key || this.busy) throw new NotebookError('locked');
    const generation = this.generation, key = this.key;
    this.busy = true;
    try {
      const data = await this.cloud.fetch(); this.check(generation);
      const vault = validateVault(await openNotebook(data.bytes, key)); this.check(generation);
      this.vault = vault; this.base = structuredClone(vault); this.record = data.record;
    } finally { if (generation === this.generation) this.busy = false; }
  }
  async save(local, suffix) {
    if (!this.key || this.busy) throw new NotebookError('locked');
    local = validateVault(local);
    this.busy = true;
    const generation = this.generation, key = this.key, base = this.base;
    try {
      for (let attempt = 0; attempt < 3; attempt++) {
        const remote = await this.cloud.fetch(); this.check(generation);
        const remoteVault = validateVault(await openNotebook(remote.bytes, key)); this.check(generation);
        const merged = mergeVault(base, local, remoteVault, suffix);
        const sealed = await sealNotebook(merged.vault, key); this.check(generation);
        try {
          const record = await this.cloud.save(remote.record, sealed); this.check(generation);
          this.vault = merged.vault; this.base = structuredClone(merged.vault); this.record = record;
          return merged.conflicts;
        } catch (error) { if (error.code !== 'conflict' || attempt === 2) throw error; }
      }
    } finally { if (generation === this.generation) this.busy = false; }
  }
}
