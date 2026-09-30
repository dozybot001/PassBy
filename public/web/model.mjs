import { NotebookError } from './crypto.mjs';
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const newID = () => crypto.randomUUID().toUpperCase();
export function validateVault(value) {
  if (value?.schemaVersion !== 1) throw new NotebookError('version');
  if (!Array.isArray(value.folders) || !Array.isArray(value.entries)) throw new NotebookError('invalidNotebook');
  const folders = new Set(), entries = new Set();
  const validID = (id, set) => {
    if (typeof id !== 'string' || !uuid.test(id) || set.has(id.toUpperCase())) throw new NotebookError('invalidNotebook');
    set.add(id.toUpperCase()); return id.toUpperCase();
  };
  const result = { schemaVersion: 1, folders: value.folders.map(f => {
    if (typeof f?.name !== 'string') throw new NotebookError('invalidNotebook');
    return { id: validID(f.id, folders), name: f.name };
  }), entries: value.entries.map(e => {
    if (!e || !['title','account','password','notes'].every(k => typeof e[k] === 'string')) throw new NotebookError('invalidNotebook');
    const folderID = e.folderID == null ? null : typeof e.folderID === 'string' ? e.folderID.toUpperCase() : false;
    if (folderID !== null && !folders.has(folderID)) throw new NotebookError('invalidNotebook');
    return { id: validID(e.id, entries), title: e.title, account: e.account, password: e.password, notes: e.notes, ...(folderID ? { folderID } : {}) };
  }) };
  return result;
}
const same = (a, b) => a === undefined || b === undefined ? a === b : JSON.stringify(a) === JSON.stringify(b);
export function mergeVault(base, local, remote, suffix = ' (Conflict copy)') {
  const result = { schemaVersion: 1, entries: [], folders: [] };
  let conflicts = 0;
  for (const kind of ['entries', 'folders']) {
    const [b,l,r] = [base,local,remote].map(v => new Map(v[kind].map(x => [x.id, x])));
    for (const id of [...new Set([...b.keys(), ...l.keys(), ...r.keys()])].sort()) {
      const original = b.get(id), ours = l.get(id), theirs = r.get(id);
      if (kind === 'folders') { const value = same(ours, original) ? theirs : ours; if (value) result.folders.push(value); }
      else if (same(ours, original)) { if (theirs) result.entries.push(theirs); }
      else if (same(theirs, original) || same(ours, theirs)) { if (ours) result.entries.push(ours); }
      else if (ours && theirs) { result.entries.push(theirs, { ...ours, id: newID(), title: ours.title + suffix }); conflicts++; }
      else { result.entries.push(ours || theirs); conflicts++; }
    }
  }
  const folders = new Set(result.folders.map(f => f.id));
  result.entries = result.entries.map(e => { const copy = { ...e }; if (!folders.has(copy.folderID)) delete copy.folderID; return copy; });
  return { vault: validateVault(result), conflicts };
}
