'use strict';
// Расшифровка речи в текст и субтитры (whisper.cpp). Модель скачивается один раз при первом запуске.
const fs = require('fs');
const os = require('os');
const path = require('path');
const https = require('https');
const { run, uniqueOut } = require('./util');
const C = require('./convert');

const MODEL_URL = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin';
const MODEL_MIN_BYTES = 100 * 1024 * 1024;
let dataDir = os.tmpdir();
const setDataDir = (d) => { dataDir = d; };

function whisperExe() {
  const dir = process.env.KONVERTER_WHISPER_DIR || path.join(__dirname, '..', 'assets', 'whisper');
  const exe = path.join(dir, process.platform === 'win32' ? 'whisper-cli.exe' : 'whisper-cli');
  return fs.existsSync(exe) ? exe : null;
}

function download(url, dest, onProgress, redirects = 5) {
  return new Promise((resolve, reject) => {
    const req = https.get(url, { headers: { 'User-Agent': 'Konverter' } }, (res) => {
      if ([301, 302, 303, 307, 308].includes(res.statusCode) && res.headers.location && redirects > 0) {
        res.resume();
        resolve(download(new URL(res.headers.location, url).toString(), dest, onProgress, redirects - 1));
        return;
      }
      if (res.statusCode !== 200) { res.resume(); reject(new Error(`Сервер ответил ${res.statusCode}`)); return; }
      const total = Number(res.headers['content-length']) || 0;
      let got = 0;
      const tmp = dest + '.part';
      const ws = fs.createWriteStream(tmp);
      res.on('data', (c) => { got += c.length; if (onProgress && total) onProgress(got / total); });
      res.pipe(ws);
      ws.on('finish', () => ws.close(() => { fs.renameSync(tmp, dest); resolve(dest); }));
      ws.on('error', reject);
      res.on('error', reject);
    });
    req.on('error', reject);
  });
}

let modelLoading = null; // одна загрузка за раз: параллельная испортила бы файл

function ensureModel(onProgress) {
  if (process.env.KONVERTER_WHISPER_MODEL) return Promise.resolve(process.env.KONVERTER_WHISPER_MODEL);
  if (!modelLoading) modelLoading = loadModel(onProgress).finally(() => { modelLoading = null; });
  return modelLoading;
}

async function loadModel(onProgress) {
  const file = path.join(dataDir, 'models', 'ggml-base.bin');
  if (fs.existsSync(file) && fs.statSync(file).size > MODEL_MIN_BYTES) return file;
  // Модель может лежать рядом с приложением — тогда интернет не нужен вовсе
  const bundled = path.join(__dirname, '..', 'assets', 'whisper', 'ggml-base.bin');
  if (fs.existsSync(bundled) && fs.statSync(bundled).size > MODEL_MIN_BYTES) return bundled;
  fs.mkdirSync(path.dirname(file), { recursive: true });
  try {
    await download(MODEL_URL, file, onProgress);
  } catch (e) {
    throw new Error(`Не удалось скачать модель распознавания речи (около 150 МБ, нужен интернет один раз): ${e.message}`);
  }
  return file;
}

async function transcribe(src, { lang = 'auto', format = 'srt', ui } = {}) {
  const exe = whisperExe();
  if (!exe) throw new Error('Модуль распознавания речи не найден. Переустанови приложение.');
  const model = await ensureModel((p) => { if (ui && ui.progress) ui.progress('Скачиваю модель распознавания…', `${Math.round(p * 100)}%`); });
  if (ui && ui.progress) ui.progress('Распознаю речь…', path.basename(src));
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'konv-speech-'));
  try {
    const wav = path.join(tmp, 'audio.wav');
    await run(C.requireFFmpeg(), ['-y', '-nostdin', '-hide_banner', '-i', src, '-vn', '-ar', '16000', '-ac', '1', '-c:a', 'pcm_s16le', wav]);
    const out = uniqueOut(C.outputDir(src), `${path.basename(src, path.extname(src))} (${format === 'srt' ? 'субтитры' : 'текст'})`, format);
    const base = out.slice(0, -(format.length + 1));
    await run(exe, ['-m', model, '-f', wav, '-l', lang, format === 'srt' ? '-osrt' : '-otxt', '-of', base]);
    if (!fs.existsSync(out)) throw new Error('Распознавание не дало результата');
    return out;
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

async function askSpeech(ui) {
  const f = await ui.ask({ title: 'Речь в текст', message: 'Что получить?', fields: [], vertical: true, buttons: ['Субтитры (.srt)', 'Текст (.txt)'] });
  if (!f) return null;
  const l = await ui.ask({ title: 'Язык речи', message: 'На каком языке говорят?', fields: [], vertical: true, buttons: ['Определить автоматически', 'Русский', 'English', 'Українська'] });
  if (!l) return null;
  return { format: f.button === 0 ? 'srt' : 'txt', lang: ['auto', 'ru', 'en', 'uk'][l.button] };
}

module.exports = { transcribe, askSpeech, setDataDir, whisperExe, ensureModel };
