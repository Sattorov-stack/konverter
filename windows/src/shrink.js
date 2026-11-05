'use strict';
// Сжатие до нужного размера (в МБ) и готовые профили для Telegram, WhatsApp, сайта, почты
const fs = require('fs');
const path = require('path');
const { run, uniqueOut } = require('./util');
const C = require('./convert');

const MB = 1024 * 1024;
const baseOf = (f) => path.basename(f, path.extname(f));
const outPath = (src, suffix, ext) => uniqueOut(C.outputDir(src), `${baseOf(src)} (${suffix})`, ext);

async function ff(args, to) {
  try {
    await run(C.requireFFmpeg(), ['-y', '-nostdin', '-hide_banner', ...args, to]);
  } catch (e) {
    fs.rmSync(to, { force: true });
    throw e;
  }
  return to;
}

const fmtDur = (s) => { const m = Math.floor(s / 60); return m ? `${m} мин ${Math.round(s % 60)} с` : `${Math.round(s)} с`; };

async function shrinkVideo(src, mb) {
  const info = await C.probeInfo(src);
  if (!info.duration) throw new Error('Не удалось узнать длительность видео');
  const budget = mb * MB * 8 * 0.92;
  let audio = info.hasAudio ? 128000 : 0;
  let vbr = budget / info.duration - audio;
  if (vbr < 150000 && audio) { audio = 64000; vbr = budget / info.duration - audio; }
  if (vbr < 80000) throw new Error(`Для видео длиной ${fmtDur(info.duration)} ${mb} МБ слишком мало. Выбери размер побольше.`);
  const out = outPath(src, `до ${mb} МБ`, 'mp4');
  for (let attempt = 0; attempt < 3; attempt++) {
    const rate = Math.floor(vbr * [1, 0.85, 0.7][attempt]);
    const h = rate < 350000 ? 360 : rate < 900000 ? 480 : rate < 2500000 ? 720 : 0;
    const vf = h && info.height > h ? ['-vf', `scale=-2:${h}`] : [];
    await ff(['-i', src, ...vf, '-c:v', 'libx264', '-preset', 'medium', '-b:v', String(rate), '-maxrate', String(Math.floor(rate * 1.2)),
      '-bufsize', String(rate * 2), '-pix_fmt', 'yuv420p', ...(info.hasAudio ? ['-c:a', 'aac', '-b:a', String(audio)] : ['-an']),
      '-movflags', '+faststart'], out);
    if (fs.statSync(out).size <= mb * MB) return out;
  }
  fs.rmSync(out, { force: true });
  throw new Error(`Не удалось уложиться в ${mb} МБ. Выбери размер побольше.`);
}

async function encodeVideo(src, { h, crf, ab, suffix }) {
  return ff(['-i', src, '-vf', `scale=-2:'min(${h},ih)'`, '-c:v', 'libx264', '-preset', 'medium', '-crf', String(crf),
    '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', `${ab}k`, '-movflags', '+faststart'], outPath(src, suffix, 'mp4'));
}

async function shrinkAudio(src, mb) {
  const info = await C.probeInfo(src);
  if (!info.duration) throw new Error('Не удалось узнать длительность звука');
  let kbps = Math.floor((mb * MB * 8 * 0.95) / info.duration / 1000);
  if (kbps < 24) throw new Error(`Для записи длиной ${fmtDur(info.duration)} ${mb} МБ слишком мало.`);
  kbps = Math.min(kbps, 320);
  const out = outPath(src, `до ${mb} МБ`, 'mp3');
  for (let attempt = 0; attempt < 3; attempt++) {
    await ff(['-i', src, '-vn', '-c:a', 'libmp3lame', '-b:a', `${Math.max(24, Math.floor(kbps * [1, 0.88, 0.75][attempt]))}k`], out);
    if (fs.statSync(out).size <= mb * MB) return out;
  }
  fs.rmSync(out, { force: true });
  throw new Error(`Не удалось уложиться в ${mb} МБ. Выбери размер побольше.`);
}

async function encodeAudio(src, { fmt, ab, mono, suffix }) {
  const codec = fmt === 'm4a' ? ['-c:a', 'aac'] : ['-c:a', 'libmp3lame'];
  return ff(['-i', src, '-vn', ...codec, '-b:a', `${ab}k`, ...(mono ? ['-ac', '1'] : [])], outPath(src, suffix, fmt));
}

const FORMATS = { jpg: 'jpeg', png: 'png', webp: 'webp' };

async function encodeImage(src, { fmt, max, q, suffix }) {
  let img = await C.openImage(src);
  if (max) img = img.resize({ width: max, height: max, fit: 'inside', withoutEnlargement: true });
  if (fmt === 'jpg') img = img.flatten({ background: '#ffffff' });
  const out = outPath(src, suffix, fmt);
  await img.toFormat(FORMATS[fmt], fmt === 'png' ? {} : { quality: q }).toFile(out);
  return out;
}

async function shrinkImage(src, mb) {
  const sharp = require('sharp');
  const { data, info } = await (await C.openImage(src)).png().toBuffer({ resolveWithObject: true });
  const limit = mb * MB;
  const out = outPath(src, `до ${mb} МБ`, 'jpg');
  for (const scale of [1, 0.85, 0.7, 0.55, 0.4, 0.3]) {
    for (const q of [90, 82, 74, 66, 58, 50, 42]) {
      const buf = await sharp(data).resize({ width: Math.max(16, Math.round(info.width * scale)) })
        .flatten({ background: '#ffffff' }).jpeg({ quality: q }).toBuffer();
      if (buf.length <= limit) { fs.writeFileSync(out, buf); return out; }
    }
  }
  throw new Error(`Не удалось уложиться в ${mb} МБ. Выбери размер побольше.`);
}

const PROFILES = {
  image: [
    { title: 'Telegram (JPG, до 2560 px)', run: (f) => encodeImage(f, { fmt: 'jpg', max: 2560, q: 85, suffix: 'Telegram' }) },
    { title: 'Сайт (WEBP, до 1920 px)', run: (f) => encodeImage(f, { fmt: 'webp', max: 1920, q: 80, suffix: 'для сайта' }) },
    { title: 'Почта (JPG, до 1 МБ)', run: (f) => shrinkImage(f, 1) },
    { title: 'Instagram (JPG, до 1350 px)', run: (f) => encodeImage(f, { fmt: 'jpg', max: 1350, q: 90, suffix: 'Instagram' }) },
    { title: 'Аватар (PNG, 512 px)', run: (f) => encodeImage(f, { fmt: 'png', max: 512, suffix: 'аватар' }) }
  ],
  video: [
    { title: 'Telegram (720p)', run: (f) => encodeVideo(f, { h: 720, crf: 26, ab: 128, suffix: 'Telegram' }) },
    { title: 'WhatsApp (до 16 МБ)', run: (f) => shrinkVideo(f, 16) },
    { title: 'Instagram (1080p)', run: (f) => encodeVideo(f, { h: 1080, crf: 23, ab: 160, suffix: 'Instagram' }) },
    { title: 'Почта (до 25 МБ)', run: (f) => shrinkVideo(f, 25) },
    { title: 'Сайт (720p, быстрый старт)', run: (f) => encodeVideo(f, { h: 720, crf: 27, ab: 96, suffix: 'для сайта' }) }
  ],
  audio: [
    { title: 'Голосовое (M4A, моно, 64 кбит/с)', run: (f) => encodeAudio(f, { fmt: 'm4a', ab: 64, mono: true, suffix: 'голосовое' }) },
    { title: 'Подкаст (MP3, моно, 96 кбит/с)', run: (f) => encodeAudio(f, { fmt: 'mp3', ab: 96, mono: true, suffix: 'подкаст' }) },
    { title: 'Музыка (MP3, 320 кбит/с)', run: (f) => encodeAudio(f, { fmt: 'mp3', ab: 320, suffix: 'музыка' }) }
  ]
};

const toSize = (kind, f, mb) => (kind === 'video' ? shrinkVideo(f, mb) : kind === 'audio' ? shrinkAudio(f, mb) : shrinkImage(f, mb));

// Возвращает { title, work(file) } или null, если нажали «Отмена»
async function askCompress(ui, kind, quick) {
  const r = await ui.ask({ title: 'Сжать', message: 'Как сжимать?', fields: [], vertical: true,
    buttons: ['Для мессенджера или сайта…', 'До нужного размера…', 'Просто сжать (среднее качество)'] });
  if (!r) return null;
  if (r.button === 2) return { title: 'Сжимаю…', work: quick };
  if (r.button === 0) {
    const list = PROFILES[kind];
    const p = await ui.ask({ title: 'Для чего?', message: 'Выбери готовый вариант', fields: [], vertical: true, buttons: list.map((x) => x.title) });
    if (!p) return null;
    return { title: `${list[p.button].title}…`, work: list[p.button].run };
  }
  const sizes = [8, 16, 25, 50];
  const s = await ui.ask({ title: 'До какого размера?', message: 'Файл будет сжат так, чтобы уложиться в этот размер.', fields: [], vertical: true,
    buttons: [...sizes.map((n) => `До ${n} МБ`), 'Свой размер…'] });
  if (!s) return null;
  let mb = sizes[s.button];
  if (mb === undefined) {
    const c = await ui.ask({ title: 'Свой размер', message: 'Сколько мегабайт?', fields: [{ label: '', value: '10' }], buttons: ['OK'] });
    mb = c && Number(String(c.values[0]).replace(',', '.'));
    if (!mb || mb <= 0) return null;
  }
  return { title: `Сжимаю до ${mb} МБ…`, work: (f) => toSize(kind, f, mb) };
}

module.exports = { shrinkVideo, shrinkAudio, shrinkImage, encodeVideo, encodeAudio, encodeImage, PROFILES, askCompress, toSize };
