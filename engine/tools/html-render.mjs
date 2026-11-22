// html-render.mjs — renders a code-driven HTML/CSS/canvas animation to video, frame by frame.
// For motion graphics Kdenlive cannot do: interface animation, cursors, 3D transforms, physics, masks.
//
//   engine\node.cmd engine\tools\html-render.mjs <scene.html> <out.mp4> [--sub 16] [--workers 5]    video
//       sub = motion-blur samples per frame (fewer than ~12 leaves visible steps on fast moves); workers = browsers in parallel
//   engine\node.cmd engine\tools\html-render.mjs <scene.html> <out dir> --frames 0,45,120    check frames as PNG
//
// The scene defines:
//   window.SCENE = { fps, frames, width, height }
//   window.ready : a promise that resolves when fonts and images are loaded
//   window.render(seconds) : draws that moment; a pure function of time, so any frame can be rendered on its own
//
// The browser is the Microsoft Edge that is part of Windows, headless (no window, no focus), with a throw-away
// profile and no network. Override its path with the MOVIE_ENGINE_BROWSER environment variable.
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

const args = process.argv.slice(2)
const option = name => {
  const i = args.indexOf(`--${name}`)
  return i < 0 ? undefined : args.splice(i, 2)[1]
}
const onlyFrames = option('frames')?.split(',').map(Number)
const sub = Math.max(1, Number(option('sub') ?? 16))
const workers = Math.max(1, Number(option('workers') ?? Math.min(5, Math.max(1, Math.floor(os.cpus().length / 2)))))
const part = option('part')?.split('/').map(Number)   // internal: "index/count", set by the parent process
const [sceneArg, outArg] = args
if (!sceneArg || !outArg) {
  console.error('usage: html-render.mjs <scene.html> <out.mp4 | dir> [--sub 16] [--workers 5] [--frames 0,10,20]')
  process.exit(1)
}

// several workers: each renders its share of the frames, then the parts are joined without re-encoding
if (!onlyFrames && !part && workers > 1) {
  const out = path.resolve(outArg)
  fs.mkdirSync(path.dirname(out), { recursive: true })
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'html-render-parts-'))
  try {
    const files = Array.from({ length: workers }, (_, i) => path.join(dir, `part${i}.mp4`))
    const started = Date.now()
    const codes = await Promise.all(files.map(async (file, i) => {
      const child = spawn(process.execPath, [fileURLToPath(import.meta.url), sceneArg, file, '--sub', String(sub), '--part', `${i}/${workers}`],
        { stdio: ['ignore', 'ignore', 'inherit'], windowsHide: true })
      try { os.setPriority(child.pid, os.constants.priority.PRIORITY_BELOW_NORMAL) } catch {}
      return (await once(child, 'exit'))[0]
    }))
    if (codes.some(code => code !== 0)) throw new Error(`a worker failed (exit codes ${codes.join(', ')})`)
    const list = path.join(dir, 'parts.txt')
    fs.writeFileSync(list, files.map(file => `file '${file.replaceAll('\\', '/').replaceAll("'", "'\\''")}'`).join('\n'))
    const join = spawn(FFMPEG, ['-hide_banner', '-loglevel', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', list, '-c', 'copy', '-movflags', '+faststart', out],
      { stdio: 'inherit', windowsHide: true })
    const [code] = await once(join, 'exit')
    if (code !== 0) throw new Error(`joining the parts failed (ffmpeg exit ${code})`)
    console.log(`rendered ${out} (${sub} samples per frame, ${workers} workers, ${Math.round((Date.now() - started) / 1000)} s)`)
    process.exitCode = 0
  } catch (error) {
    console.error(String(error.stack ?? error))
    process.exitCode = 1
  } finally {
    fs.rmSync(dir, { recursive: true, force: true })
  }
  process.exit()
}

function findBrowser () {
  const roots = [process.env['ProgramFiles(x86)'], process.env.ProgramFiles].filter(Boolean)
  const found = [process.env.MOVIE_ENGINE_BROWSER, ...roots.map(r => path.join(r, 'Microsoft', 'Edge', 'Application', 'msedge.exe'))]
    .find(p => p && fs.existsSync(p))
  if (!found) throw new Error('Microsoft Edge not found; set MOVIE_ENGINE_BROWSER')
  return found
}

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms))

async function connect (url) {
  const ws = new WebSocket(url, { perMessageDeflate: false, maxPayload: 256 * 1024 * 1024 })
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
  ws.on('close', () => {
    for (const entry of waiting.values()) entry.reject(new Error('browser closed'))
    waiting.clear()
  })
  const send = (method, params = {}, sessionId) => new Promise((resolve, reject) => {
    waiting.set(++id, { resolve, reject })
    ws.send(JSON.stringify({ id, method, params, sessionId }))
  })
  return { ws, send }
}

const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'html-render-'))
const browser = spawn(findBrowser(), [
  '--headless=new',
  '--remote-debugging-port=0',
  `--user-data-dir=${profile}`,
  '--no-first-run', '--no-default-browser-check', '--disable-extensions', '--disable-sync', '--mute-audio',
  '--disable-background-networking', '--disable-component-update',
  // local scene files only: nothing may resolve to the internet
  '--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1',
  '--allow-file-access-from-files',
  '--force-color-profile=srgb', '--force-device-scale-factor=1', '--hide-scrollbars',
  'about:blank'
], { stdio: 'ignore', windowsHide: true })
try { os.setPriority(browser.pid, os.constants.priority.PRIORITY_BELOW_NORMAL) } catch {}

let client
try {
  const portFile = path.join(profile, 'DevToolsActivePort')
  for (let i = 0; i < 150 && !fs.existsSync(portFile); i++) await sleep(200)
  await sleep(300)
  const [port, wsPath] = fs.readFileSync(portFile, 'utf8').trim().split('\n').map(s => s.trim())
  client = await connect(`ws://127.0.0.1:${port}${wsPath}`)

  const { targetId } = await client.send('Target.createTarget', { url: 'about:blank' })
  const { sessionId } = await client.send('Target.attachToTarget', { targetId, flatten: true })
  const page = (method, params) => client.send(method, params, sessionId)
  const evaluate = async expression => {
    const { result, exceptionDetails } = await page('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true })
    if (exceptionDetails) throw new Error(`scene: ${exceptionDetails.exception?.description ?? exceptionDetails.text}`)
    return result.value
  }

  await page('Emulation.setDeviceMetricsOverride', { width: 1920, height: 1080, deviceScaleFactor: 1, mobile: false })
  await page('Page.navigate', { url: pathToFileURL(path.resolve(sceneArg)).href })
  let loaded = false
  for (let i = 0; i < 150 && !loaded; i++) {
    await sleep(200)
    loaded = await evaluate('!!(window.SCENE && window.ready && window.render)').catch(() => false)
  }
  if (!loaded) throw new Error('the scene did not define SCENE, ready and render')
  await evaluate('window.ready.then(() => true)')
  const scene = await evaluate('window.SCENE')
  await page('Emulation.setDeviceMetricsOverride', { width: scene.width, height: scene.height, deviceScaleFactor: 1, mobile: false })

  const shoot = async seconds => {
    await evaluate(`(window.render(${seconds}), true)`)
    const { data } = await page('Page.captureScreenshot', { format: 'png', optimizeForSpeed: true })
    return Buffer.from(data, 'base64')
  }

  const out = path.resolve(outArg)
  if (onlyFrames) {
    fs.mkdirSync(out, { recursive: true })
    for (const f of onlyFrames) fs.writeFileSync(path.join(out, `f${String(f).padStart(4, '0')}.png`), await shoot(f / scene.fps))
    console.log(`${onlyFrames.length} check frames in ${out}`)
  } else {
    fs.mkdirSync(path.dirname(out), { recursive: true })
    const first = part ? Math.floor(scene.frames * part[0] / part[1]) : 0
    const last = part ? Math.floor(scene.frames * (part[0] + 1) / part[1]) : scene.frames
    const filters = []
    if (sub > 1) filters.push(`tmix=frames=${sub}`, `select='eq(mod(n\\,${sub})\\,${sub - 1})'`, `setpts=N/(${scene.fps}*TB)`)
    filters.push('scale=out_color_matrix=bt709:out_range=tv:flags=lanczos+accurate_rnd+full_chroma_int', 'format=yuv420p')
    const ffmpeg = spawn(FFMPEG, [
      '-hide_banner', '-loglevel', 'error', '-y',
      '-f', 'image2pipe', '-c:v', 'png', '-framerate', String(scene.fps * sub), '-i', '-',
      '-vf', filters.join(','),
      '-c:v', 'libx264', '-preset', 'slow', '-crf', '12', '-g', '15',
      '-colorspace', 'bt709', '-color_primaries', 'bt709', '-color_trc', 'bt709', '-color_range', 'tv',
      '-r', String(scene.fps), '-frames:v', String(last - first), '-movflags', '+faststart', out
    ], { stdio: ['pipe', 'inherit', 'inherit'], windowsHide: true })
    const finished = once(ffmpeg, 'exit')
    ffmpeg.stdin.on('error', () => {})   // reported through the exit code

    const started = Date.now()
    for (let f = first; f < last; f++) {
      for (let s = 0; s < sub; s++) {
        // 180 degree shutter, centred on the frame
        const offset = sub > 1 ? ((s + 0.5) / sub - 0.5) / 2 : 0
        if (!ffmpeg.stdin.write(await shoot(Math.max(0, f + offset) / scene.fps))) await once(ffmpeg.stdin, 'drain')
      }
      if (f % 60 === 0) console.log(`frame ${f}/${scene.frames} (${Math.round((Date.now() - started) / 1000)} s)`)
    }
    ffmpeg.stdin.end()
    const [code] = await finished
    if (code !== 0) throw new Error(`ffmpeg exit ${code}`)
    console.log(`rendered ${out} (${last - first} frames, ${Math.round((Date.now() - started) / 1000)} s)`)
  }
} catch (error) {
  console.error(String(error.stack ?? error))
  process.exitCode = 1
} finally {
  try { await Promise.race([client?.send('Browser.close'), sleep(3000)]) } catch {}
  client?.ws.close()
  if (browser.exitCode === null) await Promise.race([once(browser, 'exit'), sleep(5000)])
  if (browser.exitCode === null) browser.kill()
  await sleep(700)
  try { fs.rmSync(profile, { recursive: true, force: true, maxRetries: 10, retryDelay: 300 }) } catch {}
}
