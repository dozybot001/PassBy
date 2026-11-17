// Turns a PassBy export file (docs/export-format.md) into a CSV that Google Password Manager and
// Chrome import: name,url,username,password,note.
//   node scripts/export-to-csv.mjs PassBy-2026-11-18.passby [out.csv]
// The export code or passphrase is asked for in the terminal and is not shown or stored.
// The CSV holds every password in plain text: import it, then delete it.
import { chmodSync, readFileSync, writeFileSync } from 'node:fs';
import { createInterface } from 'node:readline';
import { decode, ExportError } from './export-format.mjs';

const [input, output = input?.replace(/(\.passby)?$/, '.csv')] = process.argv.slice(2);
if (!input) {
  console.error('Usage: node scripts/export-to-csv.mjs <file.passby> [out.csv]');
  process.exit(2);
}

function ask(question) {
  return new Promise(resolve => {
    const rl = createInterface({ input: process.stdin, output: process.stdout, terminal: process.stdin.isTTY });
    // Nothing typed after the question is echoed.
    if (process.stdin.isTTY) rl._writeToOutput = text => { if (text.includes(question)) process.stdout.write(question); };
    rl.question(question, answer => { rl.close(); if (process.stdin.isTTY) process.stdout.write('\n'); resolve(answer); });
  });
}

// PassBy has no address field. Take one from the title or the notes when it is plainly there.
function address(entry) {
  for (const text of [entry.title, entry.notes]) {
    const url = text.match(/https?:\/\/[^\s<>"'，。；、）)]+/i);
    if (url) return url[0];
    const host = text.match(/(?<![\w@.-])(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}(?![\w@-])/i);
    if (host) return 'https://' + host[0].toLowerCase();
  }
  return '';
}

const cell = value => /[",\r\n]/.test(value) ? '"' + value.replaceAll('"', '""') + '"' : value;

let notebook;
try {
  notebook = decode(readFileSync(input), await ask('Export code or passphrase 导出码或口令: '));
} catch (error) {
  if (!(error instanceof ExportError)) throw error;
  console.error({ wrongCode: 'Wrong export code or passphrase. 导出码或口令不对。', notExport: 'Not a PassBy export file. 不是 PassBy 导出文件。',
    update: 'Made by a newer PassBy. 这个文件来自更新的 PassBy。' }[error.code] ?? 'The file is damaged. 文件已损坏。');
  process.exit(1);
}

const folders = new Map(notebook.folders.map(f => [f.id.toUpperCase(), f.name]));
let without = 0;
const rows = notebook.entries.map(entry => {
  const url = address(entry);
  if (!url) without++;
  const folder = entry.folderID && folders.get(entry.folderID.toUpperCase());
  const note = [entry.notes, folder && `PassBy: ${folder}`].filter(Boolean).join('\n');
  return [entry.title, url, entry.account, entry.password, note].map(cell).join(',');
});
writeFileSync(output, ['name,url,username,password,note', ...rows].join('\r\n') + '\r\n', { mode: 0o600 });
chmodSync(output, 0o600);
console.log(`${rows.length} entries written to ${output} (${without} without a web address).`);
console.log(`写出 ${rows.length} 条到 ${output}（其中 ${without} 条没有网址）。导入后请删除这个文件，里面是明文密码。`);
