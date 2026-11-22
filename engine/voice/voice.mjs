// Voice-over with Microsoft Edge TTS (msedge-tts, no API key).
// Every line becomes its own mp3, so the editor can place each line on the timeline and cut on it.
//
// Usage: node engine/voice/voice.mjs <lines.json> <out folder> [voice] [rate]
//   lines.json: [{ "id": "037", "text": "I'm Alex Carter..." }, ...]   (empty text = skipped)
//   voice default en-US-AndrewMultilingualNeural, rate default +0%  (e.g. ru-RU-DmitryNeural +10%)
// Writes <out>/<id>.mp3 and <out>/voice.json: [{ id, text, file, duration, words: [{ text, start, end }] }].
// Lines are cached by voice+rate+text in <out>/.cache, so editing a few lines re-voices only those.
import { MsEdgeTTS, OUTPUT_FORMAT } from "msedge-tts";
import { execFileSync } from "node:child_process";
import crypto, { webcrypto } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

globalThis.crypto ??= webcrypto;
const here = path.dirname(fileURLToPath(import.meta.url));
const FFPROBE = path.join(here, "..", "Kdenlive", "kdenlive-26.08.3_standalone", "bin", "ffprobe.exe");

const [LINES, OUT, VOICE = "en-US-AndrewMultilingualNeural", RATE = "+0%"] = process.argv.slice(2);
if (!LINES || !OUT) throw new Error("Usage: node engine/voice/voice.mjs <lines.json> <out folder> [voice] [rate]");
const lines = JSON.parse(fs.readFileSync(LINES, "utf8"));
fs.mkdirSync(path.join(OUT, ".cache"), { recursive: true });

async function synthesize(text, dir, attempts = 4) {
  fs.mkdirSync(dir, { recursive: true });
  for (let i = 1; ; i++) {
    const tts = new MsEdgeTTS();
    try {
      await tts.setMetadata(VOICE, OUTPUT_FORMAT.AUDIO_24KHZ_96KBITRATE_MONO_MP3, { wordBoundaryEnabled: true });
      // msedge-tts sends the text inside SSML unescaped: a bare "&" (e.g. "Terri & Sandy") kills the stream
      const ssml = text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
      return await tts.toFile(dir, ssml, { rate: RATE });
    } catch (err) {
      if (i >= attempts) throw err;
      console.warn(`TTS attempt ${i} failed, retrying...`);
      await new Promise((r) => setTimeout(r, 1500 * i));
    } finally {
      tts.close();
    }
  }
}
const duration = (file) =>
  Number(execFileSync(FFPROBE, ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", file], { encoding: "utf8" }));

const result = [];
let reused = 0;
for (const line of lines) {
  const text = (line.text || "").trim();
  if (!text) continue;
  const key = crypto.createHash("sha1").update(`${VOICE}|${RATE}|${text}`).digest("hex").slice(0, 16);
  const dir = path.join(OUT, ".cache", key);
  let audio = path.join(dir, "audio.mp3"), meta = path.join(dir, "metadata.json");
  if (fs.existsSync(audio) && fs.existsSync(meta)) reused++;
  else ({ audioFilePath: audio, metadataFilePath: meta } = await synthesize(text, dir));
  const file = `${line.id}.mp3`;
  fs.copyFileSync(audio, path.join(OUT, file));
  const words = JSON.parse(fs.readFileSync(meta, "utf8")).Metadata.filter((m) => m.Type === "WordBoundary").map((m) => ({
    text: m.Data.text.Text,
    start: +(m.Data.Offset / 1e7).toFixed(3),
    end: +((m.Data.Offset + m.Data.Duration) / 1e7).toFixed(3),
  }));
  result.push({ ...line, text, file, duration: +duration(path.join(OUT, file)).toFixed(3), words });
  process.stdout.write(`\r${result.length}/${lines.length}`);
}
fs.writeFileSync(path.join(OUT, "voice.json"), JSON.stringify(result, null, 1));
const total = result.reduce((s, r) => s + r.duration, 0);
console.log(`\n${OUT}: ${VOICE} ${RATE}, ${result.length} lines (${reused} from cache), ${total.toFixed(1)} s of speech`);
