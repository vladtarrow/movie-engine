// film-render.mjs — renders long code-driven films on the GPU (html-render.mjs is for short DOM scenes).
// The page composes every frame itself on a canvas, accumulates the motion blur in 16-bit float and encodes with
// WebCodecs, so only finished H.264 leaves the browser: about 20 times faster than screenshots, same quality.
//
//   engine\node.cmd engine\tools\film-render.mjs <film.html> <out dir> [--clips all|3|0:24] [--suffix -v01] [--force]
//   engine\node.cmd engine\tools\film-render.mjs <film.html> <out dir> --frames 410,900 | --shots all [--width 384]
//   engine\node.cmd engine\tools\film-render.mjs <film.html> <out dir> --check        errors in the direction
//
// The page gives window.film (engine/tools/film/film-kit.js does): ready, clips() -> [{ name, from, to }],
// startClip(from, to), takeChunk(), still(frame, width), stills(), check(), cues().
import { spawn } from 'node:child_process'
import { createRequire } from 'node:module'
import { once } from 'node:events'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const engine = path.dirname(path.dirname(fileURLToPath(import.meta.url)))
const WebSocket = createRequire(path.join(engine, 'voice', 'package.json'))('ws')
const FFMPEG = path.join(engine, 'Kdenlive', 'kdenlive-26.08.3_standalone', 'bin', 'ffmpeg.exe')
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms))

const args = process.argv.slice(2)
const flag = name => {
  const i = args.indexOf(`--${name}`)
  return i >= 0 && !!args.splice(i, 1)
}
const option = name => {
  const i = args.indexOf(`--${name}`)
  return i < 0 ? undefined : args.splice(i, 2)[1]
}
const force = flag('force')
const checkOnly = flag('check')
const wantClips = option('clips') ?? 'all'
const wantFrames = option('frames')
const wantShots = option('shots')
const width = Number(option('width') ?? 1920)
const suffix = option('suffix') ?? ''
const [pageArg, outArg] = args
if (!pageArg || !outArg) {
  console.error('usage: film-render.mjs <film.html> <out dir> [--clips all|3|0:24] [--suffix -v01] [--force] [--frames 1,2 | --shots all] [--width 384] [--check]')
  process.exit(1)
}

function findBrowser () {
  const roots = [process.env['ProgramFiles(x86)'], process.env.ProgramFiles].filter(Boolean)
  const found = [process.env.MOVIE_ENGINE_BROWSER, ...roots.map(r => path.join(r, 'Microsoft', 'Edge', 'Application', 'msedge.exe'))]
    .find(p => p && fs.existsSync(p))
  if (!found) throw new Error('Microsoft Edge not found; set MOVIE_ENGINE_BROWSER')
  return found
}

const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'film-render-'))
const browser = spawn(findBrowser(), [
  '--headless=new', '--remote-debugging-port=0', `--user-data-dir=${profile}`,
  '--no-first-run', '--no-default-browser-check', '--disable-extensions', '--disable-sync', '--mute-audio',
  '--disable-background-networking', '--disable-component-update',
  '--disable-background-timer-throttling', '--disable-renderer-backgrounding',
  '--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1',   // local files only
  '--allow-file-access-from-files',
  '--force-color-profile=srgb', '--force-device-scale-factor=1',
  'about:blank'
], { stdio: 'ignore', windowsHide: true })
try { os.setPriority(browser.pid, os.constants.priority.PRIORITY_BELOW_NORMAL) } catch {}

let ws
try {
  const portFile = path.join(profile, 'DevToolsActivePort')
  for (let i = 0; i < 150 && !fs.existsSync(portFile); i++) await sleep(200)
  await sleep(300)
  const [port, wsPath] = fs.readFileSync(portFile, 'utf8').trim().split('\n').map(s => s.trim())
  ws = new WebSocket(`ws://127.0.0.1:${port}${wsPath}`, { perMessageDeflate: false, maxPayload: 256 * 1024 * 1024 })
  await once(ws, 'open')
  let id = 0
  const waiting = new Map()
  ws.on('message', data => {
    const message = JSON.parse(data)
    const entry = waiting.get(message.id)
    if (!entry) return
    waiting.delete(message.id)
    message.error ? entry.reject(new Error(message.error.message)) : entry.resolve(message.result)
  })
  ws.on('close', () => { for (const entry of waiting.values()) entry.reject(new Error('browser closed')); waiting.clear() })
  const send = (method, params = {}, sessionId) => new Promise((resolve, reject) => {
    waiting.set(++id, { resolve, reject })
    ws.send(JSON.stringify({ id, method, params, sessionId }))
  })

  const { targetId } = await send('Target.createTarget', { url: pathToFileURL(path.resolve(pageArg)).href })
  const { sessionId } = await send('Target.attachToTarget', { targetId, flatten: true })
  const evaluate = async expression => {
    const { result, exceptionDetails } = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true }, sessionId)
    if (exceptionDetails) throw new Error(`film: ${exceptionDetails.exception?.description ?? exceptionDetails.text}`)
    return result.value
  }
  let loaded = false
  for (let i = 0; i < 100 && !loaded; i++) {
    await sleep(200)
    loaded = await evaluate('!!window.film').catch(() => false)
  }
  if (!loaded) {
    const why = await evaluate('window.filmError || "window.film is not defined"').catch(e => e.message)
    throw new Error(`the page did not start: ${why}`)
  }
  await evaluate('window.film.ready.then(() => true)')

  const out = path.resolve(outArg)
  fs.mkdirSync(out, { recursive: true })

  if (checkOnly) {
    const problems = await evaluate('window.film.check()')
    console.log(problems.length ? problems.join('\n') : 'direction: no problems')
    fs.writeFileSync(path.join(out, 'cues.json'), JSON.stringify(await evaluate('window.film.cues()')))
    if (problems.length) process.exitCode = 1
  } else if (wantFrames || wantShots) {
    let list = wantFrames?.split(',').map(f => ({ name: `f${String(f).padStart(5, '0')}`, frame: Number(f) }))
    if (wantShots) {
      list = await evaluate('window.film.stills()')
      if (wantShots !== 'all') {
        const [a, b = a] = wantShots.split(':').map(Number)
        list = list.filter(s => s.n >= a && s.n <= b)
      }
    }
    for (const { name, frame } of list) {
      fs.writeFileSync(path.join(out, `${name}.jpg`), Buffer.from(await evaluate(`window.film.still(${frame}, ${width})`), 'base64'))
    }
    console.log(`${list.length} stills in ${out}`)
  } else {
    let clips = await evaluate('window.film.clips()')
    if (wantClips !== 'all') {
      const [a, b] = wantClips.split(':').map(Number)
      clips = clips.slice(a, b ?? a + 1)
    }
    const started = Date.now()
    let doneFrames = 0
    for (const [i, clip] of clips.entries()) {
      const file = path.join(out, `${clip.name}${suffix}.mp4`)
      if (!force && fs.existsSync(file)) continue
      const part = `${file}.part.mp4`
      const ffmpeg = spawn(FFMPEG, [
        '-hide_banner', '-loglevel', 'error', '-y', '-fflags', '+genpts', '-r', '30', '-f', 'h264', '-i', '-', '-c', 'copy',
        '-bsf:v', 'h264_metadata=colour_primaries=1:transfer_characteristics=1:matrix_coefficients=1:video_full_range_flag=0',
        '-movflags', '+faststart', part
      ], { stdio: ['pipe', 'inherit', 'inherit'], windowsHide: true })
      const finished = once(ffmpeg, 'exit')
      ffmpeg.stdin.on('error', () => {})   // reported through the exit code
      await evaluate(`(window.film.startClip(${clip.from}, ${clip.to}), true)`)
      for (;;) {
        const { data, done } = await evaluate('window.film.takeChunk()')
        if (data && !ffmpeg.stdin.write(Buffer.from(data, 'base64'))) await once(ffmpeg.stdin, 'drain')
        if (done) break
      }
      ffmpeg.stdin.end()
      const [code] = await finished
      if (code !== 0) throw new Error(`${clip.name}: ffmpeg exit ${code}`)
      fs.renameSync(part, file)   // a clip that exists is complete, so a run can be resumed
      doneFrames += clip.to - clip.from
      if (i % 10 === 0 || i === clips.length - 1) console.log(`clip ${i + 1}/${clips.length} ${clip.name}: ${(doneFrames / ((Date.now() - started) / 1000)).toFixed(1)} frames/s`)
    }
    console.log(`rendered ${doneFrames} frames in ${Math.round((Date.now() - started) / 1000)} s -> ${out}`)
  }
  await Promise.race([send('Browser.close'), sleep(3000)]).catch(() => {})
} catch (error) {
  console.error(String(error.stack ?? error))
  process.exitCode = 1
} finally {
  ws?.close()
  if (browser.exitCode === null) await Promise.race([once(browser, 'exit'), sleep(4000)])
  if (browser.exitCode === null) browser.kill()
  await sleep(500)
  try { fs.rmSync(profile, { recursive: true, force: true, maxRetries: 10, retryDelay: 300 }) } catch {}
}
