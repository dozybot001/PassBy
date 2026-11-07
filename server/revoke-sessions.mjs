// S2 of the tenonai.cn move, after Tenon has removed the old callbacks. Run once
// in the current identity container; iPhones then sign in again:
//   docker exec <container> node revoke-sessions.mjs https://tenon.asia
import { SessionStore } from './sessions.mjs';

const store = new SessionStore(process.env.SESSION_DB || '/data/sessions.sqlite');
try { console.log(JSON.stringify(store.revokeAll(process.argv[2], Date.now()))); }
finally { store.close(); }
