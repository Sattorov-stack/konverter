'use strict';
// Изменение размера (×2, ×4, ×8, ×½, свой размер) и ИИ-увеличение (Real-ESRGAN)
const fs = require('fs');
const fsp = fs.promises;
const os = require('os');
const path = require('path');
const { run, uniqueOut } = require('./util');
const { kindOf, norm } = require('./formats');
const C = require('./convert');
const prefs = require('./prefs');

const MAX_IMG = 16383;
const MAX_VIDEO = 8192;
const extOf = (f) => norm(path.extname(f).slice(1));
const baseOf = (f) => path.basename(f, path.extname(f));
const outPath = (src, suffix, ext) => uniqueOut(C.outputDir(src), `${baseOf(src)} (${suffix})`, ext);
const num = (v) => (v === Math.round(v) ? String(v) : String(+v.toFixed(3)));

function parseSpec(raw) {
  const t = String(raw).toLowerCase().replace(/,/g, '.').replace(/\s+/g, '').replace(/×/g, 'x').replace(/х/g, 'x').replace(/px|пикс/g, '');
  let m;
  if ((m = t.match(/^(\d+(?:\.\d+)?)%$/)) && +m[1] > 0) return { mode: 'factor', value: +m[1] / 100, label: `${Math.round(+m[1])}%` };
  if ((m = t.match(/^x(\d+(?:\.\d+)?)$/) || t.match(/^(\d+(?:\.\d+)?)x$/)) && +m[1] > 0) return { mode: 'factor', value: +m[1], label: `×${num(+m[1])}` };
  if ((m = t.match(/^(\d+)x(\d+)$/)) && +m[1] > 0 && +m[2] > 0) return { mode: 'size', w: +m[1], h: +m[2], label: `${m[1]}x${m[2]}` };
  if ((m = t.match(/^(\d+(?:\.\d+)?)$/)) && +m[1] > 0) {
    const v = +m[1];
    return v < 50 ? { mode: 'factor', value: v, label: `×${num(v)}` } : { mode: 'width', w: Math.round(v), label: `${Math.round(v)} px` };
  }
  return null;
}

function targetSize(spec, w, h, even) {
  let tw, th;
  if (spec.mode === 'factor') { tw = w * spec.value; th = h * spec.value; }
  else if (spec.mode === 'width') { tw = spec.w; th = (h * spec.w) / Math.max(w, 1); }
  else { tw = spec.w; th = spec.h; }
  let iw = Math.max(2, Math.round(tw));
  let ih = Math.max(2, Math.round(th));
  if (even) { iw += iw % 2; ih += ih % 2; }
  return [iw, ih];
}

function checkSize(w, h, video) {
  const limit = video ? MAX_VIDEO : MAX_IMG;
  if (Math.max(w, h) > limit) throw new Error(`Получится ${w}×${h} px. Это слишком много: максимум ${limit} px по большей стороне.`);
}

const FORMATS = { jpg: 'jpeg', png: 'png', webp: 'webp', avif: 'avif', tiff: 'tiff' };

async function resizeImage(src, spec) {
  const sharp = require('sharp');
  const { data, info } = await (await C.openImage(src)).png().toBuffer({ resolveWithObject: true });
  const [tw, th] = targetSize(spec, info.width, info.height, false);
  checkSize(tw, th, false);
  const ext = extOf(src);
  const outExt = FORMATS[ext] ? ext : 'png';
  let img = sharp(data).resize(tw, th, { fit: 'fill', kernel: 'lanczos3' });
  if (outExt === 'jpg') img = img.flatten({ background: '#ffffff' });
  const out = outPath(src, spec.label, outExt);
  await img.toFormat(FORMATS[outExt], outExt === 'png' ? {} : { quality: prefs.get('imageQuality') }).toFile(out);
  return out;
}

function videoCodec(w, h) {
  if (w <= 4096 && h <= 4096 && w * h <= 8912896) return ['-c:v', 'libx264', '-preset', 'fast', '-crf', '18', '-pix_fmt', 'yuv420p'];
  return ['-c:v', 'libx265', '-preset', 'fast', '-crf', '20', '-tag:v', 'hvc1', '-pix_fmt', 'yuv420p'];
}

async function encodeVideo(src, vf, w, h, label) {
  const ext = extOf(src);
  const outExt = ['mp4', 'mov', 'mkv'].includes(ext) ? ext : 'mp4';
  const out = outPath(src, label, outExt);
  try {
    await run(C.requireFFmpeg(), ['-y', '-nostdin', '-hide_banner', '-i', src, ...vf, ...videoCodec(w, h), '-c:a', 'aac', '-b:a', '192k',
      ...(outExt === 'mp4' ? ['-movflags', '+faststart'] : []), out]);
  } catch (e) {
    fs.rmSync(out, { force: true });
    if (/libx265|Unknown encoder/.test(e.message)) throw new Error('В этом ffmpeg нет кодека HEVC, а для такого размера он нужен. Выбери размер до 4096 px.');
    throw e;
  }
  return out;
}

async function resizeVideo(src, spec) {
  const info = await C.probeInfo(src);
  if (!info.width) throw new Error('Не удалось узнать размер видео');
  const [tw, th] = targetSize(spec, info.width, info.height, true);
  checkSize(tw, th, true);
  return encodeVideo(src, ['-vf', `scale=${tw}:${th}:flags=lanczos`], tw, th, spec.label);
}

const resize = (src, spec) => (kindOf(extOf(src)) === 'video' ? resizeVideo(src, spec) : resizeImage(src, spec));

const NO_AI = 'ИИ-модуль не найден. Переустанови приложение.';

function aiTool() {
  const dir = process.env.KONVERTER_REALESRGAN_DIR || path.join(__dirname, '..', 'assets', 'realesrgan');
  const bin = path.join(dir, process.platform === 'win32' ? 'realesrgan-ncnn-vulkan.exe' : 'realesrgan-ncnn-vulkan');
  return fs.existsSync(bin) ? { bin, models: path.join(dir, 'models') } : null;
}

const aiRun = (tool, input, output, format) =>
  run(tool.bin, ['-i', input, '-o', output, '-n', 'realesrgan-x4plus', '-s', '4', '-m', tool.models, '-f', format]);

async function aiImage(src, factor) {
  const tool = aiTool();
  if (!tool) throw new Error(NO_AI);
  const sharp = require('sharp');
  const tmp = await fsp.mkdtemp(path.join(os.tmpdir(), 'konv-ai-'));
  try {
    const input = path.join(tmp, 'in.png');
    const info = await (await C.openImage(src)).png().toFile(input);
    const finalW = info.width * factor, finalH = info.height * factor;
    checkSize(finalW, finalH, false);
    const passes = factor === 8 ? 2 : 1;
    const inter = Math.max(info.width, info.height) * (passes === 2 ? 16 : 4);
    if (inter > 24000) throw new Error(`Для ×${factor} промежуточный размер получится ${inter} px: это слишком много. Выбери ×4 или ×2.`);
    let current = path.join(tmp, 'p1.png');
    await aiRun(tool, input, current, 'png');
    if (passes === 2) { const p2 = path.join(tmp, 'p2.png'); await aiRun(tool, current, p2, 'png'); current = p2; }
    const ext = extOf(src);
    const outExt = FORMATS[ext] ? ext : 'png';
    let img = sharp(current, { limitInputPixels: false });
    if (factor !== (passes === 2 ? 16 : 4)) img = img.resize(finalW, finalH, { kernel: 'lanczos3' });
    if (outExt === 'jpg') img = img.flatten({ background: '#ffffff' });
    const out = outPath(src, `ИИ ×${factor}`, outExt);
    await img.toFormat(FORMATS[outExt], outExt === 'png' ? {} : { quality: prefs.get('imageQuality') }).toFile(out);
    return out;
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

async function aiVideo(src, factor) {
  const tool = aiTool();
  if (!tool) throw new Error(NO_AI);
  const info = await C.probeInfo(src);
  if (!info.width) throw new Error('Не удалось узнать размер видео');
  const fps = info.fps || 30;
  const tw = Math.ceil((info.width * factor) / 2) * 2, th = Math.ceil((info.height * factor) / 2) * 2;
  checkSize(tw, th, true);
  const tmp = await fsp.mkdtemp(path.join(os.tmpdir(), 'konv-aivideo-'));
  const frames = path.join(tmp, 'frames'), up = path.join(tmp, 'up');
  fs.mkdirSync(frames); fs.mkdirSync(up);
  const ff = C.requireFFmpeg();
  try {
    await run(ff, ['-y', '-nostdin', '-hide_banner', '-i', src, '-fps_mode', 'passthrough', '-q:v', '2', path.join(frames, '%08d.jpg')]);
    await aiRun(tool, frames, up, 'jpg');
    const ext = extOf(src);
    const outExt = ['mp4', 'mov', 'mkv'].includes(ext) ? ext : 'mp4';
    const out = outPath(src, `ИИ ×${factor}`, outExt);
    const args = ['-y', '-nostdin', '-hide_banner', '-framerate', fps.toFixed(3), '-i', path.join(up, '%08d.jpg'), '-i', src, '-map', '0:v', '-map', '1:a?'];
    if (factor !== 4) args.push('-vf', `scale=${tw}:${th}:flags=lanczos`);
    args.push(...videoCodec(tw, th), '-c:a', 'aac', '-b:a', '192k', '-shortest');
    if (outExt === 'mp4') args.push('-movflags', '+faststart');
    args.push(out);
    try { await run(ff, args); } catch (e) { fs.rmSync(out, { force: true }); throw e; }
    return out;
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

async function askSpec(ui, isVideo) {
  const hint = isVideo
    ? 'Видео меняет размер обычным сглаживанием: быстро, но новых деталей не появится.'
    : 'Фото меняет размер обычным сглаживанием: быстро, но новых деталей не появится. Для настоящего улучшения есть «ИИ-увеличение».';
  const r = await ui.ask({ title: 'Размер', message: hint, fields: [], vertical: true, buttons: ['×2', '×4', '×8', '×½', '×¼', 'Свой размер…'] });
  if (!r) return null;
  const preset = [[2, '×2'], [4, '×4'], [8, '×8'], [0.5, '×½'], [0.25, '×¼']][r.button];
  if (preset) return { mode: 'factor', value: preset[0], label: preset[1] };
  let message = 'Примеры: 3200 (ширина в пикселях), 3200x2400, 400%, ×4, 0.5. Число меньше 50 значит «во сколько раз».';
  let text = '';
  for (;;) {
    const c = await ui.ask({ title: 'Свой размер', message, fields: [{ label: '', value: text }], buttons: ['OK'] });
    if (!c) return null;
    text = c.values[0];
    const spec = parseSpec(text);
    if (spec) return spec;
    message = 'Не понял. Примеры: 3200, 3200x2400, 400%, ×4, 0.5';
  }
}

async function askAIFactor(ui, video) {
  let message = 'ИИ дорисовывает детали: лучше всего работает на фото и рисунках. На совсем маленьких снимках лица и текст могут получиться «придуманными».';
  const buttons = ['×2', '×4'];
  if (video) message += '\nВидео обрабатывается кадр за кадром: это долго и занимает много места на диске.';
  else { buttons.push('×8'); message += '\n×8 делается в два прохода и занимает заметно дольше.'; }
  const r = await ui.ask({ title: 'ИИ-увеличение', message, fields: [], vertical: true, buttons });
  return r ? [2, 4, 8][r.button] : null;
}

async function confirmVideoAI(ui, src, factor) {
  const info = await C.probeInfo(src);
  const fps = info.fps || 30;
  const frames = Math.max(1, Math.floor((info.duration || 0) * fps));
  const outMP = ((info.width || 1280) * 4 * (info.height || 720) * 4) / 1e6;
  const lo = Math.ceil((frames * outMP * 0.5) / 60), hi = Math.ceil((frames * outMP * 1.5) / 60);
  const gb = ((frames * outMP * 0.5) / 1000).toFixed(1);
  const r = await ui.ask({ title: `ИИ для видео ×${factor}`, fields: [], buttons: ['Начать'],
    message: `В видео около ${frames} кадров. ИИ обрабатывает каждый отдельно: примерно ${lo}–${hi} мин. и до ${gb} ГБ временного места на диске. Компьютер в это время будет заметно нагружен. Продолжить?` });
  return !!r;
}

module.exports = { parseSpec, targetSize, resize, resizeImage, resizeVideo, aiImage, aiVideo, aiTool, askSpec, askAIFactor, confirmVideoAI };
