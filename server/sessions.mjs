import { DatabaseSync } from 'node:sqlite';
import { mkdirSync, lstatSync, openSync, closeSync, constants } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { createHash } from 'node:crypto';

const unavailable = () => Object.assign(new Error('Session storage unavailable'), { status: 503 });
const validHash = value => typeof value === 'string' && /^[A-Za-z0-9_-]{43}$/.test(value);
const validOrigin = value => ['https://tenon.asia', 'https://passby.tenon.asia'].includes(value);
const REVOCATION_TTL = 30 * 24 * 60 * 60 * 1000;
const MAX_REFRESH_RECORDS = 50000;
const subjectKey = (issuer, sub) => createHash('sha256').update(`${issuer}\n${sub}`).digest('base64url');
const validIdentity = value => value?.issuer === 'https://account.tenon.asia/api/auth'
  && typeof value.sub === 'string' && value.sub.length > 0 && typeof value.name === 'string'
  && ['admin', 'user'].includes(value.role) && Number.isSafeInteger(value.expires) && value.expires > 0;

// Only product token hashes and verified identity snapshots belong here.
// Central tokens, refresh credential plaintext and login transactions stay out
// of SQLite. Digest-only rotation/revocation history closes logout races.
export class SessionStore {
  #db;
  constructor(path) {
    try {
      if (path !== ':memory:') {
        path = resolve(path);
        mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
        const directory = lstatSync(dirname(path));
        if (!directory.isDirectory() || directory.isSymbolicLink() || (directory.mode & 0o777) !== 0o700
          || directory.uid !== process.getuid()) throw unavailable();
        try { closeSync(openSync(path, constants.O_CREAT | constants.O_EXCL | constants.O_WRONLY, 0o600)); }
        catch (error) { if (error.code !== 'EEXIST') throw error; }
        const file = lstatSync(path);
        if (!file.isFile() || file.isSymbolicLink() || (file.mode & 0o777) !== 0o600 || file.uid !== process.getuid()) throw unavailable();
      }
      this.#db = new DatabaseSync(path);
      this.#db.exec('PRAGMA busy_timeout=5000; PRAGMA journal_mode=DELETE; PRAGMA synchronous=FULL;');
      const version = this.#db.prepare('PRAGMA user_version').get().user_version;
      if (version !== 0 && version !== 1) throw unavailable();
      this.#db.exec('BEGIN IMMEDIATE');
      try {
        this.#db.exec(`CREATE TABLE IF NOT EXISTS product_sessions (
          origin TEXT NOT NULL, token_hash TEXT NOT NULL, issuer TEXT NOT NULL,
          subject TEXT NOT NULL, name TEXT NOT NULL, role TEXT NOT NULL,
          expires INTEGER NOT NULL CHECK(typeof(expires)='integer' AND expires>0), native_refresh_hash TEXT,
          PRIMARY KEY(origin, token_hash), CHECK(role IN ('admin','user'))
        );
        CREATE INDEX IF NOT EXISTS product_sessions_expiry ON product_sessions(origin, expires);
        CREATE INDEX IF NOT EXISTS product_sessions_refresh ON product_sessions(origin, native_refresh_hash);
        CREATE TABLE IF NOT EXISTS revoked_refresh (
          origin TEXT NOT NULL, refresh_hash TEXT NOT NULL,
          expires INTEGER NOT NULL CHECK(typeof(expires)='integer' AND expires>0),
          PRIMARY KEY(origin, refresh_hash)
        );
        CREATE INDEX IF NOT EXISTS revoked_refresh_expiry ON revoked_refresh(origin, expires);
        CREATE TABLE IF NOT EXISTS refresh_rotations (
          origin TEXT NOT NULL, previous_hash TEXT NOT NULL, refresh_hash TEXT NOT NULL,
          expires INTEGER NOT NULL CHECK(typeof(expires)='integer' AND expires>0),
          PRIMARY KEY(origin, previous_hash, refresh_hash)
        );
        CREATE INDEX IF NOT EXISTS refresh_rotations_expiry ON refresh_rotations(origin, expires);
        CREATE TABLE IF NOT EXISTS product_deletion_receipts (
          operation_id TEXT PRIMARY KEY, subject_hash TEXT NOT NULL, deleted_at INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS product_deletion_epochs (
          subject_hash TEXT PRIMARY KEY, generation INTEGER NOT NULL UNIQUE
        );
        PRAGMA user_version=1; COMMIT;`);
      } catch (error) { try { this.#db.exec('ROLLBACK'); } catch {} throw error; }
      this.health();
    } catch {
      try { this.#db?.close(); } catch {}
      throw unavailable();
    }
  }
  #run(operation) {
    try { return operation(); }
    catch (error) { if ([401, 429].includes(error.status)) throw error; throw unavailable(); }
  }
  health() { return this.#run(() => this.#db.prepare('SELECT (SELECT count(*) FROM product_sessions) AS count, (SELECT count(*) FROM revoked_refresh) AS revoked, (SELECT count(*) FROM refresh_rotations) AS rotations, (SELECT count(*) FROM product_deletion_receipts) AS deletions, (SELECT count(*) FROM product_deletion_epochs) AS generations').get().count); }
  count(origin, now) { return this.#run(() => this.#db.prepare('SELECT count(*) AS count FROM product_sessions WHERE origin=? AND expires>?').get(origin, now).count); }
  prune(origin, now) {
    this.#run(() => {
      this.#db.prepare('DELETE FROM product_sessions WHERE origin=? AND expires<=?').run(origin, now);
      this.#db.prepare('DELETE FROM revoked_refresh WHERE origin=? AND expires<=?').run(origin, now);
      this.#db.prepare('DELETE FROM refresh_rotations WHERE origin=? AND expires<=?').run(origin, now);
    });
  }
  get(origin, key, now) {
    return this.#run(() => {
      const row = this.#db.prepare('SELECT issuer, subject AS sub, name, role, expires FROM product_sessions WHERE origin=? AND token_hash=? AND expires>?').get(origin, key, now);
      if (!row) return undefined;
      if (!validIdentity(row)) throw unavailable();
      return { ...row };
    });
  }
  generation() { return this.#run(() => this.#db.prepare('SELECT coalesce(max(generation),0) AS value FROM product_deletion_epochs').get().value); }
  assertGeneration(issuer, sub, generation) {
    return this.#run(() => {
      const row = this.#db.prepare('SELECT generation FROM product_deletion_epochs WHERE subject_hash=?').get(subjectKey(issuer, sub));
      if (!Number.isSafeInteger(generation) || generation < 0 || row && row.generation > generation) throw Object.assign(new Error('Authorization superseded by deletion'), { status: 401 });
    });
  }
  assertRefresh(origin, issuer, sub, hash, now) {
    this.#run(() => {
      if (this.#db.prepare('SELECT 1 FROM revoked_refresh WHERE origin=? AND refresh_hash=? AND expires>?').get(origin, hash, now)) throw Object.assign(new Error('Session credential revoked'), { status: 401 });
      if (this.#db.prepare('SELECT 1 FROM product_deletion_epochs WHERE subject_hash=?').get(subjectKey(issuer, sub))) {
        const current = this.#db.prepare(`WITH RECURSIVE credentials(hash) AS (
          VALUES(?) UNION SELECT r.refresh_hash FROM refresh_rotations r JOIN credentials c ON r.previous_hash=c.hash WHERE r.origin=? AND r.expires>?
        ) SELECT 1 FROM product_sessions s JOIN credentials c ON s.native_refresh_hash=c.hash WHERE s.origin=? AND s.issuer=? AND s.subject=? AND s.expires>? LIMIT 1`).get(hash, origin, now, origin, issuer, sub, now);
        if (!current) throw Object.assign(new Error('Product identity deleted'), { status: 401 });
      }
    });
  }
  create(origin, key, session, now, { nativeRefreshHash = null, retireRefreshHash = null, authorizationGeneration = this.generation() } = {}) {
    if (!validOrigin(origin) || !validHash(key) || !validIdentity(session) || session.expires <= now
      || retireRefreshHash !== null && !validHash(retireRefreshHash)
      || nativeRefreshHash !== null && !validHash(nativeRefreshHash)) throw unavailable();
    this.#run(() => {
      this.#db.exec('BEGIN IMMEDIATE');
      try {
        this.assertGeneration(session.issuer, session.sub, authorizationGeneration);
        this.prune(origin, now);
        const revoked = this.#db.prepare('SELECT 1 FROM revoked_refresh WHERE origin=? AND refresh_hash=? AND expires>?');
        if ([nativeRefreshHash, retireRefreshHash].some(hash => hash !== null && revoked.get(origin, hash, now))) {
          throw Object.assign(new Error('Session credential revoked'), { status: 401 });
        }
        if (retireRefreshHash !== null) this.#db.prepare('DELETE FROM product_sessions WHERE origin=? AND native_refresh_hash=?').run(origin, retireRefreshHash);
        if (this.count(origin, now) >= 5000) throw Object.assign(new Error('Session capacity unavailable'), { status: 429 });
        if (retireRefreshHash !== null && nativeRefreshHash !== null) {
          const existing = this.#db.prepare('SELECT 1 FROM refresh_rotations WHERE origin=? AND previous_hash=? AND refresh_hash=?').get(origin, retireRefreshHash, nativeRefreshHash);
          if (!existing && this.#db.prepare('SELECT count(*) AS count FROM refresh_rotations WHERE origin=?').get(origin).count >= MAX_REFRESH_RECORDS) {
            throw Object.assign(new Error('Credential capacity unavailable'), { status: 429 });
          }
          this.#db.prepare('INSERT INTO refresh_rotations VALUES(?,?,?,?) ON CONFLICT(origin,previous_hash,refresh_hash) DO UPDATE SET expires=max(expires,excluded.expires)').run(origin, retireRefreshHash, nativeRefreshHash, now + REVOCATION_TTL);
        }
        const insert = this.#db.prepare('INSERT INTO product_sessions(origin, token_hash, issuer, subject, name, role, expires, native_refresh_hash) VALUES(?,?,?,?,?,?,?,?)');
        insert.run(origin, key, session.issuer, session.sub, session.name, session.role, session.expires, nativeRefreshHash);
        this.#db.exec('COMMIT');
      } catch (error) { try { this.#db.exec('ROLLBACK'); } catch {} throw error; }
    });
  }
  delete(origin, key) { this.#run(() => this.#db.prepare('DELETE FROM product_sessions WHERE origin=? AND token_hash=?').run(origin, key)); }
  deleteProduct(issuer, sub, operationId, now, { previouslyCompleted = false } = {}) {
    if (issuer !== 'https://account.tenon.asia/api/auth' || typeof sub !== 'string' || !sub || sub.length > 256 || !/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i.test(operationId) || !Number.isSafeInteger(now)) throw unavailable();
    return this.#run(() => {
      this.#db.exec('BEGIN IMMEDIATE');
      try {
        const hash = subjectKey(issuer, sub);
        const receipt = this.#db.prepare('SELECT subject_hash FROM product_deletion_receipts WHERE operation_id=?').get(operationId);
        if (receipt) {
          if (receipt.subject_hash !== hash) throw Object.assign(new Error('Receipt identity mismatch'), { status: 401 });
          this.#db.exec('COMMIT'); return;
        }
        if (previouslyCompleted) throw unavailable();
        for (const origin of ['https://tenon.asia', 'https://passby.tenon.asia']) {
          this.prune(origin, now);
          const credentials = this.#db.prepare(`WITH RECURSIVE credentials(hash) AS (
            SELECT native_refresh_hash FROM product_sessions WHERE origin=? AND issuer=? AND subject=? AND native_refresh_hash IS NOT NULL
            UNION SELECT r.refresh_hash FROM refresh_rotations r JOIN credentials c ON r.previous_hash=c.hash WHERE r.origin=? AND r.expires>?
          ) SELECT hash FROM credentials`).all(origin, issuer, sub, origin, now);
          const mark = this.#db.prepare('INSERT INTO revoked_refresh VALUES(?,?,?) ON CONFLICT(origin,refresh_hash) DO UPDATE SET expires=max(expires,excluded.expires)');
          if (credentials.length + this.#db.prepare('SELECT count(*) AS count FROM revoked_refresh WHERE origin=?').get(origin).count > MAX_REFRESH_RECORDS) throw Object.assign(new Error('Credential capacity unavailable'), { status: 429 });
          for (const { hash: refreshHash } of credentials) mark.run(origin, refreshHash, now + REVOCATION_TTL);
        }
        this.#db.prepare('DELETE FROM product_sessions WHERE issuer=? AND subject=?').run(issuer, sub);
        const generation = this.generation() + 1;
        this.#db.prepare('INSERT INTO product_deletion_epochs VALUES(?,?) ON CONFLICT(subject_hash) DO UPDATE SET generation=excluded.generation').run(hash, generation);
        this.#db.prepare('INSERT INTO product_deletion_receipts VALUES(?,?,?)').run(operationId, hash, now);
        this.#db.exec('COMMIT');
      } catch (error) { try { this.#db.exec('ROLLBACK'); } catch {} throw error; }
    });
  }
  revoke(origin, refreshHash, now) {
    if (!validOrigin(origin) || !validHash(refreshHash) || !Number.isSafeInteger(now)) throw unavailable();
    this.#run(() => {
      this.#db.exec('BEGIN IMMEDIATE');
      try {
        this.prune(origin, now);
        const hashes = this.#db.prepare(`WITH RECURSIVE credentials(hash) AS (
          VALUES(?) UNION SELECT r.refresh_hash FROM refresh_rotations r JOIN credentials c ON r.previous_hash=c.hash
          WHERE r.origin=? AND r.expires>?
        ) SELECT hash FROM credentials`).all(refreshHash, origin, now);
        const existing = this.#db.prepare('SELECT 1 FROM revoked_refresh WHERE origin=? AND refresh_hash=?');
        const additional = hashes.filter(({ hash }) => !existing.get(origin, hash)).length;
        if (this.#db.prepare('SELECT count(*) AS count FROM revoked_refresh WHERE origin=?').get(origin).count + additional > MAX_REFRESH_RECORDS) {
          throw Object.assign(new Error('Credential capacity unavailable'), { status: 429 });
        }
        const mark = this.#db.prepare('INSERT INTO revoked_refresh VALUES(?,?,?) ON CONFLICT(origin,refresh_hash) DO UPDATE SET expires=max(expires,excluded.expires)');
        const remove = this.#db.prepare('DELETE FROM product_sessions WHERE origin=? AND native_refresh_hash=?');
        for (const { hash } of hashes) { mark.run(origin, hash, now + REVOCATION_TTL); remove.run(origin, hash); }
        this.#db.exec('COMMIT');
      } catch (error) { try { this.#db.exec('ROLLBACK'); } catch {} throw error; }
    });
  }
  close() { this.#db.close(); }
}
