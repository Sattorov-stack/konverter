'use strict';
// Движок конвертации: фото (sharp), музыка и видео (ffmpeg), документы (LibreOffice или встроенный)
const fs = require('fs');
const fsp = fs.promises;
const os = require('os');
const path = require('path');
const { run, uniqueOut, findExe } = require('./util');
const { norm, kindOf } = require('./formats');
const prefs = require('./prefs');

// Электрон подставляет сюда то, что умеет только он (PDF из HTML, корзина)
const hooks = { htmlToPdf: null, trash: null, notice: null };
const setHooks = (h) => Object.assign(hooks, h);

const MSG_NO_FFMPEG = 'Не найден ffmpeg. Переустанови приложение.';
const MSG_NO_OFFICE = 'Для этого файла нужен LibreOffice. Он лежит в папке setup рядом с приложением: запусти INSTALL.bat или установи LibreOffice вручную (libreoffice.org).';

// ---------- поиск программ ----------
function ffmpegPath() {
  try {
    const p = require('ffmpeg-static');
    if (p && fs.existsSync(p)) return p;
  } catch (e) { /* нет */ }
  return null;
}
function requireFFmpeg() {
  const p = ffmpegPath();
  if (!p) throw new Error(MSG_NO_FFMPEG);
  return p;
}
function sofficePath() {
  const local = [
    path.join(__dirname, '..', 'tools', 'LibreOffice', 'program', 'soffice.exe'),
    path.join(__dirname, '..', '..', 'tools', 'LibreOffice', 'program', 'soffice.exe')
  ];
  for (const p of local) if (fs.existsSync(p)) return p;
  const dirs = [process.env['ProgramFiles'], process.env['ProgramFiles(x86)'], process.env['LOCALAPPDATA']].filter(Boolean);
  for (const d of dirs) {
    const p = path.join(d, 'LibreOffice', 'program', 'soffice.exe');
    if (fs.existsSync(p)) return p;
  }
  return null;
}

// ---------- куда сохранять ----------
function outputDir(src) {
  const parent = path.dirname(src);
  const mode = prefs.get('saveMode');
  let dir = parent;
  if (mode === 1) dir = path.join(parent, 'Converted');
  else if (mode === 2 && prefs.get('outputFolder')) dir = prefs.get('outputFolder');
  if (dir !== parent) fs.mkdirSync(dir, { recursive: true });
  return dir;
}

// ---------- фото ----------
async function loadImageBuffer(src, ext) {
  if (ext === 'heic') {
    const convert = require('heic-convert');
    const out = await convert({ buffer: await fsp.readFile(src), format: 'PNG' });
    return Buffer.from(out);
  }
  if (ext === 'bmp') {
    const tmp = path.join(os.tmpdir(), `konv-${process.pid}-${Date.now()}.png`);
    await run(requireFFmpeg(), ['-y', '-nostdin', '-hide_banner', '-i', src, tmp]);
    try { return await fsp.readFile(tmp); } finally { fs.rmSync(tmp, { force: true }); }
  }
  return null; // sharp сам прочитает файл
}

async function openImage(src) {
  const sharp = require('sharp');
  const ext = norm(path.extname(src).slice(1));
  const buf = await loadImageBuffer(src, ext);
  return sharp(buf || src, { failOn: 'none' }).rotate(); // rotate() учитывает поворот из EXIF
}

async function imageToPdf(jpegBuffers, out) {
  const { PDFDocument } = require('pdf-lib');
  const doc = await PDFDocument.create();
  for (const b of jpegBuffers) {
    const jpg = await doc.embedJpg(b);
    const page = doc.addPage([jpg.width, jpg.height]);
    page.drawImage(jpg, { x: 0, y: 0, width: jpg.width, height: jpg.height });
  }
  await fsp.writeFile(out, await doc.save());
}

async function image(src, target, out) {
  let img = await openImage(src);
  const maxSide = prefs.get('imageMaxSide');
  if (maxSide > 0) img = img.resize({ width: maxSide, height: maxSide, fit: 'inside', withoutEnlargement: true });
  const q = prefs.get('imageQuality');
  switch (target) {
    case 'jpg': await img.flatten({ background: '#ffffff' }).jpeg({ quality: q }).toFile(out); break;
    case 'png': await img.png().toFile(out); break;
    case 'webp': await img.webp({ quality: q }).toFile(out); break;
    case 'avif': await img.avif({ quality: Math.round(q * 0.7), effort: 4 }).toFile(out); break;
    case 'tiff': await img.tiff({ quality: q }).toFile(out); break;
    case 'gif': await img.gif().toFile(out); break;
    case 'bmp': {
      const tmp = path.join(os.tmpdir(), `konv-${process.pid}-${Date.now()}.png`);
      await img.png().toFile(tmp);
      try { await run(requireFFmpeg(), ['-y', '-nostdin', '-hide_banner', '-i', tmp, out]); } finally { fs.rmSync(tmp, { force: true }); }
      break;
    }
    case 'pdf': await imageToPdf([await img.flatten({ background: '#ffffff' }).jpeg({ quality: q }).toBuffer()], out); break;
    default: throw new Error('Такой формат для фото не поддерживается');
  }
}

// ---------- музыка и видео ----------
function audioArgs(t) {
  const b = prefs.get('audioBitrate') + 'k';
  switch (t) {
    case 'mp3': return ['-c:a', 'libmp3lame', '-b:a', b];
    case 'm4a': return ['-c:a', 'aac', '-b:a', b];
    case 'wav': return ['-c:a', 'pcm_s16le'];
    case 'flac': return ['-c:a', 'flac'];
    case 'ogg': return ['-c:a', 'libvorbis', '-b:a', b];
    case 'opus': return ['-c:a', 'libopus', '-b:a', b];
    case 'aiff': return ['-c:a', 'pcm_s16be'];
    default: return null;
  }
}

function videoArgs(t) {
  const q = prefs.get('videoQuality');
  const crf = q === 0 ? '18' : q === 2 ? '28' : '22';
  const vp9 = q === 0 ? '24' : q === 2 ? '38' : '31';
  const h = prefs.get('videoMaxHeight');
  const scale = h > 0 ? ['-vf', `scale=-2:'min(${h},ih)'`] : [];
  const h264 = [...scale, '-c:v', 'libx264', '-preset', 'medium', '-crf', crf, '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '192k'];
  switch (t) {
    case 'mp4': return [...h264, '-movflags', '+faststart'];
    case 'mov': case 'mkv': return h264;
    case 'webm': return [...scale, '-c:v', 'libvpx-vp9', '-crf', vp9, '-b:v', '0', '-c:a', 'libopus'];
    case 'avi': return [...scale, '-c:v', 'mpeg4', '-q:v', '4', '-c:a', 'libmp3lame'];
    case 'wmv': return [...scale, '-c:v', 'wmv2', '-b:v', '4M', '-c:a', 'wmav2', '-b:a', '192k'];
    case 'gif': return ['-an', '-vf', 'fps=12,scale=480:-1:flags=lanczos', '-loop', '0'];
    default: return null;
  }
}

async function media(src, target, out, onProgress) {
  const ff = requireFFmpeg();
  const a = audioArgs(target);
  const codec = a ? ['-vn', ...a] : (videoArgs(target) || []);
  let dur = 0;
  await run(ff, ['-y', '-nostdin', '-hide_banner', '-i', src, ...codec, out], (s) => {
    const d = s.match(/Duration: (\d+):(\d+):([\d.]+)/);
    if (d) dur = +d[1] * 3600 + +d[2] * 60 + parseFloat(d[3]);
    const all = [...s.matchAll(/time=(\d+):(\d+):([\d.]+)/g)];
    if (all.length && dur && onProgress) {
      const t = all[all.length - 1];
      onProgress(Math.min(0.99, (+t[1] * 3600 + +t[2] * 60 + parseFloat(t[3])) / dur));
    }
  });
}

async function probeText(file) {
  const ff = ffmpegPath();
  if (!ff) return '';
  let text = '';
  // без выходного файла ffmpeg завершается с ошибкой, но всё нужное он уже вывел
  try { await run(ff, ['-hide_banner', '-i', file], (s) => { text += s; }); } catch (e) { /* так и должно быть */ }
  return text;
}

// длительность, размер кадра, частота кадров, есть ли звук
async function probeInfo(file) {
  const t = await probeText(file);
  const d = t.match(/Duration: (\d+):(\d+):([\d.]+)/);
  const v = t.split('\n').find((l) => l.includes('Video:')) || '';
  const size = v.match(/[ ,](\d{2,5})x(\d{2,5})[ ,\[]/);
  const fps = v.match(/(\d+(?:\.\d+)?) fps/);
  return {
    duration: d ? +d[1] * 3600 + +d[2] * 60 + parseFloat(d[3]) : null,
    width: size ? +size[1] : null,
    height: size ? +size[2] : null,
    fps: fps ? parseFloat(fps[1]) : null,
    hasAudio: /Audio:/.test(t),
    hasVideo: !!v
  };
}

async function probeDuration(file) {
  const ff = ffmpegPath();
  if (!ff) return null;
  let text = '';
  // без выходного файла ffmpeg завершается с ошибкой, но всё нужное он уже вывел: ошибку игнорируем
  try { await run(ff, ['-hide_banner', '-i', file], (s) => { text += s; }); } catch (e) { /* так и должно быть */ }
  const d = text.match(/Duration: (\d+):(\d+):([\d.]+)/);
  return d ? +d[1] * 3600 + +d[2] * 60 + parseFloat(d[3]) : null;
}

// ---------- документы ----------
const escapeHtml = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const wrapHtml = (body) => `<!doctype html><html><head><meta charset="utf-8"><style>
@page { size: A4; margin: 20mm 18mm; }
html,body{margin:0;padding:0}
body{font-family:"Calibri","Segoe UI",Arial,sans-serif;font-size:11pt;line-height:1.35;color:#000}
p{margin:0 0 8pt}
h1{font-size:18pt;margin:12pt 0 8pt} h2{font-size:15pt;margin:10pt 0 6pt} h3{font-size:12.5pt;margin:8pt 0 4pt}
img{max-width:100%;height:auto}
table{border-collapse:collapse;width:100%;margin:6pt 0}
td,th{border:1px solid #777;padding:4px 6px;vertical-align:top}
th{background:#f2f2f2;font-weight:600}
ul,ol{margin:0 0 8pt 18pt;padding:0}
pre{white-space:pre-wrap;font-family:Consolas,monospace;font-size:10.5pt}
</style></head><body>${body}</body></html>`;
const htmlToText = (h) => h.replace(/<style[\s\S]*?<\/style>/gi, '').replace(/<br\s*\/?>/gi, '\n')
  .replace(/<\/(p|div|h\d|li|tr)>/gi, '\n').replace(/<[^>]+>/g, '')
  .replace(/&nbsp;/g, ' ').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&').replace(/\n{3,}/g, '\n\n').trim();

// Без LibreOffice умеем только самое простое
function nativeSupports(kind, ext, target) {
  if (kind === 'pdf') return target === 'txt';
  if (kind !== 'doc') return false;
  if (ext === 'docx') return ['pdf', 'html', 'txt'].includes(target);
  if (ext === 'txt') return ['pdf', 'html'].includes(target);
  if (ext === 'html') return ['pdf', 'txt'].includes(target);
  return false;
}

async function loadHtml(src, ext) {
  if (ext === 'docx') {
    const mammoth = require('mammoth');
    return (await mammoth.convertToHtml({ path: src })).value;
  }
  if (ext === 'txt') return '<pre style="white-space:pre-wrap;font-family:inherit">' + escapeHtml(await fsp.readFile(src, 'utf8')) + '</pre>';
  return fsp.readFile(src, 'utf8');
}

async function nativeDoc(src, kind, ext, target, out) {
  if (kind === 'pdf') {
    const pdfParse = require('pdf-parse/lib/pdf-parse.js');
    const data = await pdfParse(await fsp.readFile(src));
    if (!data.text.trim()) throw new Error('В этом PDF нет текста (возможно, это скан)');
    await fsp.writeFile(out, data.text, 'utf8');
    return;
  }
  if (target === 'txt' && ext === 'docx') {
    const mammoth = require('mammoth');
    await fsp.writeFile(out, (await mammoth.extractRawText({ path: src })).value, 'utf8');
    return;
  }
  const body = await loadHtml(src, ext);
  if (target === 'txt') { await fsp.writeFile(out, htmlToText(body), 'utf8'); return; }
  const html = wrapHtml(body);
  if (target === 'html') { await fsp.writeFile(out, html, 'utf8'); return; }
  if (target === 'pdf') {
    if (!hooks.htmlToPdf) throw new Error('Сохранение в PDF сейчас недоступно');
    if (hooks.notice) {
      hooks.notice('PDF без точной вёрстки', 'LibreOffice не найден, документ печатается упрощённо. Запусти INSTALL.bat рядом с приложением — вёрстка сохранится как в оригинале.');
    }
    await fsp.writeFile(out, await hooks.htmlToPdf(html));
    return;
  }
  throw new Error(MSG_NO_OFFICE);
}

async function officeConvert(office, src, kind, target, out) {
  const tmp = await fsp.mkdtemp(path.join(os.tmpdir(), 'konv-'));
  try {
    let filter = target;
    if (target === 'txt') filter = 'txt:Text (encoded):UTF8';
    if (target === 'docx' && kind === 'pdf') filter = 'docx:MS Word 2007 XML';
    const profile = 'file:///' + path.join(tmp, 'profile').replace(/\\/g, '/');
    const args = ['-env:UserInstallation=' + profile, '--headless'];
    if (kind === 'pdf') args.push('--infilter=writer_pdf_import');
    args.push('--convert-to', filter, '--outdir', tmp, src);
    await run(office, args);
    const made = fs.readdirSync(tmp).find((f) => f.toLowerCase().endsWith('.' + target));
    if (!made) throw new Error('Не удалось конвертировать этот файл');
    fs.copyFileSync(path.join(tmp, made), out);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

async function document(src, kind, ext, target, out) {
  const office = sofficePath();
  if (office) return officeConvert(office, src, kind, target, out);
  if (nativeSupports(kind, ext, target)) return nativeDoc(src, kind, ext, target, out);
  throw new Error(MSG_NO_OFFICE);
}

// PDF в картинку: нужен Ghostscript (необязательно)
async function pdfToImage(src, target, out) {
  const gs = await findExe(['gswin64c', 'gswin32c', 'gs']);
  if (!gs) throw new Error('Для PDF в картинку нужен бесплатный Ghostscript (ghostscript.com).');
  await run(gs, ['-dBATCH', '-dNOPAUSE', '-dQUIET', '-dFirstPage=1', '-dLastPage=1', '-r150',
    target === 'jpg' ? '-sDEVICE=jpeg' : '-sDEVICE=png16m', `-sOutputFile=${out}`, src]);
}

// ---------- главный вход ----------
async function convertFile(src, target, opts = {}) {
  const ext = norm(path.extname(src).slice(1));
  const kind = kindOf(ext);
  if (!kind) throw new Error('Этот формат не поддерживается');
  const base = path.basename(src, path.extname(src));
  const dir = opts.outDir || outputDir(src);
  if (opts.outDir) fs.mkdirSync(dir, { recursive: true });
  const out = uniqueOut(dir, base, target);
  try {
    if (kind === 'image') await image(src, target, out);
    else if (kind === 'pdf' && (target === 'jpg' || target === 'png')) await pdfToImage(src, target, out);
    else if (kind === 'audio' || kind === 'video') await media(src, target, out, opts.onProgress);
    else await document(src, kind, ext, target, out);
  } catch (e) {
    fs.rmSync(out, { force: true });
    throw e;
  }
  if (!opts.keepOriginal && prefs.get('trashOriginal') && hooks.trash && out !== src) {
    try { await hooks.trash(src); } catch (e) { /* не страшно */ }
  }
  return out;
}

module.exports = {
  convertFile, setHooks, outputDir, ffmpegPath, requireFFmpeg, sofficePath, probeDuration, probeInfo, probeText,
  openImage, imageToPdf, escapeHtml, MSG_NO_OFFICE
};
