'use strict';
// Колесо действий: копия, путь, ZIP, дубль, переименовать, переместить
const fs = require('fs');
const path = require('path');
const { uniqueOut, powershell, psq } = require('./util');

const I = (id, title, icon) => ({ id, title, icon });
const ITEMS = [
  I('copy', 'Копия', '📋'), I('path', 'Путь', '🔗'), I('zip', 'ZIP', '🗜️'), I('duplicate', 'Дубль', '⧉'),
  I('rename', 'Имя', '✏️'), I('move', 'В папку', '📁'), I('desktop', 'На стол', '🖥️'), I('explorer', 'Проводник', '🔎')
];
const items = () => ITEMS;

const baseOf = (f) => path.basename(f, path.extname(f));
const extOf = (f) => path.extname(f).slice(1);

async function runAction(id, files, ui) {
  const what = files.length === 1 ? path.basename(files[0]) : `Файлов: ${files.length}`;
  switch (id) {
    case 'copy':
      await powershell(`Set-Clipboard -LiteralPath @(${files.map(psq).join(',')})`);
      return ui.note('Скопировано', 'Вставь куда нужно: Ctrl+V');
    case 'path':
      ui.clipboardText(files.join('\n'));
      return ui.note('Путь скопирован', what);
    case 'zip': {
      const out = uniqueOut(path.dirname(files[0]), files.length === 1 ? baseOf(files[0]) : 'Архив', 'zip');
      return ui.job('Архивирую…', what, async () => {
        await powershell(`Compress-Archive -LiteralPath @(${files.map(psq).join(',')}) -DestinationPath ${psq(out)}`);
        return [out];
      });
    }
    case 'duplicate': {
      const done = [];
      for (const f of files) {
        const dest = uniqueOut(path.dirname(f), baseOf(f) + ' копия', extOf(f));
        try { fs.cpSync(f, dest, { recursive: true }); done.push(dest); } catch (e) { /* пропускаем */ }
      }
      return report(ui, done, 'Копия создана', 'Не удалось создать копию');
    }
    case 'rename': {
      const r = await ui.ask({
        title: 'Переименовать',
        message: 'Шаблон: {имя} старое имя, {n} номер, {дата} сегодняшняя дата. Расширение сохранится.',
        fields: [{ label: '', value: files.length > 1 ? '{имя} {n}' : baseOf(files[0]) }],
        buttons: ['OK']
      });
      const template = r && r.values[0].trim();
      if (!template) return;
      const today = new Date().toISOString().slice(0, 10);
      const done = [];
      files.forEach((f, i) => {
        let name = template.replace(/\{имя\}/g, baseOf(f)).replace(/\{n\}/g, String(i + 1)).replace(/\{дата\}/g, today);
        if (files.length > 1 && !template.includes('{n}')) name += ` ${i + 1}`;
        name = name.replace(/[\\/:*?"<>|]/g, '-');
        const same = path.join(path.dirname(f), extOf(f) ? `${name}.${extOf(f)}` : name);
        if (same === f) { done.push(f); return; } // имя не изменилось
        const dest = uniqueOut(path.dirname(f), name, extOf(f));
        try { fs.renameSync(f, dest); done.push(dest); } catch (e) { /* пропускаем */ }
      });
      return report(ui, done, 'Переименовано', 'Не удалось переименовать');
    }
    case 'move': {
      const places = [['Рабочий стол', 'desktop'], ['Документы', 'documents'], ['Загрузки', 'downloads'], ['Изображения', 'pictures'], ['Видео', 'videos'], ['Музыка', 'music']];
      const r = await ui.ask({ title: 'Переместить в…', message: what, fields: [], buttons: [...places.map((p) => p[0]), 'Другая папка…'], vertical: true });
      if (!r) return;
      const folder = r.button < places.length ? ui.paths[places[r.button][1]] : await ui.pickFolder();
      if (!folder) return;
      const done = [];
      for (const f of files) {
        if (path.resolve(path.dirname(f)) === path.resolve(folder)) { done.push(f); continue; } // уже в этой папке
        const dest = uniqueOut(folder, baseOf(f), extOf(f));
        try { fs.renameSync(f, dest); done.push(dest); } catch (e) {
          try { fs.cpSync(f, dest, { recursive: true }); fs.rmSync(f, { recursive: true, force: true }); done.push(dest); } catch (e2) { /* пропускаем */ }
        }
      }
      return report(ui, done, 'Перемещено', 'Не удалось переместить');
    }
    case 'desktop': {
      const done = [];
      for (const f of files) {
        const dest = uniqueOut(ui.paths.desktop, baseOf(f), extOf(f));
        try { fs.cpSync(f, dest, { recursive: true }); done.push(dest); } catch (e) { /* пропускаем */ }
      }
      return report(ui, done, 'На рабочем столе', 'Не удалось скопировать на рабочий стол');
    }
    case 'explorer':
      return ui.reveal(files[0]);
    default:
  }
}

function report(ui, done, ok, fail) {
  if (!done.length) ui.info(fail, 'Проверь права доступа к папке');
  else ui.note(ok, done.length === 1 ? path.basename(done[0]) : `Файлов: ${done.length}`);
}

module.exports = { items, runAction };
