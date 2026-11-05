'use strict';
const fs = require('fs');
const path = require('path');
const { KINDS, DEFAULT_HIDDEN } = require('./formats');

const defaults = {
  modConvert: 'shift', modTools: 'alt', modActions: 'ctrl',
  saveMode: 0,            // 0 рядом, 1 подпапка Converted, 2 выбранная папка
  outputFolder: '',
  trashOriginal: false,
  notify: true, sound: true,
  imageQuality: 90, imageMaxSide: 0,
  audioBitrate: 192,
  videoQuality: 1,        // 0 высокое, 1 среднее, 2 малое
  videoMaxHeight: 0,
  watchEnabled: false, watchFolders: [],
  contextMenu: false,
  wheels: {}
};

let file = null;
let data = { ...defaults, wheels: {} };

function init(dir) {
  file = path.join(dir, 'prefs.json');
  try { data = { ...defaults, ...JSON.parse(fs.readFileSync(file, 'utf8')) }; } catch (e) { data = { ...defaults, wheels: {} }; }
  if (!data.wheels) data.wheels = {};
}

function save() {
  if (!file) return;
  try {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, JSON.stringify(data, null, 2));
  } catch (e) { /* не страшно */ }
}

const get = (k) => data[k];
const all = () => JSON.parse(JSON.stringify(data));
function set(patch) { Object.assign(data, patch); save(); }

// Свои колёса форматов: порядок и скрытые пункты для каждого типа файла
function wheelState(kind) {
  const outs = KINDS[kind].out;
  const saved = data.wheels[kind] || {};
  const order = (saved.order || []).filter((f) => outs.includes(f));
  for (const f of outs) if (!order.includes(f)) order.push(f);
  const hidden = saved.hidden ? saved.hidden.filter((f) => outs.includes(f)) : (DEFAULT_HIDDEN[kind] || []);
  return { order, hidden };
}
function saveWheel(kind, order, hidden) { data.wheels[kind] = { order, hidden }; save(); }
function resetWheel(kind) { delete data.wheels[kind]; save(); }
function wheelFor(kind) {
  const s = wheelState(kind);
  return s.order.filter((f) => !s.hidden.includes(f));
}

module.exports = { init, get, all, set, wheelState, saveWheel, resetWheel, wheelFor, defaults };
