// Browser API token is public by design. Restrict it to the deployment origin
// in CloudKit Console; never use a server-to-server key here.
// The tenonai.cn switch: set `date` (YYYY-MM-DD) once it is scheduled to warn
// on the old host, and keep it set after the switch to explain on the new host
// why a browser must sign in and be authorized again. Empty hides the notice.
export const moveNotice = Object.freeze({ date: '2026-11-17', host: 'passby.tenonai.cn' });

export const cloudConfig = Object.freeze({
  containerIdentifier: 'iCloud.cn.tenonai.apps.passby',
  environment: 'production',
  apiToken: '082c7de8449c00d538d5873a00d4f57cfc001ab46148b6689e7da9ba92914cb0',
});
