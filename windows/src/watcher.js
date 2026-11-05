'use strict';
// Папки-наблюдатели: новый файл в выбранной папке сам конвертируется в нужный формат
const fs = require('fs');
const path = require('path');
const { kindOf, norm } = require('./formats');

class FolderWatcher {
  // o: { getRules, convert(file, target, outDir), onDone(dir, count, errors), interval, log }
  constructor(o) {
    this.o = o;
    this.state = new Map();
    this.busy = false;
    this.timer = null;
  }

  start() { this.timer = setInterval(() => this.scan().catch((e) => this.o.log && this.o.log('Наблюдатель: ' + e.message)), this.o.interval || 3000); }
  stop() { clearInterval(this.timer); this.timer = null; }

  async scan() {
    if (this.busy) return;
    this.busy = true;
    try {
      for (const rule of this.o.getRules()) await this.scanRule(rule);
    } finally {
      this.busy = false;
    }
  }

  async scanRule(rule) {
    const dir = rule.path;
    let entries;
    try { entries = fs.readdirSync(dir, { withFileTypes: true }).filter((e) => e.isFile() && !e.name.startsWith('.') && !e.name.startsWith('~$')); } catch (e) { return; }
    const first = !this.state.has(dir);
    if (first) this.state.set(dir, new Map());
    const known = this.state.get(dir);
    let converted = 0;
    const errors = [];
    for (const e of entries) {
      const file = path.join(dir, e.name);
      let size;
      try { size = fs.statSync(file).size; } catch (err) { continue; }
      let st = known.get(e.name);
      if (!st) {
        st = { size, stable: 0, done: first }; // файлы, которые уже лежали при запуске, не трогаем
        known.set(e.name, st);
        continue;
      }
      if (st.done) continue;
      if (size === st.size && size > 0) st.stable++; else { st.size = size; st.stable = 0; }
      if (st.stable < 1) continue; // ждём, пока файл допишется
      st.done = true;
      const ext = norm(path.extname(e.name).slice(1));
      const kind = kindOf(ext);
      const target = kind && rule[kind];
      if (!target || target === ext) continue;
      try {
        await this.o.convert(file, target, path.join(dir, 'Готово'));
        converted++;
      } catch (err) {
        errors.push(`${e.name}: ${err.message}`);
      }
    }
    if ((converted || errors.length) && this.o.onDone) this.o.onDone(dir, converted, errors);
  }
}

module.exports = { FolderWatcher };
