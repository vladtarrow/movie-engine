// Synthesizes a set of UI / transition sound effects in code (no samples, no downloads).
// Usage: node engine/audio/sfx.mjs <out folder>
// Writes whoosh.wav, whoosh-long.wav, swipe.wav, click.wav, pop.wav, tick.wav, riser.wav, impact.wav, ding.wav, reveal.wav
import fs from "node:fs";
import path from "node:path";

const SR = 44100;
const OUT = process.argv[2];
if (!OUT) throw new Error("Usage: node engine/audio/sfx.mjs <out folder>");
fs.mkdirSync(OUT, { recursive: true });

let seed = 12345;
const rand = () => ((seed = (seed * 1664525 + 1013904223) >>> 0) / 2 ** 32) * 2 - 1;

function writeWav(name, left, right = left) {
  const n = left.length;
  let peak = 1e-9;
  for (let i = 0; i < n; i++) peak = Math.max(peak, Math.abs(left[i]), Math.abs(right[i]));
  const g = 0.89 / peak; // normalise to about -1 dBFS; the editor sets the level
  const buf = Buffer.alloc(44 + n * 4);
  buf.write("RIFF", 0); buf.writeUInt32LE(36 + n * 4, 4); buf.write("WAVEfmt ", 8);
  buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(2, 22);
  buf.writeUInt32LE(SR, 24); buf.writeUInt32LE(SR * 4, 28); buf.writeUInt16LE(4, 32); buf.writeUInt16LE(16, 34);
  buf.write("data", 36); buf.writeUInt32LE(n * 4, 40);
  for (let i = 0; i < n; i++) {
    buf.writeInt16LE(Math.round(Math.max(-1, Math.min(1, left[i] * g)) * 32767), 44 + i * 4);
    buf.writeInt16LE(Math.round(Math.max(-1, Math.min(1, right[i] * g)) * 32767), 46 + i * 4);
  }
  fs.writeFileSync(path.join(OUT, name), buf);
}
function sfx(len, fn) {
  const out = new Float32Array(Math.floor(len * SR));
  for (let i = 0; i < out.length; i++) out[i] = fn(i / SR, i / out.length);
  return out;
}
// filtered-noise sweep; pan moves left->right for a stereo pass-by
function sweep(len, bright, panMove = 0) {
  let lp = 0;
  const L = new Float32Array(Math.floor(len * SR)), R = new Float32Array(L.length);
  for (let i = 0; i < L.length; i++) {
    const p = i / L.length, env = Math.sin(Math.PI * p) ** 2;
    lp += (0.02 + bright * Math.sin(Math.PI * p)) * (rand() - lp);
    const pan = 0.5 + panMove * (p - 0.5);
    L[i] = lp * env * Math.cos(pan * Math.PI / 2) * 1.41;
    R[i] = lp * env * Math.sin(pan * Math.PI / 2) * 1.41;
  }
  return [L, R];
}

writeWav("whoosh.wav", ...sweep(0.45, 0.4, 0.6));
writeWav("whoosh-long.wav", ...sweep(0.9, 0.3, 0.9));
writeWav("swipe.wav", ...sweep(0.25, 0.6, 0.8));
writeWav("click.wav", sfx(0.04, (t) => (Math.sin(2 * Math.PI * 2200 * t) * 0.7 + rand() * 0.3) * Math.exp(-t * 160)));
let ph = 0;
writeWav("pop.wav", sfx(0.12, (t) => { ph += (2 * Math.PI * (300 + 700 * Math.exp(-t * 40))) / SR; return Math.sin(ph) * Math.exp(-t * 30); }));
writeWav("tick.wav", sfx(0.03, (t) => Math.sin(2 * Math.PI * 3800 * t) * Math.exp(-t * 250)));
let lpR = 0;
writeWav("riser.wav", sfx(2, (t, p) => {
  lpR += (0.02 + 0.5 * p * p) * (rand() - lpR);
  return lpR * p * p * 0.8 + Math.sin(2 * Math.PI * (200 + 900 * p * p) * t) * 0.15 * p * p;
}));
let lpI = 0, phI = 0;
writeWav("impact.wav", sfx(1.4, (t) => {
  phI += (2 * Math.PI * (40 + 110 * Math.exp(-t * 25))) / SR;
  lpI += 0.08 * (rand() - lpI);
  return Math.sin(phI) * Math.exp(-t * 4) + lpI * Math.exp(-t * 3) * 0.6;
}));
const bell = (f) => (t) => [1, 2.76, 5.4].reduce((s, k, j) => s + Math.sin(2 * Math.PI * f * k * t) * [1, 0.4, 0.15][j] * Math.exp(-t * (3 + j * 3)), 0);
const b1 = bell(1318.5), b2 = bell(1760);
writeWav("ding.wav", sfx(1.2, (t) => b1(t) * Math.min(1, t * 400)));
// two-note "reveal" chime for the five secrets
writeWav("reveal.wav", sfx(1.6, (t) => b1(t) * 0.8 + (t > 0.14 ? b2(t - 0.14) : 0)));
console.log(`${OUT}: 10 sound effects written`);
