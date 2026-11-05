'use strict';
const { contextBridge, ipcRenderer, webUtils } = require('electron');

const on = (channel, cb) => {
  const listener = (_e, ...args) => cb(...args);
  ipcRenderer.on(channel, listener);
  return () => ipcRenderer.removeListener(channel, listener);
};

contextBridge.exposeInMainWorld('api', {
  pathFor: (file) => webUtils.getPathForFile(file),
  formats: () => ipcRenderer.invoke('formats:get'),
  prefs: () => ipcRenderer.invoke('prefs:get'),
  setPrefs: (patch) => ipcRenderer.invoke('prefs:set', patch),
  wheelState: (kind) => ipcRenderer.invoke('wheel:state', kind),
  saveWheel: (kind, order, hidden) => ipcRenderer.invoke('wheel:save', kind, order, hidden),
  resetWheel: (kind) => ipcRenderer.invoke('wheel:reset', kind),
  pickFiles: () => ipcRenderer.invoke('pick:files'),
  pickFolder: () => ipcRenderer.invoke('pick:folder'),
  expand: (paths) => ipcRenderer.invoke('expand', paths),
  convert: (file, target) => ipcRenderer.invoke('convert:file', file, target),
  reveal: (p) => ipcRenderer.invoke('reveal', p),
  openSettings: () => ipcRenderer.invoke('win:settings'),
  onProgress: (cb) => on('convert:progress', cb),
  wheelPick: (id, paths) => ipcRenderer.send('wheel:pick', id, paths),
  onWheel: (cb) => on('wheel:data', cb),
  onToast: (cb) => on('toast:update', cb),
  toastReveal: () => ipcRenderer.send('toast:reveal'),
  onDialog: (cb) => on('dialog:config', cb),
  dialogReady: (height) => ipcRenderer.send('dialog:ready', height),
  dialogDone: (result) => ipcRenderer.send('dialog:done', result)
});
