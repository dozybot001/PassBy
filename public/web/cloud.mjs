import { NotebookError } from './crypto.mjs';
import { cloudConfig } from './config.mjs';
export class CloudNotebook {
  async authenticate(onUser, onSignOut, language, { remember = false, theme = 'black', onError = () => {} } = {}) {
    if (!cloudConfig.apiToken) throw new NotebookError('notConfigured');
    const generation = this.authGeneration = (this.authGeneration || 0) + 1;
    if (!globalThis.CloudKit) {
      if (!this.sdkLoading) this.sdkLoading = new Promise((resolve, reject) => {
        const script = document.createElement('script');
        script.src = 'https://cdn.apple-cloudkit.com/ck/2/cloudkit.js';
        script.onload = resolve;
        script.onerror = () => { this.sdkLoading = null; script.remove(); reject(new NotebookError('service')); };
        document.head.append(script);
      });
      await this.sdkLoading;
    }
    if (generation !== this.authGeneration) return;
    CloudKit.configure({ locale: language === 'zh' ? 'zh-cn' : 'en-us', containers: [{
      containerIdentifier: cloudConfig.containerIdentifier, environment: cloudConfig.environment,
      apiTokenAuth: { apiToken: cloudConfig.apiToken, persist: remember === true,
        signInButton: { id: 'apple-sign-in-button', theme },
        signOutButton: { id: 'apple-sign-out-button', theme } },
    }] });
    const container = CloudKit.getDefaultContainer();
    this.container = container;
    this.database = container.privateCloudDatabase;
    const active = () => generation === this.authGeneration;
    const failed = () => { if (active()) onError(new NotebookError('service')); };
    const watchIn = () => container.whenUserSignsIn().then(user => {
      if (!active()) return;
      onUser(user); watchOut();
    }).catch(failed);
    const watchOut = () => container.whenUserSignsOut().then(() => {
      if (!active()) return;
      onSignOut(); watchIn();
    }).catch(failed);
    const user = await container.setUpAuth();
    if (!active()) return;
    if (user) { onUser(user); watchOut(); } else watchIn();
  }
  async fetchRecord() {
    if (!this.database) throw new NotebookError('service');
    const response = await this.database.fetchRecords('notebook-v1');
    if (response.hasErrors) {
      if (response.errors?.some(e => ['UNKNOWN_ITEM','NOT_FOUND'].includes(e.ckErrorCode))) throw new NotebookError('noNotebook');
      throw new NotebookError('service');
    }
    const record = response.records?.[0];
    if (!record) throw new NotebookError('noNotebook');
    if (record.recordType !== 'Notebook' || record.fields?.format?.value !== 1) throw new NotebookError('version');
    return record;
  }
  async fetch() {
    const record = await this.fetchRecord();
    const url = record.fields?.ciphertext?.value?.downloadURL;
    if (typeof url !== 'string') throw new NotebookError('invalidNotebook');
    const assetURL = new URL(url.replace('${f}', 'notebook.enc'));
    // CloudKit supplies Apple CDN URLs. Never follow a record-supplied URL to an
    // arbitrary host (including a hostile container record).
    if (assetURL.protocol !== 'https:' || !/(^|\.)(icloud\.com|icloud-content\.com|apple\.com|apple-cloudkit\.com)$/.test(assetURL.hostname)) throw new NotebookError('invalidNotebook');
    const asset = await fetch(assetURL.href, { cache: 'no-store', credentials: 'omit', referrerPolicy: 'no-referrer' });
    if (!asset.ok) throw new NotebookError('service');
    return { record, bytes: await asset.arrayBuffer() };
  }
  async save(record, ciphertext) {
    const response = await this.database.saveRecords({
      recordName: record.recordName, recordType: 'Notebook', recordChangeTag: record.recordChangeTag,
      fields: { format: { value: 1 }, ciphertext: { value: new Blob([ciphertext], { type: 'application/octet-stream' }) } },
    });
    if (response.hasErrors) {
      if (response.errors?.some(e => e.ckErrorCode === 'CONFLICT')) throw new NotebookError('conflict');
      throw new NotebookError('service');
    }
    if (!response.records?.[0]) throw new NotebookError('service');
    return response.records[0];
  }
}
