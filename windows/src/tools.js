'use strict';
// Колесо инструментов: обрезать, без звука, сжать, склеить, кадры, водяной знак, PDF и др.
const fs = require('fs');
const fsp = fs.promises;
const os = require('os');
const path = require('path');
const { run, uniqueOut, findExe } = require('./util');
const { kindOf, norm } = require('./formats');
const prefs = require('./prefs');
const C = require('./convert');
const Shrink = require('./shrink');
const R = require('./resize');
const AFX = require('./audiofx');
const S = require('./speech');
const BG = require('./bgremove');

const extOf = (f) => norm(path.extname(f).slice(1));
const baseOf = (f) => path.basename(f, path.extname(f));
const sorted = (files) => [...files].sort((a, b) => path.basename(a).localeCompare(path.basename(b), undefined, { numeric: true }));
const outPath = (src, suffix, ext) =>
  uniqueOut(C.outputDir(src), `${baseOf(src)} (${suffix})`, ext || path.extname(src).slice(1));

async function ff(args, to) {
  try {
    await run(C.requireFFmpeg(), ['-y', '-nostdin', '-hide_banner', ...args, to]);
  } catch (e) {
    fs.rmSync(to, { force: true });
    throw e;
  }
  return to;
}

// ---------- пункты колеса ----------
const I = (id, title, icon) => ({ id, title, icon });

function items(files) {
  const kind = files[0] && kindOf(extOf(files[0]));
  if (!kind) return [];
  let list = [];
  switch (kind) {
    case 'video': list = [I('mute', 'Без звука', '🔇'), I('trim', 'Обрезать', '✂️'), I('compress', 'Сжать…', '🗜️'), I('merge', 'Склеить', '🔗'), I('frames', 'Кадры', '🎞️'), I('resize', 'Размер', '🔍'), I('ai', 'ИИ-увеличение', '✨'), I('fx', 'Звук…', '🔊'), I('subs', 'Субтитры', '💬')]; break;
    case 'audio': list = [I('trim', 'Обрезать', '✂️'), I('compress', 'Сжать…', '🗜️'), I('fx', 'Звук…', '🔊'), I('merge', 'Склеить', '🔗'), I('subs', 'Текст речи', '💬')]; break;
    case 'image': list = [I('compress', 'Сжать…', '🗜️'), I('resize', 'Размер', '🔍'), I('rotate', 'Повернуть', '↻'), I('strip', 'Без EXIF', '📍'), I('topdf', 'В один PDF', '📄'), I('ocr', 'Текст с фото', '🔤'), I('watermark', 'Водяной знак', '💧'), I('ai', 'ИИ-увеличение', '✨'), I('bgremove', 'Убрать фон', '🪄')]; break;
    case 'pdf': list = [I('merge', 'Объединить', '🔗'), I('split', 'По страницам', '✂️'), I('rotate', 'Повернуть', '↻'), I('compress', 'Сжать', '🗜️'), I('password', 'Пароль', '🔒')]; break;
    default:
      list = [I('topdf', 'В PDF', '📄')];
      if (kind === 'doc') list.push(I('totxt', 'В текст', '📝'));
      if (files.length > 1) list.push(I('mergepdf', 'Склеить в PDF', '🔗'));
  }
  if (files.length < 2) list = list.filter((i) => i.id !== 'merge');
  return list;
}

// ---------- видео и звук ----------
const mute = (src) => ff(['-i', src, '-an', '-c:v', 'copy'], outPath(src, 'без звука'));
const compressVideo = (src) => ff(['-i', src, '-c:v', 'libx264', '-preset', 'medium', '-crf', '28', '-pix_fmt', 'yuv420p',
  '-c:a', 'aac', '-b:a', '128k', '-movflags', '+faststart'], outPath(src, 'сжато', 'mp4'));
const compressAudio = (src) => ff(['-i', src, '-vn', '-c:a', 'libmp3lame', '-b:a', '128k'], outPath(src, 'сжато', 'mp3'));
const normalize = (src) => ff(['-i', src, '-vn', '-af', 'loudnorm=I=-16:TP=-1.5:LRA=11', '-c:a', 'libmp3lame', '-q:a', '2'],
  outPath(src, 'громкость', 'mp3'));

function trim(src, start, end) {
  const from = start.toFixed(3);
  const len = (end - start).toFixed(3);
  const ext = extOf(src);
  if (kindOf(ext) === 'video') {
    const outExt = ['mp4', 'mov', 'mkv'].includes(ext) ? ext : 'mp4';
    return ff(['-ss', from, '-i', src, '-t', len, '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '20', '-pix_fmt', 'yuv420p',
      '-c:a', 'aac', '-b:a', '192k'], outPath(src, 'обрезано', outExt));
  }
  return ff(['-ss', from, '-i', src, '-t', len, '-c', 'copy', '-avoid_negative_ts', 'make_zero'], outPath(src, 'обрезано'));
}

async function mergeMedia(files, kind) {
  const list = sorted(files);
  if (!list.every((f) => kindOf(extOf(f)) === kind)) throw new Error('Склеивать можно только файлы одного типа');
  const txt = path.join(os.tmpdir(), `konv-${process.pid}-${Date.now()}.txt`);
  fs.writeFileSync(txt, list.map((f) => "file '" + f.replace(/\\/g, '/').replace(/'/g, "'\\''") + "'").join('\n'));
  try {
    const codec = kind === 'video'
      ? ['-c:v', 'libx264', '-preset', 'medium', '-crf', '20', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '192k', '-movflags', '+faststart']
      : ['-vn', '-c:a', 'libmp3lame', '-q:a', '2'];
    return await ff(['-f', 'concat', '-safe', '0', '-i', txt, ...codec], outPath(list[0], 'объединено', kind === 'video' ? 'mp4' : 'mp3'));
  } finally {
    fs.rmSync(txt, { force: true });
  }
}

async function frames(src, every) {
  const folder = uniqueOut(C.outputDir(src), `${baseOf(src)} (кадры)`, '');
  fs.mkdirSync(folder, { recursive: true });
  try {
    await ff(['-i', src, '-vf', `fps=1/${every}`, '-q:v', '2'], path.join(folder, 'кадр_%03d.jpg'));
  } catch (e) {
    fs.rmSync(folder, { recursive: true, force: true });
    throw e;
  }
  return folder;
}

// ---------- фото ----------
function formatFor(ext) {
  return { jpg: ['jpeg', 'jpg'], png: ['png', 'png'], webp: ['webp', 'webp'], avif: ['avif', 'avif'], tiff: ['tiff', 'tiff'] }[ext] || ['png', 'png'];
}

async function compressImage(src) {
  const out = outPath(src, 'сжато', 'jpg');
  await (await C.openImage(src)).flatten({ background: '#ffffff' }).jpeg({ quality: 65 }).toFile(out);
  return out;
}

async function halfImage(src) {
  const img = await C.openImage(src);
  const meta = await img.clone().metadata();
  const [fmt, ext] = formatFor(extOf(src));
  const out = outPath(src, '½', ext);
  await img.resize({ width: Math.max(1, Math.round(meta.width / 2)) }).toFormat(fmt, { quality: prefs.get('imageQuality') }).toFile(out);
  return out;
}

async function rotateImage(src) {
  const sharp = require('sharp');
  const png = await (await C.openImage(src)).png().toBuffer();
  const [fmt, ext] = formatFor(extOf(src));
  const out = outPath(src, 'повернуто', ext);
  await sharp(png).rotate(90).toFormat(fmt, { quality: prefs.get('imageQuality') }).toFile(out);
  return out;
}

async function stripMeta(src) {
  const [fmt, ext] = formatFor(extOf(src));
  const out = outPath(src, 'без метаданных', ext);
  await (await C.openImage(src)).toFormat(fmt, { quality: prefs.get('imageQuality') }).toFile(out); // sharp не переносит EXIF
  return out;
}

async function imagesToPdf(files) {
  const list = sorted(files);
  const bufs = [];
  for (const f of list) bufs.push(await (await C.openImage(f)).flatten({ background: '#ffffff' }).jpeg({ quality: prefs.get('imageQuality') }).toBuffer());
  const out = uniqueOut(C.outputDir(list[0]), baseOf(list[0]) + (list.length > 1 ? ` (+${list.length - 1})` : ''), 'pdf');
  await C.imageToPdf(bufs, out);
  return out;
}

async function watermark(src, text) {
  const sharp = require('sharp');
  const png = await (await C.openImage(src)).png().toBuffer();
  const meta = await sharp(png).metadata();
  const size = Math.round(Math.min(meta.width, meta.height) / 12);
  const svg = `<svg width="${meta.width}" height="${meta.height}" xmlns="http://www.w3.org/2000/svg">
<text x="${meta.width - size * 0.6}" y="${meta.height - size * 0.6}" text-anchor="end" font-family="Segoe UI, Arial, sans-serif"
 font-size="${size}" font-weight="bold" fill="#ffffff" fill-opacity="0.75" stroke="#000000" stroke-opacity="0.35" stroke-width="${Math.max(1, size / 25)}">${C.escapeHtml(text)}</text></svg>`;
  const jpg = extOf(src) === 'jpg';
  const out = outPath(src, 'водяной знак', jpg ? 'jpg' : 'png');
  const img = sharp(png).composite([{ input: Buffer.from(svg) }]);
  await (jpg ? img.flatten({ background: '#ffffff' }).jpeg({ quality: prefs.get('imageQuality') }) : img.png()).toFile(out);
  return out;
}

// Распознавание текста (языки лежат внутри приложения, интернет не нужен)
function langDir() {
  const dir = path.join(os.tmpdir(), 'konverter-ocr');
  fs.mkdirSync(dir, { recursive: true });
  for (const [pkg, name] of [['@tesseract.js-data/rus', 'rus'], ['@tesseract.js-data/eng', 'eng']]) {
    const dest = path.join(dir, `${name}.traineddata.gz`);
    if (!fs.existsSync(dest)) fs.copyFileSync(require.resolve(`${pkg}/4.0.0_best_int/${name}.traineddata.gz`), dest);
  }
  return dir;
}

async function ocr(src, ui) {
  const { createWorker } = require('tesseract.js');
  const png = await (await C.openImage(src)).png().toBuffer();
  const dir = langDir();
  const worker = await createWorker(['rus', 'eng'], 1, { langPath: dir, cachePath: dir, gzip: true });
  let text;
  try { text = (await worker.recognize(png)).data.text.trim(); } finally { await worker.terminate(); }
  if (!text) throw new Error('Текст на картинке не найден');
  const out = outPath(src, 'текст', 'txt');
  await fsp.writeFile(out, text, 'utf8');
  if (ui && ui.clipboardText) ui.clipboardText(text);
  return out;
}

// ---------- PDF ----------
async function loadPdf(file) {
  const { PDFDocument } = require('pdf-lib');
  return PDFDocument.load(await fsp.readFile(file), { ignoreEncryption: true });
}

async function mergePDF(files) {
  const { PDFDocument } = require('pdf-lib');
  const list = sorted(files);
  const doc = await PDFDocument.create();
  for (const f of list) {
    const src = await loadPdf(f);
    for (const p of await doc.copyPages(src, src.getPageIndices())) doc.addPage(p);
  }
  const out = outPath(list[0], 'объединено', 'pdf');
  await fsp.writeFile(out, await doc.save());
  return out;
}

async function splitPDF(src) {
  const { PDFDocument } = require('pdf-lib');
  const d = await loadPdf(src);
  const outs = [];
  for (const i of d.getPageIndices()) {
    const one = await PDFDocument.create();
    const [p] = await one.copyPages(d, [i]);
    one.addPage(p);
    const out = outPath(src, `стр. ${i + 1}`, 'pdf');
    await fsp.writeFile(out, await one.save());
    outs.push(out);
  }
  return outs;
}

async function rotatePDF(src) {
  const { degrees } = require('pdf-lib');
  const d = await loadPdf(src);
  for (const p of d.getPages()) p.setRotation(degrees((p.getRotation().angle + 90) % 360));
  const out = outPath(src, 'повернуто', 'pdf');
  await fsp.writeFile(out, await d.save());
  return out;
}

async function compressPDF(src) {
  const gs = await findExe(['gswin64c', 'gswin32c', 'gs']);
  if (!gs) throw new Error('Для сжатия PDF нужен бесплатный Ghostscript (ghostscript.com).');
  const out = outPath(src, 'сжато', 'pdf');
  try {
    await run(gs, ['-sDEVICE=pdfwrite', '-dPDFSETTINGS=/ebook', '-dNOPAUSE', '-dQUIET', '-dBATCH', `-sOutputFile=${out}`, src]);
  } catch (e) { fs.rmSync(out, { force: true }); throw e; }
  return out;
}

async function passwordPDF(src, pw) {
  const q = await findExe(['qpdf']);
  if (!q) throw new Error('Для пароля на PDF нужна бесплатная программа qpdf (qpdf.sourceforge.io).');
  const out = outPath(src, 'с паролем', 'pdf');
  try {
    await run(q, ['--encrypt', pw, pw, '256', '--', src, out]);
  } catch (e) { fs.rmSync(out, { force: true }); throw e; }
  return out;
}

// ---------- документы ----------
const toTarget = (f, target) => C.convertFile(f, target, { keepOriginal: true });

async function mergeDocsToPdf(files) {
  const pdfs = [];
  const temp = [];
  for (const f of sorted(files)) {
    if (extOf(f) === 'pdf') { pdfs.push(f); continue; }
    const p = await toTarget(f, 'pdf');
    pdfs.push(p);
    temp.push(p);
  }
  try { return await mergePDF(pdfs); } finally { temp.forEach((t) => fs.rmSync(t, { force: true })); }
}

// ---------- время для обрезки ----------
function parseTime(text) {
  const parts = String(text).trim().replace(',', '.').split(':').map((p) => (p === '' ? NaN : Number(p)));
  if (!parts.length || parts.some((n) => Number.isNaN(n))) return null;
  return parts.reduce((a, n) => a * 60 + n, 0);
}
function formatTime(t) {
  const total = Math.round(t);
  const h = Math.floor(total / 3600), m = Math.floor((total % 3600) / 60), s = total % 60;
  const two = (n) => String(n).padStart(2, '0');
  return h > 0 ? `${h}:${two(m)}:${two(s)}` : `${m}:${two(s)}`;
}

async function askRange(ui, duration) {
  let message = 'Время в секундах или мм:сс, например 0:15 и 1:30. Пустой конец значит «до конца».';
  let startText = '0:00';
  let endText = duration ? formatTime(duration) : '';
  for (;;) {
    const r = await ui.ask({
      title: 'Обрезать', message,
      fields: [{ label: 'Начало:', value: startText }, { label: 'Конец:', value: endText }],
      buttons: ['Обрезать']
    });
    if (!r) return null;
    [startText, endText] = r.values;
    const s = startText.trim() === '' ? 0 : parseTime(startText);
    const e = endText.trim() === '' ? duration : parseTime(endText);
    if (s === null || s === undefined) { message = 'Не понял «Начало». Пример: 0:15'; continue; }
    if (e === null || e === undefined) { message = endText.trim() === '' ? 'Укажи «Конец», например 1:30' : 'Не понял «Конец». Пример: 1:30'; continue; }
    if (e <= s) { message = `Конец (${formatTime(e)}) должен быть позже начала (${formatTime(s)})`; continue; }
    return [s, e];
  }
}

// ---------- запуск выбранного инструмента ----------
async function runTool(id, files, ui) {
  const first = files[0];
  const kind = kindOf(extOf(first));
  const label = files.length > 1 ? `Файлов: ${files.length}` : path.basename(first);
  const each = async (fn) => { const outs = []; for (const f of files) outs.push(await fn(f)); return outs; };
  const job = (title, work) => ui.job(title, label, work);

  switch (`${kind}:${id}`) {
    case 'video:mute': return job('Убираю звук…', () => each(mute));
    case 'video:trim':
    case 'audio:trim': {
      const r = await askRange(ui, await C.probeDuration(first));
      if (!r) return;
      return job('Обрезаю…', () => each((f) => trim(f, r[0], r[1])));
    }
    case 'video:compress':
    case 'audio:compress':
    case 'image:compress': {
      const quick = kind === 'video' ? compressVideo : kind === 'audio' ? compressAudio : compressImage;
      const plan = await Shrink.askCompress(ui, kind, quick);
      if (!plan) return;
      return job(plan.title, () => each(plan.work));
    }
    case 'video:resize':
    case 'image:resize': {
      const spec = await R.askSpec(ui, kind === 'video');
      if (!spec) return;
      return job('Меняю размер…', () => each((f) => R.resize(f, spec)));
    }
    case 'image:ai': {
      const factor = await R.askAIFactor(ui, false);
      if (!factor) return;
      return job('ИИ увеличивает фото…', () => each((f) => R.aiImage(f, factor)));
    }
    case 'video:ai': {
      const factor = await R.askAIFactor(ui, true);
      if (!factor || !(await R.confirmVideoAI(ui, first, factor))) return;
      return job('ИИ увеличивает видео… (это долго)', () => each((f) => R.aiVideo(f, factor)));
    }
    case 'video:fx':
    case 'audio:fx': {
      const fx = await AFX.askEffect(ui);
      if (!fx) return;
      return job(`${fx.title}…`, () => each((f) => AFX.apply(f, fx)));
    }
    case 'video:subs':
    case 'audio:subs': {
      const o = await S.askSpeech(ui);
      if (!o) return;
      return job('Распознаю речь…', () => each((f) => S.transcribe(f, { ...o, ui })));
    }
    case 'image:bgremove': return job('Убираю фон…', () => each((f) => BG.removeBackground(f)));
    case 'video:merge':
    case 'audio:merge': return job('Склеиваю…', async () => [await mergeMedia(files, kind)]);
    case 'video:frames': {
      const r = await ui.ask({ title: 'Кадры из видео', message: 'Сохранять кадр каждые сколько секунд?', fields: [{ label: '', value: '5' }], buttons: ['OK'] });
      const n = r && Number(String(r.values[0]).replace(',', '.'));
      if (!n || n <= 0) return;
      return job('Достаю кадры…', () => each((f) => frames(f, n)));
    }
    case 'image:rotate': return job('Поворачиваю…', () => each(rotateImage));
    case 'image:strip': return job('Убираю метаданные…', () => each(stripMeta));
    case 'image:topdf': return job('Собираю PDF…', async () => [await imagesToPdf(files)]);
    case 'image:ocr': return job('Распознаю текст…', () => each((f) => ocr(f, ui)));
    case 'image:watermark': {
      const r = await ui.ask({ title: 'Водяной знак', message: 'Текст в правом нижнем углу', fields: [{ label: '', value: '© ' }], buttons: ['OK'] });
      const t = r && r.values[0].trim();
      if (!t) return;
      return job('Ставлю водяной знак…', () => each((f) => watermark(f, t)));
    }
    case 'pdf:merge': return job('Объединяю PDF…', async () => [await mergePDF(files)]);
    case 'pdf:split': return job('Разделяю PDF…', () => splitPDF(first));
    case 'pdf:rotate': return job('Поворачиваю PDF…', () => each(rotatePDF));
    case 'pdf:compress': return job('Сжимаю PDF…', () => each(compressPDF));
    case 'pdf:password': {
      const r = await ui.ask({ title: 'Пароль для PDF', message: 'Без пароля файл не откроется', fields: [{ label: '', value: '', secure: true }], buttons: ['OK'] });
      const pw = r && r.values[0];
      if (!pw) return;
      return job('Защищаю PDF…', () => each((f) => passwordPDF(f, pw)));
    }
    default:
      if (id === 'topdf') return job('Делаю PDF…', () => each((f) => toTarget(f, 'pdf')));
      if (id === 'totxt') return job('Достаю текст…', () => each((f) => toTarget(f, 'txt')));
      if (id === 'mergepdf') return job('Склеиваю в PDF…', async () => [await mergeDocsToPdf(files)]);
      ui.info('Недоступно', 'Для этого файла такого инструмента нет');
  }
}

module.exports = { items, runTool, parseTime, formatTime, mergePDF, splitPDF, rotatePDF, trim, mergeMedia, frames, watermark, halfImage, rotateImage, compressImage, stripMeta, imagesToPdf, ocr, mute };
