'use strict';
// Эффекты для звука: громкость, шум, тишина, скорость (работает и для видео со звуком)
const fs = require('fs');
const path = require('path');
const { run, uniqueOut } = require('./util');
const { kindOf, norm } = require('./formats');
const C = require('./convert');

const extOf = (f) => norm(path.extname(f).slice(1));
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

const AUDIO_CODEC = {
  mp3: ['-c:a', 'libmp3lame', '-q:a', '2'], m4a: ['-c:a', 'aac', '-b:a', '256k'], aac: ['-c:a', 'aac', '-b:a', '256k'],
  wav: ['-c:a', 'pcm_s16le'], flac: ['-c:a', 'flac'], ogg: ['-c:a', 'libvorbis', '-q:a', '6'],
  opus: ['-c:a', 'libopus', '-b:a', '160k'], aiff: ['-c:a', 'pcm_s16be']
};

const EFFECTS = [
  { id: 'normalize', title: 'Выровнять громкость', suffix: 'громкость', af: 'loudnorm=I=-16:TP=-1.5:LRA=11' },
  { id: 'denoise', title: 'Убрать шум', suffix: 'без шума', af: 'afftdn=nf=-25' },
  { id: 'silence', title: 'Убрать тишину', suffix: 'без пауз',
    af: 'silenceremove=start_periods=1:start_threshold=-45dB:stop_periods=-1:stop_threshold=-45dB:stop_duration=0.6' },
  { id: 'fast15', title: 'Ускорить ×1.5', suffix: '×1.5', speed: 1.5 },
  { id: 'fast2', title: 'Ускорить ×2', suffix: '×2', speed: 2 },
  { id: 'slow75', title: 'Замедлить ×0.75', suffix: '×0.75', speed: 0.75 },
  { id: 'slow5', title: 'Замедлить ×0.5', suffix: '×0.5', speed: 0.5 }
];

async function apply(src, fx) {
  const ext = extOf(src);
  const info = await C.probeInfo(src);
  if (kindOf(ext) === 'audio' || !info.hasVideo) {
    if (!info.hasAudio) throw new Error('В этом файле нет звука');
    const outExt = AUDIO_CODEC[ext] ? ext : 'mp3';
    return ff(['-i', src, '-vn', '-af', fx.speed ? `atempo=${fx.speed}` : fx.af, ...AUDIO_CODEC[outExt]], outPath(src, fx.suffix, outExt));
  }
  const outExt = ['mp4', 'mov', 'mkv'].includes(ext) ? ext : 'mp4';
  if (fx.speed) {
    const s = fx.speed;
    const parts = info.hasAudio
      ? ['-filter_complex', `[0:v]setpts=PTS/${s}[v];[0:a]atempo=${s}[a]`, '-map', '[v]', '-map', '[a]', '-c:a', 'aac', '-b:a', '192k']
      : ['-filter_complex', `[0:v]setpts=PTS/${s}[v]`, '-map', '[v]', '-an'];
    return ff(['-i', src, ...parts, '-c:v', 'libx264', '-preset', 'medium', '-crf', '20', '-pix_fmt', 'yuv420p'], outPath(src, fx.suffix, outExt));
  }
  if (!info.hasAudio) throw new Error('В этом видео нет звука');
  return ff(['-i', src, '-c:v', 'copy', '-af', fx.af, '-c:a', 'aac', '-b:a', '192k'], outPath(src, fx.suffix, outExt));
}

async function askEffect(ui) {
  const r = await ui.ask({ title: 'Звук', message: 'Что сделать со звуком?', fields: [], vertical: true, buttons: EFFECTS.map((e) => e.title) });
  return r ? EFFECTS[r.button] : null;
}

module.exports = { EFFECTS, apply, askEffect };
