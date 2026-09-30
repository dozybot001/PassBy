// Browser API token is public by design. Restrict it to the deployment origin
// in CloudKit Console; never use a server-to-server key here.
export const cloudConfig = Object.freeze({
  containerIdentifier: 'iCloud.cn.tenonai.apps.passby',
  environment: 'production',
  apiToken: '082c7de8449c00d538d5873a00d4f57cfc001ab46148b6689e7da9ba92914cb0',
});
