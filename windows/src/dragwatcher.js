'use strict';
// Следит за перетаскиванием файлов по всей системе и нужными кнопками (Shift / Ctrl / Alt)
const { screen } = require('electron');

class DragWatcher {
  constructor(o) {
    this.o = o; // { getModes, getSelection, onShow, onHide, log }
    this.mods = { shift: false, ctrl: false, alt: false };
    this.isDown = false;
    this.dragging = false;
    this.files = null;
    this.lastMode = null;
    this.timer = null;
    this.session = 0;
  }

  start() {
    const { uIOhook, UiohookKey } = require('uiohook-napi');
    this.K = UiohookKey;
    uIOhook.on('keydown', (e) => this.key(e.keycode, true));
    uIOhook.on('keyup', (e) => this.key(e.keycode, false));
    uIOhook.on('mousedown', (e) => { if (e.button === 1) { this.sync(e); this.down(); } });
    uIOhook.on('mouseup', (e) => { if (e.button === 1) { this.sync(e); this.up(); } });
    uIOhook.start();
    this.o.log('Слежу за перетаскиванием файлов');
  }

  stop() {
    try { require('uiohook-napi').uIOhook.stop(); } catch (e) { /* уже остановлено */ }
  }

  // если пропустили отпускание кнопки, берём правду из самого события мыши
  sync(e) {
    this.mods = { shift: !!e.shiftKey, ctrl: !!e.ctrlKey, alt: !!e.altKey };
  }

  key(code, down) {
    const K = this.K;
    if (code === K.Shift || code === K.ShiftRight) this.mods.shift = down;
    else if (code === K.Ctrl || code === K.CtrlRight) this.mods.ctrl = down;
    else if (code === K.Alt || code === K.AltRight) this.mods.alt = down;
    else return;
    this.evaluate();
  }

  down() {
    this.isDown = true;
    this.dragging = false;
    this.files = null;
    this.lastMode = null;
    this.session++;
    this.startPoint = screen.getCursorScreenPoint();
    clearInterval(this.timer);
    this.timer = setInterval(() => this.poll(), 40);
  }

  poll() {
    if (!this.isDown || this.dragging) return;
    const p = screen.getCursorScreenPoint();
    if (Math.hypot(p.x - this.startPoint.x, p.y - this.startPoint.y) < 8) return;
    this.dragging = true;
    this.trySelection(this.session, 0);
  }

  // Выделение в Проводнике иногда не читается с первого раза (PowerShell стартует
  // медленно, окно может быть ещё не готово) — пробуем несколько раз, пока тянем.
  trySelection(mine, attempt) {
    this.o.getSelection().then((files) => {
      if (mine !== this.session || !this.dragging) return;
      const list = Array.isArray(files) ? files : [];
      if (!list.length && this.isDown && attempt < 12) {
        setTimeout(() => this.trySelection(mine, attempt + 1), 250);
        return;
      }
      this.files = list;
      this.o.log(`Перетаскивание: файлов ${list.length}`);
      this.evaluate();
    }).catch(() => {
      if (mine === this.session && this.dragging && this.isDown && attempt < 12) {
        setTimeout(() => this.trySelection(mine, attempt + 1), 250);
      }
    });
  }

  up() {
    const was = this.dragging;
    this.reset();
    if (was) this.o.onHide(1000); // даём системе доставить файл на сегмент
  }

  // вызывается, когда файл уже выбран на колесе
  stopDrag() { this.reset(); }

  reset() {
    this.isDown = false;
    this.dragging = false;
    this.files = null;
    this.lastMode = null;
    this.session++;
    clearInterval(this.timer);
    this.timer = null;
  }

  currentMode() {
    const pressed = Object.keys(this.mods).filter((k) => this.mods[k]);
    if (pressed.length !== 1) return null;
    const m = this.o.getModes();
    for (const mode of ['convert', 'tools', 'actions']) if (m[mode] === pressed[0]) return mode;
    return null;
  }

  evaluate() {
    if (!this.dragging || !this.files || !this.files.length) return;
    const mode = this.currentMode();
    if (mode && mode !== this.lastMode) this.o.onShow(mode, this.files);
    this.lastMode = mode;
  }
}

module.exports = { DragWatcher };
