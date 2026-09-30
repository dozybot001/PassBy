import { NotebookError } from './crypto.mjs';
import { cloudConfig } from './config.mjs';
export class CloudNotebook {
  async authenticate(onUser, onSignOut, language) {
    if (!cloudConfig.apiToken) throw new NotebookError('notConfigured');
    if (!globalThis.CloudKit) {
      await new Promise((resolve, reject) => {
        const script = document.createElement('script');
        script.src = 'https://cdn.apple-cloudkit.com/ck/2/cloudkit.js';
        script.onload = resolve; script.onerror = () => reject(new NotebookError('service'));
        document.head.append(script);
      });
    }
    CloudKit.configure({ locale: language === 'zh' ? 'zh-cn' : 'en-us', containers: [{
      containerIdentifier: cloudConfig.containerIdentifier, environment: cloudConfig.environment,
      apiTokenAuth: { apiToken: cloudConfig.apiToken, persist: false,
        signInButton: { id: 'apple-sign-in-button', theme: 'black' },
        signOutButton: { id: 'apple-sign-out-button', theme: 'black' } },
    }] });
    this.container = CloudKit.getDefaultContainer();
    this.database = this.container.privateCloudDatabase;
    const watchIn = () => this.container.whenUserSignsIn().then(user => { onUser(user); watchOut(); });
    const watchOut = () => this.container.whenUserSignsOut().then(() => { onSignOut(); watchIn(); });
    const user = await this.container.setUpAuth();
    if (user) { onUser(user); watchOut(); } else watchIn();
  }
  async fetch() {
    const response = await this.database.fetchRecords('notebook-v1');
    if (response.hasErrors) {
      if (response.errors?.some(e => ['UNKNOWN_ITEM','NOT_FOUND'].includes(e.ckErrorCode))) throw new NotebookError('noNotebook');
      throw new NotebookError('service');
    }
    const record = response.records?.[0];
    if (!record) throw new NotebookError('noNotebook');
    if (record.recordType !== 'Notebook' || record.fields?.format?.value !== 1) throw new NotebookError('version');
    const url = record.fields?.ciphertext?.value?.downloadURL;
    const assetURL = new URL(url);
    // CloudKit supplies Apple CDN URLs. Never follow a record-supplied URL to an
    // arbitrary host (including a hostile container record).
    if (assetURL.protocol !== 'https:' || !/(^|\.)(icloud\.com|icloud-content\.com|apple\.com|apple-cloudkit\.com)$/.test(assetURL.hostname)) throw new NotebookError('invalidNotebook');
    const asset = await fetch(assetURL.href.replace('${f}', 'notebook.enc'), { cache: 'no-store', credentials: 'omit', referrerPolicy: 'no-referrer' });
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
