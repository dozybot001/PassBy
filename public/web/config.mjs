// Browser API token is public by design. Restrict it to the deployment origin
// in CloudKit Console; never use a server-to-server key here.
// The web app moved here from passby.tenon.asia on 2026-11-14. The notice explains
// why a browser must sign in and be authorized again; empty `host` hides it.
export const moveNotice = Object.freeze({ host: 'passby.tenonai.cn' });

export const cloudConfig = Object.freeze({
  containerIdentifier: 'iCloud.cn.tenonai.apps.passby',
  environment: 'production',
  apiToken: '082c7de8449c00d538d5873a00d4f57cfc001ab46148b6689e7da9ba92914cb0',
});
