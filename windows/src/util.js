'use strict';
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

function run(cmd, args, onData) {
  return new Promise((resolve, reject) => {
    const p = spawn(cmd, args, { windowsHide: true });
    let tail = '';
    const grab = (d) => {
      const s = d.toString();
      tail = (tail + s).slice(-1500);
      if (onData) onData(s);
    };
    p.stdout.on('data', grab);
    p.stderr.on('data', grab);
    p.on('error', reject);
    p.on('close', (code) => {
      if (code === 0) resolve(tail);
      else reject(new Error(tail.trim().split('\n').slice(-3).join(' ') || 'Ошибка (код ' + code + ')'));
    });
  });
}

function uniqueOut(dir, base, ext) {
  const name = (b) => (ext ? `${b}.${ext}` : b);
  let p = path.join(dir, name(base));
  let i = 1;
  while (fs.existsSync(p)) p = path.join(dir, name(`${base} (${i++})`));
  return p;
}

// PowerShell без проблем с кавычками и русскими буквами
function powershell(script) {
  const full = '[Console]::OutputEncoding=[Text.Encoding]::UTF8\n' + script;
  const enc = Buffer.from(full, 'utf16le').toString('base64');
  return run('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', enc]);
}
const psq = (s) => "'" + String(s).replace(/'/g, "''") + "'";

// Папка с портативными инструментами рядом с приложением: <app>/tools
function toolsDirs() {
  return [path.join(__dirname, '..', 'tools'), path.join(__dirname, '..', '..', 'tools')];
}

function findBundledFile(dir, fileName, depth) {
  if (depth < 0) return null;
  let list;
  try { list = fs.readdirSync(dir, { withFileTypes: true }); } catch (e) { return null; }
  for (const d of list) {
    if (d.isFile() && d.name.toLowerCase() === fileName.toLowerCase()) return path.join(dir, d.name);
  }
  for (const d of list) {
    if (d.isDirectory()) {
      const r = findBundledFile(path.join(dir, d.name), fileName, depth - 1);
      if (r) return r;
    }
  }
  return null;
}

// Свои инструменты ищем первыми: приложение должно работать и без установки в систему
function findBundledExe(name) {
  const exts = process.platform === 'win32' ? ['.exe', ''] : [''];
  for (const root of toolsDirs()) {
    if (!fs.existsSync(root)) continue;
    for (const e of exts) {
      const fileName = name + e;
      const direct = [
        path.join(root, fileName),
        path.join(root, name, fileName),
        path.join(root, name, 'bin', fileName),
        path.join(root, name, 'program', fileName)
      ];
      for (const p of direct) if (fs.existsSync(p)) return p;
      const deep = findBundledFile(root, fileName, 3);
      if (deep) return deep;
    }
  }
  return null;
}

// Ищет программу рядом с приложением, затем в PATH (например qpdf, gswin64c)
async function findExe(names) {
  for (const n of names) {
    const local = findBundledExe(n);
    if (local) return local;
  }
  for (const n of names) {
    try {
      const out = await run(process.platform === 'win32' ? 'where' : 'which', [n]);
      const line = out.split(/\r?\n/).find((l) => l.trim() && fs.existsSync(l.trim()));
      if (line) return line.trim();
    } catch (e) { /* не нашли */ }
  }
  return null;
}

function expandFiles(paths) {
  const result = [];
  const walk = (p) => {
    let st;
    try { st = fs.statSync(p); } catch (e) { return; }
    if (st.isDirectory()) {
      for (const n of fs.readdirSync(p)) if (!n.startsWith('.')) walk(path.join(p, n));
    } else if (st.isFile()) {
      result.push(p);
    }
  };
  paths.forEach(walk);
  return result;
}

module.exports = { run, uniqueOut, powershell, psq, findExe, expandFiles };
