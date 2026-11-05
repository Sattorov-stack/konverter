'use strict';
// Удаление фона с фото: нейросеть silueta (U²-Net), работает офлайн через onnxruntime
const path = require('path');
const { uniqueOut } = require('./util');
const C = require('./convert');

let session = null;
const modelFile = () => process.env.KONVERTER_BG_MODEL || path.join(__dirname, '..', 'assets', 'models', 'silueta.onnx');

async function getSession() {
  if (!session) session = await require('onnxruntime-node').InferenceSession.create(modelFile());
  return session;
}

async function removeBackground(src) {
  const sharp = require('sharp');
  const ort = require('onnxruntime-node');
  const base = await (await C.openImage(src)).png().toBuffer({ resolveWithObject: true });
  const { width: w, height: h } = base.info;
  const N = 320;

  const small = await sharp(base.data).removeAlpha().resize(N, N, { fit: 'fill' }).raw().toBuffer();
  let max = 1;
  for (let i = 0; i < small.length; i++) if (small[i] > max) max = small[i];
  const mean = [0.485, 0.456, 0.406], std = [0.229, 0.224, 0.225];
  const input = new Float32Array(3 * N * N);
  for (let i = 0; i < N * N; i++) for (let c = 0; c < 3; c++) input[c * N * N + i] = (small[i * 3 + c] / max - mean[c]) / std[c];

  const s = await getSession();
  const res = await s.run({ [s.inputNames[0]]: new ort.Tensor('float32', input, [1, 3, N, N]) });
  const pred = res[s.outputNames[0]].data;
  let mn = Infinity, mx = -Infinity;
  for (let i = 0; i < pred.length; i++) { if (pred[i] < mn) mn = pred[i]; if (pred[i] > mx) mx = pred[i]; }
  const range = mx - mn || 1;
  const mask = Buffer.alloc(N * N);
  for (let i = 0; i < N * N; i++) mask[i] = Math.round((255 * (pred[i] - mn)) / range);

  // extractChannel(0) нужен, чтобы маска осталась одноканальной (иначе sharp делает из неё RGB)
  const bigMask = await sharp(mask, { raw: { width: N, height: N, channels: 1 } }).resize(w, h, { kernel: 'lanczos3' }).extractChannel(0).raw().toBuffer();
  if (bigMask.length !== w * h) throw new Error('Не удалось построить маску фона');

  // RGBA собираем вручную: так прозрачность гарантированно попадает в итоговый PNG
  const rgb = await sharp(base.data).removeAlpha().raw().toBuffer();
  const rgba = Buffer.alloc(w * h * 4);
  for (let i = 0; i < w * h; i++) {
    rgba[i * 4] = rgb[i * 3];
    rgba[i * 4 + 1] = rgb[i * 3 + 1];
    rgba[i * 4 + 2] = rgb[i * 3 + 2];
    rgba[i * 4 + 3] = bigMask[i];
  }
  const out = uniqueOut(C.outputDir(src), `${path.basename(src, path.extname(src))} (без фона)`, 'png');
  await sharp(rgba, { raw: { width: w, height: h, channels: 4 } }).png().toFile(out);
  return out;
}

module.exports = { removeBackground };
