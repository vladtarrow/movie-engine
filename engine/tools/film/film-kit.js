// film-kit.js — a light, interactive film made from storyboard elements, timed to the words of the voice.
//
//   window.film = FilmKit.create({ data, direction, scenes, media, font })
//
// data      : window.FILM of a project's build-data.py (shots with elements, VO lines with word times)
// direction : text, one line per shot:   <n> key=value key=value | action args @word | action args +seconds
//             coordinates are those of a 384x216 contact-sheet cell (x 5 = slide pixels);
//             @word = when the voice says it, +1.2 = seconds after the shot starts, nothing = spread over the shot.
//   keys:    s=0.7 scale | trim=1 clip tall pictures above the captions | fit=0.85 shrink | crop=0.4 left part of a background | cont=1 no push | at=960,478 centre | scene=name | hide=0,2 elements | say=Line one/Line *marked* (kinetic text)
//            panel=Title~chip~chip (a small live panel beside a dark picture) | text=keep (do not darken white text)
//            enter=left|right|up|down|zoom
//   actions: click x y | hover x y | drag x y dx dy [back] | ring x y w h | box x y w h | select x y w h
//            under x1 y1 x2 y2 | strike x1 y1 x2 y2 | arrow x1 y1 x2 y2 | lens x y r [zoom] | zoom x y k
//            scroll amount | spin x y | pop x y | shake | wipe | burst x y | confetti x y | tag x y Text
//            chips A~B~C | toggle Label | slider From~To | swatches #hex,#hex | toast Text | type Text | count a b suffix
// scenes    : custom shots, name -> (api, context) => void; context = { shot, t, age, left, at(word, fallback), opt }
//
// The stage ends at y = 925, captions always stay on the light ground below it.
(() => {
  const D = window.FilmDraw
  const { W, H, C, pen, clamp, lerp, span, out, io, back, bump, group } = D

  const STAGE = { x: 960, y: 474, s: 0.83 }
  const CELL = 5
  const PUSH = 0.44                 // seconds of the push from one VO line to the next
  const MORPH = 0.26                // seconds from one build step to the next
  const COLORS = [C.pink, C.cyan, C.violet, C.orange, C.yellow, C.green]
  const NEEDS = {
    click: 2, hover: 2, drag: 4, ring: 4, box: 4, select: 4, under: 4, strike: 4, arrow: 4, lens: 3, zoom: 3,
    scroll: 1, spin: 2, pop: 2, shake: 0, wipe: 0, burst: 2, confetti: 2, tag: 3, chips: 1, toggle: 1, slider: 1,
    swatches: 1, toast: 1, type: 1, count: 2
  }
  const SOUND = { click: 'click', drag: 'swipe', toggle: 'click', chips: 'pop', tag: 'pop', confetti: 'pop', wipe: 'swipe', swatches: 'click', toast: 'pop' }
  const norm = w => w.toLowerCase().replace(/[^\p{L}\p{N}]/gu, '')
  const luminance = hex => {
    const v = parseInt(hex.slice(1, 7), 16)
    return 0.2126 * (v >> 16) + 0.7152 * ((v >> 8) & 255) + 0.0722 * (v & 255)
  }

  function create ({ data, direction = '', scenes = {}, media, font }) {
    const FPS = data.fps
    const problems = []
    const shots = data.shots.map((s, index) => ({ ...s, index, t0: s.at / FPS, t1: (s.at + s.f) / FPS, opt: {}, acts: [] }))
    const byNumber = new Map(shots.map(s => [s.n, s]))
    const words = data.lines.flatMap(line => line.words.map(([w, a, b]) => ({ w: norm(w), a, b })))
    shots.forEach((s, i) => {
      s.prev = shots[i - 1] ?? null
      s.first = !s.prev || s.prev.g !== s.g
      if (s.first) s.segment = (s.prev?.segment ?? -1) + 1
      else s.segment = s.prev.segment
    })

    function wordTime (shot, word, report = true) {
      const key = norm(word)
      let best = null
      for (const w of words) {
        if (w.a < shot.t0 - 0.6) continue
        if (w.a > shot.t1) break
        if (w.w.startsWith(key)) { best = w; break }
      }
      if (best) return Math.max(shot.t0 + 0.05, best.a)
      if (report) problems.push(`shot ${shot.n}: the voice does not say "${word}" during it`)
      return null
    }

    // ---------- direction ----------
    for (const raw of direction.split('\n')) {
      const line = raw.trim()
      if (!line || line.startsWith('//')) continue
      const [head, ...parts] = line.split('|').map(p => p.trim())
      const number = parseInt(head)
      const shot = byNumber.get(number)
      if (!shot) { problems.push(`no shot ${number}`); continue }
      const options = head.slice(String(number).length).trim()
      const key = /(^|\s)([a-z]+)=/g
      const found = [...options.matchAll(key)]
      found.forEach((m, i) => {
        shot.opt[m[2]] = options.slice(m.index + m[0].length, found[i + 1]?.index ?? options.length).trim()
      })
      if (options && !found.length) problems.push(`shot ${number}: cannot read "${options}"`)
      if (shot.opt.scene && !scenes[shot.opt.scene]) problems.push(`shot ${number}: no scene "${shot.opt.scene}"`)

      parts.forEach((part, k) => {
        const tokens = part.split(/\s+/)
        const verb = tokens.shift()
        if (!(verb in NEEDS)) { problems.push(`shot ${number}: unknown action "${verb}"`); return }
        let at = null
        const last = tokens[tokens.length - 1] ?? ''
        if (/^@./.test(last)) at = wordTime(shot, tokens.pop().slice(1))
        else if (/^\+[\d.]+$/.test(last)) at = shot.t0 + Number(tokens.pop())
        if (tokens.length < NEEDS[verb]) { problems.push(`shot ${number}: "${verb}" needs ${NEEDS[verb]} values`); return }
        const len = shot.t1 - shot.t0
        at ??= shot.t0 + Math.min(len * 0.7, 0.36 + (len - 0.36) * k / Math.max(1, parts.length))
        shot.acts.push({ verb, at: clamp(at, shot.t0 + 0.04, shot.t1 - 0.04), v: tokens.map(Number), args: tokens, words: tokens.join(' ') })
      })
      shot.acts.sort((a, b) => a.at - b.at)
      shot.directed = true
    }
    for (const s of shots) if (!s.directed) problems.push(`shot ${s.n}: no direction`)
    for (const s of shots) s.cont = !!s.opt.cont

    // ---------- layout ----------
    for (const s of shots) {
      const hidden = new Set((s.opt.hide ?? '').split(',').filter(Boolean).map(Number))
      s.items = s.els.map((e, i) => {
        const full = e.w >= 1840 && e.h >= 1000
        return { ...e, i, framed: e.k === 'img' && full, r: e.k === 'img' && full ? 56 : (e.r ?? 0), hidden: hidden.has(i) }
      }).filter(e => !e.hidden && !(e.k === 'box' && e.w > 1800 && e.h > 1000))
      for (const e of s.items) {
        if (e.back && s.opt.crop) {   // only the meaningful left part of a background picture
          const keep = Number(s.opt.crop)
          e.w *= keep
          e.framed = false
          e.r = 40
          e.card = true
          e.crop = [0, 0, 1 - keep, 0]
        }
        const info = e.k === 'img' ? data.images[e.src] : null
        e.plate = !!s.opt.plate && !!info && info.lum > 160 && e.w < 1000 && e.h < 720   // white logos (plate=1)
      }
      let dark = 0
      for (const e of s.items) {
        const w = Math.max(0, Math.min(W, e.x + e.w) - Math.max(0, e.x))
        const h = Math.max(0, Math.min(H, e.y + e.h) - Math.max(0, e.y))
        if (e.k === 'img') {
          const info = data.images[e.src]
          if (info.lum < 100) dark += w * h * info.solid * (100 - info.lum) / 100
        } else if (e.fill && e.fill.length === 7 && luminance(e.fill) < 80) dark += w * h * 0.8
      }
      s.dark = dark / (W * H)
      for (const e of s.items) {
        e.bar = !s.items.some(o => o.k === 'text' && o.y < e.y + 20) && e.k === 'img' && e.w > 1000 && e.h > 500 && e.w / e.h > 1.25 && !e.rot && !!(e.r || e.framed) &&
          data.images[e.src].solid > 0.97 && !e.plate && !e.card
      }
      let scale = s.dark > 0.42 ? 0.64 : s.dark > 0.25 ? 0.74 : STAGE.s
      let { x, y } = STAGE
      if (s.opt.panel) { scale = Math.min(scale, 0.64); x = 700 }
      if (s.opt.s) scale = Number(s.opt.s)
      if (s.opt.fit) scale *= Number(s.opt.fit)   // dark picture: smaller, so the frame stays light
      if (s.opt.at) [x, y] = s.opt.at.split(',').map(Number)
      for (const e of s.items) {
        if (!e.bar) continue
        // the whole window stays between the top of the frame and the captions
        const reach = H / 2 - e.y + FilmLive.BAR
        if (reach > 0 && !s.opt.at) scale = Math.min(scale, (y - 16) / reach)
      }
      s.view = { x, y, s: scale }
      // the pointer's own steps, when nothing is directed
      s.lead = s.opt.say ? null : s.items.filter(e => e.w * e.h > 20000).sort((a, b) => b.w * b.h - a.w * a.h)[0] ?? null
    }
    let head = null
    for (const s of shots) {
      if (s.first) head = s
      s.segT0 = head.t0
      head.segEnd = s.t1
    }
    for (const s of shots) {
      if (s.first) head = s
      s.segT1 = head.segEnd
    }
    const toStage = (s, x, y) => [s.view.x + (x - W / 2) * s.view.s, s.view.y + (y - H / 2) * s.view.s]
    const cell = (s, x, y) => toStage(s, x * CELL, y * CELL)

    function itemAt (shot, x, y) {
      for (let i = shot.items.length - 1; i >= 0; i--) {
        const e = shot.items[i]
        if (x >= e.x && x <= e.x + e.w && y >= e.y && y <= e.y + e.h) return e
      }
      return null
    }
    for (const s of shots) {
      for (const a of s.acts) {
        if (['drag', 'spin', 'pop'].includes(a.verb)) {
          a.item = itemAt(s, a.v[0] * CELL, a.v[1] * CELL)
          if (!a.item) problems.push(`shot ${s.n}: "${a.verb}" points at no element`)
        } else if (['lens', 'zoom'].includes(a.verb)) a.item = itemAt(s, a.v[0] * CELL, a.v[1] * CELL) ?? s.lead
        else if (a.verb === 'scroll') a.item = s.lead
      }
    }

    const SPOTS = [[0.3, 0.4], [0.68, 0.62], [0.55, 0.28], [0.2, 0.7], [0.78, 0.4], [0.45, 0.8]]
    for (const s of shots) {
      if (s.opt.scene || s.opt.say || !s.lead) continue
      const e = s.lead
      const added = []
      let last = s.t0 + 0.1
      let k = s.index
      for (const next of [...s.acts.map(a => a.at), s.t1 + 0.35]) {
        while (next - last > 1.55) {
          const word = words.find(w => w.a >= last + 0.8 && w.a < next - 0.45)
          const at = Math.min(word ? word.a : last + 1.1, s.t1 - 0.12)
          if (at <= last + 0.2) break
          const [fx, fy] = SPOTS[k++ % SPOTS.length]
          const x = (clamp(e.x, 0, W) + (Math.min(W, e.x + e.w) - clamp(e.x, 0, W)) * fx) / CELL
          const y = (clamp(e.y, 0, H) + (Math.min(H, e.y + e.h) - clamp(e.y, 0, H)) * fy) / CELL
          added.push({ verb: k % 3 ? 'click' : 'hover', at, v: [x, y], args: [], words: '', auto: true })
          last = at
        }
        last = Math.max(last, next)
      }
      s.acts.push(...added)
      s.acts.sort((a, b) => a.at - b.at)
    }
    const live = FilmLive.create({ data, shots, toStage })

    // ---------- pointer: one path through the whole film ----------
    const path = []
    const clicks = []
    const holds = []
    const reach = (t, at, x, y) => {
      const last = path[path.length - 1]
      const from = Math.max(last ? last.t + 0.01 : 0, at - 0.5)
      if (last && from < at) path.push({ t: from, x: last.x, y: last.y })
      path.push({ t: Math.max(at, last ? last.t + 0.02 : 0), x, y })
    }
    for (const s of shots) {
      if (s.opt.scene && scenes[s.opt.scene]?.pointer) {
        for (const [dt, x, y, press] of scenes[s.opt.scene].pointer(s, (w, fallback) => wordTime(s, w, false) ?? s.t0 + fallback)) {
          reach(s.t0, dt, x, y)
          if (press) clicks.push({ t: dt, x, y, sound: 'click' })
        }
        continue
      }
      let moved = false
      for (const a of s.acts) {
        const [x, y, p, q] = a.v
        let goal = null
        if (['click', 'hover', 'lens', 'zoom', 'spin', 'pop', 'burst', 'tag'].includes(a.verb)) goal = cell(s, x, y)
        else if (a.verb === 'ring') goal = cell(s, x + p / 2, y)
        else if (['box', 'select', 'under', 'strike', 'arrow'].includes(a.verb)) goal = cell(s, x, y)
        else if (a.verb === 'drag') goal = cell(s, x, y)
        else if (a.verb === 'toggle') goal = [960 + (D.textWidth(a.words, 32) + 250) / 2 - 92, 868]
        else if (a.verb === 'slider') goal = [700, 868]
        else if (a.verb === 'chips') goal = [960, 868]
        else if (a.verb === 'scroll') goal = [s.view.x + 720 * s.view.s, s.view.y]
        if (!goal) continue
        reach(s.t0, a.at, ...goal)
        moved = true
        if (['click', 'spin', 'pop', 'toggle'].includes(a.verb)) clicks.push({ t: a.at, x: goal[0], y: goal[1], auto: a.auto })
        if (a.verb === 'drag') {
          const end = cell(s, x + p, y + q)
          const len = Math.min(0.7, Math.max(0.2, s.t1 - a.at - 0.1))
          a.len = len
          path.push({ t: a.at + len, x: end[0], y: end[1] })
          holds.push([a.at, a.at + len])
        } else if (['select', 'box'].includes(a.verb)) {
          const end = cell(s, x + p, y + q)
          path.push({ t: a.at + 0.32, x: end[0], y: end[1] })
          holds.push([a.at, a.at + 0.32])
        } else if (['under', 'strike', 'arrow'].includes(a.verb)) {
          const end = cell(s, p, q)
          path.push({ t: a.at + 0.32, x: end[0], y: end[1] })
        } else if (a.verb === 'slider') {
          path.push({ t: a.at + 0.7, x: 1220, y: 868 })
          holds.push([a.at, a.at + 0.7])
        }
      }
      if (!moved && s.t1 - s.t0 > 0.7) {
        const e = s.lead
        const at = e ? toStage(s, e.x + e.w * (s.index % 2 ? 0.7 : 0.35), e.y + e.h * 0.6) : [1500, 760]
        reach(s.t0, s.t0 + Math.min(0.75, (s.t1 - s.t0) * 0.6), clamp(at[0], 90, 1830), clamp(at[1], 90, 900))
      }
    }
    path.sort((a, b) => a.t - b.t)
    clicks.sort((a, b) => a.t - b.t)

    function before (list, t) {
      let a = 0; let b = list.length
      while (a < b) {
        const m = (a + b) >> 1
        if (list[m].t <= t) a = m + 1
        else b = m
      }
      return a
    }
    function pointer (t) {
      const i = before(path, t)
      if (!i) return path.length ? [path[0].x + 400, path[0].y + 260] : [1500, 760]
      const a = path[i - 1]; const b = path[i]
      const drift = [7 * Math.sin(t * 1.9), 6 * Math.cos(t * 1.5)]
      if (!b) return [a.x + drift[0], a.y + drift[1]]
      const raw = clamp((t - a.t) / Math.max(0.01, b.t - a.t)); const p = io(raw)
      const dx = b.x - a.x; const dy = b.y - a.y
      const arc = Math.sin(Math.PI * p) * Math.min(0.12, Math.hypot(dx, dy) / 9000)
      return [lerp(a.x, b.x, p) - dy * arc + drift[0], lerp(a.y, b.y, p) + dx * arc + drift[1]]
    }

    // ---------- pictures ----------
    const pictures = new Map()
    async function decodeFor (shotList) {
      const wanted = new Set(shotList.flatMap(s => s.els.filter(e => e.k === 'img').map(e => e.src)))
      for (const name of FilmKit.extraPictures?.(shotList) ?? []) wanted.add(name)
      for (const [name, bitmap] of pictures) {
        if (wanted.has(name)) continue
        bitmap.close()
        pictures.delete(name)
      }
      await Promise.all([...wanted].filter(name => !pictures.has(name)).map(async name => {
        const image = new Image()
        image.src = media + name
        await image.decode()
        const k = Math.min(1, 2400 / Math.max(image.naturalWidth, image.naturalHeight))   // sharp up to a 1.3x zoom
        pictures.set(name, await createImageBitmap(image, {
          resizeWidth: Math.round(image.naturalWidth * k), resizeHeight: Math.round(image.naturalHeight * k), resizeQuality: 'high'
        }))
      }))
    }
    function picture (name, x, y, w, h, crop) {
      D.rec(x, y, w, h)
      if (pen.dry) return
      const img = pictures.get(name)
      if (!img) return
      const [l, t, r, b] = crop ?? [0, 0, 0, 0]
      const kw = 1 - l - r; const kh = 1 - t - b
      // a negative crop means a margin: shrink the destination instead of sampling outside the picture
      const sl = Math.max(0, l); const st = Math.max(0, t); const sr = Math.max(0, r); const sb = Math.max(0, b)
      pen.g.drawImage(img, sl * img.width, st * img.height, (1 - sl - sr) * img.width, (1 - st - sb) * img.height,
        x + (sl - l) / kw * w, y + (st - t) / kh * h, (1 - sl - sr) / kw * w, (1 - st - sb) / kh * h)
    }

    // ---------- elements ----------
    function textColour (shot, e, c) {
      if (shot.opt.text === 'keep' || luminance(c) < 190) return c
      if (e.fill && luminance(e.fill) < 190) return c
      const cx = e.x + e.w / 2; const cy = e.y + e.h / 2
      for (let i = shot.items.indexOf(e) - 1; i >= 0; i--) {
        const u = shot.items[i]
        if (cx < u.x || cx > u.x + u.w || cy < u.y || cy > u.y + u.h) continue
        if (u.k === 'box' && u.fill && u.fill.length === 7) return luminance(u.fill) < 190 ? c : C.ink
        if (u.k === 'img') return data.images[u.src].lum < 130 ? c : C.ink
      }
      return C.ink
    }
    function paragraphs (shot, e) {
      if (!e.rows) {
        const [l, t, r, b] = e.pad
        e.rows = []
        for (const para of e.paras) {
          const size = para.runs[0]?.size ?? 40
          let row = { align: para.align, size, runs: [], w: 0 }
          for (const run of para.runs) {
            for (const token of run.s.match(/\S+|\s+/g) ?? []) {
              const tw = D.textWidth(token, run.size)
              if (row.w + tw > e.w - l - r + 8 && row.runs.length && token.trim()) {
                e.rows.push(row)
                row = { align: para.align, size, runs: [], w: 0 }
              }
              if (!row.runs.length && !token.trim()) continue
              row.runs.push({ s: token, size: run.size, c: run.c, w: tw })
              row.w += tw
            }
          }
          e.rows.push(row)
        }
        e.textHeight = e.rows.reduce((sum, row) => sum + row.size * 1.46, 0)
        e.top = e.anchor === 'ctr' ? (e.h - e.textHeight) / 2 : e.anchor === 'b' ? e.h - b - e.textHeight : t
      }
      let y = e.top
      for (const row of e.rows) {
        const free = e.w - e.pad[0] - e.pad[2] - row.w
        let x = e.pad[0] + (row.align === 'ctr' ? free / 2 : row.align === 'r' ? free : 0)
        for (const run of row.runs) {
          if (run.s.trim()) D.text(run.s, x, y + row.size * 0.73, run.size, textColour(shot, e, run.c), 'left')
          x += run.w
        }
        y += row.size * 1.46
      }
    }
    function pad8 (hex, factor) {
      const a = hex.length > 7 ? parseInt(hex.slice(7), 16) : 255
      return hex.slice(0, 7) + Math.round(a * factor).toString(16).padStart(2, '0')
    }
    function inner (shot, e, w, h, t) {
      // zoom and scroll happen inside the picture's frame
      let k = 1; let ox = 0.5; let oy = 0.5; let shift = 0; let scrolled = 0
      for (const a of shot.acts) {
        if (a.item !== e) continue
        if (a.verb === 'zoom') {
          const p = io(span(t, a.at, 0.7))
          k = lerp(k, a.v[2], p)
          ox = lerp(ox, clamp((a.v[0] * CELL - e.x) / e.w), p)
          oy = lerp(oy, clamp((a.v[1] * CELL - e.y) / e.h), p)
        } else if (a.verb === 'scroll') {
          scrolled = io(span(t, a.at, Math.min(1.4, Math.max(0.3, shot.t1 - a.at))))
          const amount = a.v[0] / 100
          k = Math.max(k, lerp(1, 1 + Math.abs(amount), span(t, shot.t0, 0.5)))
          shift = -amount * (scrolled - 0.5) * h * span(t, shot.t0, 0.5)
        }
      }
      return { k, ox: (ox - 0.5) * w, oy: (oy - 0.5) * h, shift, scrolled }
    }
    function element (shot, e, rect, t, alpha, hover = 0) {
      const { x, y, w, h } = rect
      group({ x: x + w / 2, y: y + h / 2, rot: (e.rot ?? 0) + (rect.rot ?? 0), s: rect.s ?? 1, sx: (rect.sx ?? 1) * (e.fx ? -1 : 1), alpha }, () => {
        const l = -w / 2; const top = -h / 2
        let ringed = false
        const radius = e.oval ? Math.min(w, h) / 2 : e.r * w / e.w
        if (e.k === 'line') {
          const line = e.line
          const a = [l, e.fy ? -top : top]; const b = [-l, e.fy ? top : -top]
          D.stroke([a, b], line.c, line.w, out(span(t, shot.t0 + 0.2, 0.4)))
          if (line.tail) D.arrowHead([a, b], line.c, line.w, 44, span(t, shot.t0 + 0.5, 0.15))
          if (line.head) D.arrowHead([b, a], line.c, line.w, 44, span(t, shot.t0 + 0.3, 0.15))
          return
        }
        if (e.k === 'img') {
          const info = data.images[e.src]
          const card = e.card || (info.solid > 0.97 && (e.r || e.shadow || e.oval || e.framed || w > 330)) && (e.alpha ?? 1) > 0.95
          const barH = e.bar ? FilmLive.BAR * w / e.w : 0
          if (card || e.bar) D.shadow(l, top - barH, w, h + barH, radius, 0.85 + 0.4 * hover)
          if (e.bar) live.bar(shot, l, top, w, w / e.w, t)
          if (e.plate) D.panel(l - 36, top - 36, w + 72, h + 72, 44, C.pink)
          ringed = card && !e.bar
          const body = () => {
            const z = inner(shot, e, w, h, t)
            group({ x: z.ox, y: z.oy + z.shift, s: z.k, alpha: e.alpha ?? 1 }, () => picture(e.src, l - z.ox, top - z.oy, w, h, e.crop))
            if (z.scrolled > 0 && z.scrolled < 1) D.box(-l - 24, top + 30 + (h - 260) * z.scrolled, 12, 200, { r: 6, fill: '#26132e55' })
          }
          if (radius || e.oval || shot.acts.some(a => a.item === e && (a.verb === 'zoom' || a.verb === 'scroll'))) D.clip(l, top, w, h, e.bar ? [0, 0, 32 * w / e.w, 32 * w / e.w] : radius, body)
          else body()
        } else {
          if (e.fill) {
            // full-screen colour washes of the deck become a pale tint
            const wash = e.w > 1800 && e.h > 1000
            if (e.shadow && e.fill.length === 7) D.shadow(l, top, w, h, radius)
            D.box(l, top, w, h, { r: radius, oval: e.oval, fill: wash ? pad8(e.fill, 0.14) : e.fill })
          }
          if (e.k === 'text') group({ x: l, y: top, s: w / e.w }, () => paragraphs(shot, e))
        }
        if (e.line) {
          if (e.oval) D.stroke(D.ringPoints(0, 0, w, h), e.line.c, Math.max(8, e.line.w), out(span(t, shot.t0 + 0.25, 0.4)))
          else D.box(l, top, w, h, { r: radius, stroke: e.line.c, line: e.line.w })
        }
        if (hover > 0.02 && ringed) D.box(l - 3, top - 3, w + 6, h + 6, { r: radius + 3, stroke: pad8(C.pink, hover * 0.8), line: 5 })
      })
    }

    // how the directed actions move one element
    function moved (shot, e, t) {
      const m = { dx: 0, dy: 0, s: 1, sx: 1, rot: 0 }
      for (const a of shot.acts) {
        if (a.verb === 'shake') {
          const age = t - a.at
          if (age > 0 && age < 0.55) m.dx += 24 * Math.sin(age * 44) * (1 - age / 0.55)
        }
        if (a.item !== e) continue
        if (a.verb === 'drag') {
          const p = io(span(t, a.at, a.len ?? 0.7))
          const home = a.args[4] === 'back' ? back(span(t, a.at + (a.len ?? 0.7) + 0.1, 0.4)) : 0
          m.dx += a.v[2] * CELL * p * (1 - home)
          m.dy += a.v[3] * CELL * p * (1 - home)
          m.rot += 5 * Math.sin(Math.PI * p) * Math.sign(a.v[2] || 1)
        } else if (a.verb === 'spin') {
          const turn = io(span(t, a.at, 0.8))
          const c = Math.cos(turn * Math.PI * 2)
          m.sx *= Math.sign(c || 1) * Math.max(0.05, Math.abs(c))
        } else if (a.verb === 'pop') m.s *= 1 + 0.06 * back(span(t, a.at, 0.3)) * (1 - span(t, a.at + 0.9, 0.3))
      }
      return m
    }

    function enterFrom (shot) {
      const dir = shot.opt.enter ?? ['left', 'up', 'zoom', 'right', 'down'][shot.segment % 5]
      return { left: [1, 0], right: [-1, 0], up: [0, 1], down: [0, -1], zoom: [0, 0] }[dir] ?? [1, 0]
    }

    function slide (shot, t, { morph = true, pointerAt = null } = {}) {
      const age = t - shot.t0
      const from = morph && !shot.first && !shot.prev.opt.scene && !shot.prev.opt.say && age < MORPH ? shot.prev : null
      const p = from ? io(clamp(age / MORPH)) : 1
      const matched = new Map()
      if (from) {
        const left = new Set(from.items)
        for (const e of shot.items) {
          for (const u of left) {
            if (u.k !== e.k) continue
            const same = e.k === 'img'
              ? u.src === e.src
              : e.k === 'text'
                ? JSON.stringify(u.paras) === JSON.stringify(e.paras)
                : Math.abs(u.x - e.x) + Math.abs(u.y - e.y) < 40
            if (same) { matched.set(e, u); left.delete(u); break }
          }
        }
      }
      const a = from?.view ?? shot.view; const b = shot.view
      const view = { x: lerp(a.x, b.x, p), y: lerp(a.y, b.y, p), s: lerp(a.s, b.s, p) }
      group({ x: view.x, y: view.y, s: view.s * (1 + 0.022 * span(t, shot.segT0, shot.segT1 - shot.segT0)) }, () => group({ x: -W / 2, y: -H / 2 }, () => {
        if (from) {
          const stay = new Set(matched.values())
          for (const u of from.items) if (!stay.has(u)) element(from, u, { x: u.x, y: u.y, w: u.w, h: u.h, s: lerp(1, 0.94, p) }, t, 1 - p)
        }
        let top = null
        if (pointerAt) top = itemAt(shot, W / 2 + (pointerAt[0] - view.x) / view.s, H / 2 + (pointerAt[1] - view.y) / view.s)
        const drawItems = () => shot.items.forEach((e, i) => {
          const u = matched.get(e)
          const start = shot.t0 + Math.min(i * 0.05, (shot.t1 - shot.t0) * 0.35)
          const inP = u ? 1 : back(span(t, start, shot.first ? 0.46 : 0.32))
          const m = moved(shot, e, t)
          const depth = e.framed ? 0.4 : 0.6 + Math.min(i, 5) * 0.35
          const tiltX = pointerAt ? (pointerAt[0] - W / 2) / W : 0
          const tiltY = pointerAt ? (pointerAt[1] - H / 2) / H : 0
          const float = Math.sin(t * 1.6 + i * 1.3) * 5 * Math.min(1, depth)
          const sweep = (t - shot.t0 - 0.55) % 2.4
          const lift = shot.items.length >= 3 && !e.back && e.w < 1500 && sweep > 0 ? bump(sweep * 7 - i, 1.1) : 0
          const lit = pointerAt && e === top && e.k === 'img' ? span(t, shot.t0 + 0.45, 0.25) : 0
          const base = u ? { x: lerp(u.x, e.x, p), y: lerp(u.y, e.y, p), w: lerp(u.w, e.w, p), h: lerp(u.h, e.h, p) } : e
          element(shot, e, {
            x: base.x + m.dx - tiltX * 26 * depth,
            y: base.y + m.dy - 30 * lift - tiltY * 20 * depth + float + (u ? 0 : 50 * (1 - inP)),
            w: base.w,
            h: base.h,
            s: m.s * lerp(0.9, 1, inP) * (1 + 0.012 * lit),
            sx: m.sx,
            rot: m.rot + tiltX * 0.9 + lift * 2
          }, t, u ? 1 : span(t, start, 0.16), lit)
        })
        // trim=1: tall pictures end with the slide, the captions keep the light ground
        if (shot.opt.trim) D.clip(-600, -600, W + 1200, H + 560, 0, drawItems)
        else drawItems()
      }))
    }

    // ---------- kinetic text ----------
    function say (shot, t, pointerAt) {
      if (!shot.sayRows) {
        let marked = false
        const rows = shot.opt.say.split('/').map(row => row.trim().split(/\s+/).map(token => {
          if (token.startsWith('*')) marked = true
          const word = { s: token.replace(/\*/g, ''), hl: marked }
          if (token.endsWith('*')) marked = false
          return word
        }))
        let size = [0, 168, 148, 122, 104][Math.min(4, rows.length)]
        const widest = Math.max(...rows.map(r => D.textWidth(r.map(w => w.s).join(' '), size)))
        if (widest > 1660) size = Math.floor(size * 1660 / widest)
        let spokenAt = shot.t0 - 0.6; let last = shot.t0 - 0.02; let hlAt = null
        const lh = size * 1.34
        rows.forEach((row, r) => {
          let x = W / 2 - D.textWidth(row.map(w => w.s).join(' '), size) / 2
          for (const word of row) {
            const key = norm(word.s)
            const hit = key && words.find(w => w.a >= spokenAt && w.a < shot.t1 - 0.1 && w.w === key)
            word.at = Math.min(shot.t0 + Math.max(0.4, (shot.t1 - shot.t0) * 0.65), hit ? Math.max(last, hit.a - 0.06) : last + 0.09)
            if (hit) spokenAt = hit.a + 0.01
            last = word.at
            word.x = x
            word.y = STAGE.y - (rows.length - 1) * lh / 2 + r * lh
            word.w = D.textWidth(word.s, size)
            if (word.hl && hlAt === null) hlAt = word.at
            x += word.w + D.textWidth(' ', size)
          }
        })
        const marks = rows.map(row => {
          const list = row.filter(w => w.hl)
          if (!list.length) return null
          const end = list[list.length - 1]
          return { x: list[0].x - size * 0.16, y: list[0].y - size * 0.64, w: end.x + end.w - list[0].x + size * 0.32, h: size * 1.28, at: hlAt + 0.22 }
        }).filter(Boolean)
        shot.sayRows = { rows, size, marks }
      }
      const { rows, size, marks } = shot.sayRows
      for (const m of marks) {
        const grow = io(span(t, m.at - 0.14, 0.3))
        const fill = span(t, m.at + 0.2, 0.12)
        if (fill < 1 && grow > 0) {
          D.box(m.x, m.y, m.w * grow, m.h, { r: 6, stroke: C.cyan, line: 5 })
          for (const [hx, hy] of [[m.x, m.y], [m.x + m.w * grow, m.y], [m.x, m.y + m.h], [m.x + m.w * grow, m.y + m.h]]) D.box(hx - 11, hy - 11, 22, 22, { r: 4, fill: C.white, stroke: C.cyan, line: 5 })
        }
        if (fill > 0) {
          group({ x: m.x + m.w / 2, y: m.y + m.h / 2, s: lerp(0.92, 1, back(fill)), alpha: fill }, () => D.box(-m.w / 2, -m.h / 2, m.w, m.h, { r: size * 0.2, fill: C.pink }))
        }
      }
      for (const word of rows.flat()) {
        const white = word.hl && marks.length && t >= marks[0].at + 0.2
        let x = word.x
        for (const [k, ch] of [...word.s].entries()) {
          const w = D.textWidth(word.s.slice(0, word.s.indexOf(ch, k) + ch.length), size) - (x - word.x)
          const p = span(t, word.at + k * 0.022, 0.28)
          if (p > 0) {
            const cx = x + w / 2
            const near = pointerAt ? bump(cx - pointerAt[0], 110) * bump(word.y - pointerAt[1], 120) : 0   // letters shy away from the pointer
            group({ x: cx, y: word.y + 56 * (1 - back(p)) - 7 * near, s: lerp(0.6, 1, back(p)) * (1 + 0.1 * near), rot: 12 * (1 - back(p)), alpha: clamp(p * 3) },
              () => D.text(ch, 0, 0, size, white ? C.white : C.ink))
          }
          x += w
        }
      }
    }

    // ---------- actions drawn over a shot ----------
    function overlays (shot, t) {
      for (const a of shot.acts) {
        const age = t - a.at
        if (age < -0.02) continue
        const [x, y, p, q] = a.v
        const here = () => cell(shot, x, y)
        const unit = CELL * shot.view.s
        switch (a.verb) {
          case 'ring': {
            const at = here()
            D.stroke(D.ringPoints(at[0], at[1], p * unit, q * unit), C.pink, 11, out(span(t, a.at, 0.4)))
            break
          }
          case 'box': case 'select': {
            const at = here(); const s = io(span(t, a.at, 0.32))
            const w = p * unit * s; const h = q * unit * s
            const color = a.verb === 'box' ? C.pink : C.cyan
            D.box(at[0], at[1], w, h, { r: a.verb === 'box' ? 18 : 4, stroke: color, line: a.verb === 'box' ? 9 : 5 })
            if (a.verb === 'select') for (const [hx, hy] of [[at[0], at[1]], [at[0] + w, at[1]], [at[0], at[1] + h], [at[0] + w, at[1] + h]]) D.box(hx - 11, hy - 11, 22, 22, { r: 4, fill: C.white, stroke: color, line: 5 })
            break
          }
          case 'under': case 'strike': case 'arrow': {
            const from = here(); const to = cell(shot, p, q)
            const pts = D.arcPoints(...from, ...to, a.verb === 'arrow' ? 0.18 : 0.015)
            const color = a.verb === 'strike' ? C.red : C.pink
            D.stroke(pts, color, a.verb === 'arrow' ? 12 : 14, out(span(t, a.at, 0.32)))
            if (a.verb === 'arrow') D.arrowHead(pts, color, 12, 46, span(t, a.at + 0.3, 0.14))
            break
          }
          case 'lens': {
            const e = a.item
            if (!e) break
            const at = here(); const k = a.v[3] || 1.8; const r = p * CELL
            const show = back(span(t, a.at, 0.3))
            group({ x: at[0] + 18 * Math.sin(age * 2.4), y: at[1] + 10 * Math.cos(age * 1.9), s: show * shot.view.s }, () => {
              D.shadow(-r, -r, r * 2, r * 2, r)
              D.clip(-r, -r, r * 2, r * 2, r, () => {
                D.box(-r, -r, r * 2, r * 2, { fill: C.white })
                group({ s: k }, () => picture(e.src, e.x - x * CELL, e.y - y * CELL, e.w, e.h, e.crop))
              })
              D.dot(0, 0, r, null, C.white, 14)
              D.stroke([[r * 0.74, r * 0.74], [r * 1.12, r * 1.12]], C.pink, 30)
            })
            break
          }
          case 'burst': D.burst(...here(), age, C.pink, 1.6); break
          case 'confetti': D.confetti(...here(), age); break
          case 'tag': {
            const at = here(); const colour = COLORS[a.args.slice(2).join(' ').length % 4]
            D.pill(a.args.slice(2).join(' '), at[0], at[1], { fill: colour, color: C.white, size: 34, scale: back(span(t, a.at, 0.3)), rot: -3 })
            break
          }
          case 'chips': {
            const list = a.words.split('~')
            const size = list.length > 4 ? 26 : 30
            const w = list.map(s => D.textWidth(s, size) + size * 2.9)
            let left = W / 2 - (w.reduce((m, v) => m + v, 0) + 22 * (list.length - 1)) / 2
            const active = Math.min(list.length - 1, Math.floor(age / Math.max(0.35, (shot.t1 - a.at) / list.length)))
            list.forEach((label, i) => {
              const on = i === active && age > 0.25
              D.pill(label, left + w[i] / 2, 872, { size, fill: on ? C.pink : C.white, color: on ? C.white : C.ink, dotColor: on ? C.white : COLORS[i % 6], scale: back(span(t, a.at + i * 0.1, 0.3)) })
              left += w[i] + 22
            })
            break
          }
          case 'toggle': {
            const w = D.textWidth(a.words, 32) + 250
            group({ x: 960, y: 868, s: back(span(t, a.at - 0.02, 0.28)) }, () => {
              D.panel(-w / 2, -50, w, 100, 50)
              D.text(a.words, -70, 0, 32)
              D.toggle(w / 2 - 92, 0, io(span(t, a.at + 0.1, 0.22)))
            })
            break
          }
          case 'slider': {
            const [from, to] = a.words.split('~')
            group({ x: 960, y: 868, s: back(span(t, a.at - 0.02, 0.28)) }, () => {
              const side = Math.max(D.textWidth(from, 27), D.textWidth(to, 27))
              const half = 260 + 60 + side + 40
              D.panel(-half, -50, half * 2, 100, 50)
              const v = io(span(t, a.at, 0.7))
              D.text(from, -320 - side / 2, 0, 27, C.mute)
              D.text(to, 320 + side / 2, 0, 27, C.pink)
              D.box(-260, -8, 520, 16, { r: 8, fill: '#f3e8f3' })
              D.box(-260, -8, Math.max(1, 520 * v), 16, { r: 8, fill: C.cyan })
              D.dot(-260 + 520 * v, 0, 28, C.white, C.cyan, 10)
            })
            break
          }
          case 'swatches': {
            const list = a.words.split(',')
            const active = Math.min(list.length - 1, Math.floor(age / Math.max(0.3, (shot.t1 - a.at) / list.length)))
            group({ x: 960, y: 866, s: back(span(t, a.at, 0.3)) }, () => {
              const w = list.length * 104 + 40
              D.panel(-w / 2, -58, w, 116, 58)
              list.forEach((color, i) => {
                const cx = -w / 2 + 72 + i * 104
                D.dot(cx, 0, 36 * back(span(t, a.at + i * 0.06, 0.25)), color)
                if (i === active) D.dot(cx, 0, 45, null, C.ink, 6)
              })
            })
            break
          }
          case 'toast': {
            const p1 = back(span(t, a.at, 0.36))
            D.pill(a.words, 960, lerp(-70, 78, p1), { size: 34, fill: C.white, dotColor: C.pink })
            break
          }
          case 'type': {
            const all = a.words; const n = Math.round(span(t, a.at, Math.min(1.1, shot.t1 - a.at - 0.1)) * all.length)
            const w = D.textWidth(all, 34) + 170
            group({ x: 960, y: 868, s: back(span(t, a.at - 0.02, 0.28)) }, () => {
              D.panel(-w / 2, -50, w, 100, 50)
              D.dot(-w / 2 + 56, 0, 14, C.pink)
              D.text(all.slice(0, n), -w / 2 + 92, 0, 34, C.ink, 'left')
              D.box(-w / 2 + 96 + D.textWidth(all.slice(0, n), 34), -26, 4, 52, { fill: C.pink })
            })
            break
          }
          case 'count': {
            const value = Math.round(lerp(x, y, out(span(t, a.at, Math.min(1, shot.t1 - a.at)))))
            D.pill(`${value}${a.args.slice(2).join(' ')}`, 960, 866, { size: 44, fill: C.pink, color: C.white, scale: back(span(t, a.at, 0.3)) })
          }
        }
      }
    }
    function sidePanel (shot, t) {
      const [title, ...chips] = shot.opt.panel.split('~')
      const rows = D.wrap(title, 48, 420)
      const h = 110 + rows.length * 64 + chips.length * 92
      group({ x: 1595, y: STAGE.y, s: back(span(t, shot.t0 + 0.15, 0.4)) }, () => {
        D.panel(-255, -h / 2, 510, h, 44)
        let y = -h / 2 + 82
        for (const row of rows) {
          D.text(row, 0, y, 48)
          y += 64
        }
        chips.forEach((label, i) => {
          const at = shot.t0 + 0.55 + i * Math.min(0.9, (shot.t1 - shot.t0 - 0.6) / chips.length)
          const on = io(span(t, at, 0.2))
          D.box(-205, y - 8, 410, 72, { r: 36, fill: on > 0.5 ? '#fde3ec' : '#f7f0f8' })
          if (on > 0) D.check(-160, y + 28, 22, on)
          else D.dot(-160, y + 28, 22, C.white)
          D.text(label, 26, y + 28, 27)
          y += 92
        })
      })
    }

    function content (shot, t, options = {}) {
      const scene = shot.opt.scene && scenes[shot.opt.scene]
      if (scene) {
        scene(api, {
          shot, t, age: t - shot.t0, left: shot.t1 - t, opt: shot.opt, pointer: options.pointerAt,
          slide: () => slide(shot, t, options),
          at: (word, fallback) => wordTime(shot, word, false) ?? shot.t0 + fallback
        })
      } else if (shot.opt.say) say(shot, t, options.pointerAt)
      else slide(shot, t, options)
    }

    function shotAt (t) {
      let a = 0; let b = shots.length - 1
      while (a < b) {
        const m = (a + b + 1) >> 1
        if (shots[m].t0 <= t) a = m
        else b = m - 1
      }
      return shots[a]
    }
    const lastClick = (t, within) => {
      const list = []
      for (let i = before(clicks, t) - 1; i >= 0 && t - clicks[i].t < within; i--) list.push(clicks[i])
      return list
    }

    function foreground (t) {
      const shot = shotAt(t)
      const at = pointer(t)
      const cut = !shot.cont && (shot.first || shot.opt.scene || shot.opt.say || shot.prev?.opt.scene || shot.prev?.opt.say)
      const old = cut && shot.prev && t - shot.t0 < PUSH ? shot.prev : null
      const wipe = shot.acts.find(a => a.verb === 'wipe')
      const p = old ? io(clamp((t - shot.t0) / PUSH)) : 1
      const [dx, dy] = shot.first && !shot.cont ? enterFrom(shot) : [0, 0]
      const still = dx === 0 && dy === 0
      live.sides(shot, t, at)
      if (old) {
        group({
          x: 960 - dx * 1920 * p, y: STAGE.y - dy * 1100 * p,
          s: lerp(1, still ? 1.22 : 0.9, p), rot: -2.5 * dx * p, alpha: 1 - (still ? clamp(p * 2) : p * p)
        }, () => group({ x: -960, y: -STAGE.y }, () => {
          content(old, t, { morph: false })
          if (old.opt.panel) sidePanel(old, t)
          overlays(old, t)
        }))
      }
      group({
        x: 960 + dx * 1920 * (1 - p), y: STAGE.y + dy * 1100 * (1 - p),
        s: lerp(still ? 0.8 : 0.9, 1, p), rot: 2.5 * dx * (1 - p), alpha: old ? (still ? clamp(p * 2 - 0.7) : clamp(p * 1.7)) : 1
      }, () => group({ x: -960, y: -STAGE.y }, () => {
        if (wipe && shot.prev && !old) {
          const w = io(span(t, wipe.at, Math.min(0.75, shot.t1 - wipe.at)))
          const edge = lerp(shot.view.x - 960 * shot.view.s, shot.view.x + 960 * shot.view.s, w)
          if (w < 1) content(shot.prev, t, { morph: false, pointerAt: at })
          if (w > 0) D.clip(-40, -40, (w < 1 ? edge : W + 40) + 40, H + 80, 0, () => content(shot, t, { morph: false, pointerAt: at }))
          if (w > 0 && w < 1) {
            D.box(edge - 4, 70, 8, 808, { r: 4, fill: C.white })
            D.dot(edge, STAGE.y, 44, C.white, C.pink, 8)
          }
        } else content(shot, t, { pointerAt: at })
        if (shot.opt.panel) sidePanel(shot, t)
        overlays(shot, t)
      }))
      live.team(shot, t)
      let press = 0
      for (const c of lastClick(t + 0.12, 0.7)) {
        D.burst(c.x, c.y, t - c.t)
        press = Math.max(press, bump(t - c.t, 0.06))
      }
      if (holds.some(([a, b]) => t >= a && t <= b)) press = 1
      // the opening ends without a pointer: it fades in after the hand-over
      group({ x: at[0], y: at[1], alpha: span(t, shots[0].t0 + 0.6, 0.3) }, () => D.cursor(0, 0, 1 - 0.2 * press))
    }

    // ---------- the living ground (drawn once per frame, it needs no motion blur) ----------
    const ground = new OffscreenCanvas(W, H)
    const gg = ground.getContext('2d')
    const BLOBS = [['255,196,222', 250, 200, 720, 0], ['176,232,244', 1700, 250, 700, 2], ['255,226,160', 1500, 980, 650, 4], ['214,200,255', 420, 1000, 700, 5.5]]
    function background (t) {
      gg.globalAlpha = 1
      gg.fillStyle = C.paper
      gg.fillRect(0, 0, W, H)
      for (const [rgb, x, y, r, phase] of BLOBS) {
        const bx = x + 130 * Math.sin(t * 0.8 + phase); const by = y + 90 * Math.cos(t * 0.65 + phase)
        const grad = gg.createRadialGradient(bx, by, 0, bx, by, r)
        grad.addColorStop(0, `rgba(${rgb},.85)`); grad.addColorStop(0.55, `rgba(${rgb},.3)`); grad.addColorStop(1, `rgba(${rgb},0)`)
        gg.fillStyle = grad
        gg.fillRect(0, 0, W, H)
      }
      const p = pointer(t)
      const waves = lastClick(t, 0.8)
      gg.beginPath()
      const lit = []
      for (let gx = 24; gx < W; gx += 48) {
        for (let gy = 24; gy < H; gy += 48) {
          let dx = gx - p[0]; let dy = gy - p[1]; let dist = Math.hypot(dx, dy) || 1
          let hot = dist < 520 ? bump(dist, 190) : 0
          let x = gx + dx / dist * 30 * hot; let y = gy + dy / dist * 30 * hot
          for (const w of waves) {
            dx = gx - w.x; dy = gy - w.y; dist = Math.hypot(dx, dy) || 1
            const age = t - w.t
            const ring = bump(dist - age * 1100, 70) * (1 - age / 0.8)
            x += dx / dist * 22 * ring; y += dy / dist * 22 * ring
            hot = Math.max(hot, ring)
          }
          if (hot > 0.03) lit.push([x, y, hot])
          else { gg.moveTo(x + 2.6, y); gg.arc(x, y, 2.6, 0, 7) }
        }
      }
      gg.fillStyle = 'rgba(150,115,165,.2)'
      gg.fill()
      for (const [x, y, hot] of lit) {
        gg.fillStyle = `rgba(${lerp(150, 240, hot)},${lerp(115, 51, hot)},${lerp(165, 123, hot)},${0.2 + 0.55 * hot})`
        gg.beginPath(); gg.arc(x, y, 2.6 + 3.4 * hot, 0, 7); gg.fill()
      }
      scenes.ground?.(api, { g: gg, t, width: W, height: H, picture: name => pictures.get(name) })
    }

    // ---------- frame, motion blur, encoder ----------
    const layer = new OffscreenCanvas(W, H)
    const lg = layer.getContext('2d')
    const sum = new OffscreenCanvas(W, H)
    const sg = sum.getContext('2d', { colorType: 'float16' })
    pen.g = lg

    function dryPass (t) {
      pen.dry = true
      pen.points = []
      lg.save()
      lg.setTransform(1, 0, 0, 1, 0, 0)
      foreground(t)
      lg.restore()
      pen.dry = false
      return pen.points
    }
    function sampleCount (t) {
      const a = dryPass(t - 0.25 / FPS); const b = dryPass(t + 0.25 / FPS)
      if (a.length !== b.length) return 16
      let far = 0
      for (let i = 0; i < a.length; i += 2) {
        const x = b[i]; const y = b[i + 1]
        if (x < -300 || x > W + 300 || y < -300 || y > H + 300) continue
        far = Math.max(far, Math.abs(a[i] - x) + Math.abs(a[i + 1] - y))
      }
      return clamp(Math.ceil(far / 2.5), 1, 56)   // neighbouring samples at most 2.5 px apart
    }
    function frame (f) {
      const t = f / FPS
      background(t)
      const count = sampleCount(t)
      for (let k = 0; k < count; k++) {
        const time = t + (count > 1 ? ((k + 0.5) / count - 0.5) / 2 / FPS : 0)
        lg.setTransform(1, 0, 0, 1, 0, 0)
        lg.globalAlpha = 1
        lg.drawImage(ground, 0, 0)
        foreground(time)
        sg.globalAlpha = 1 / (k + 1)
        sg.drawImage(layer, 0, 0)
      }
    }
    const around = (from, to) => shots.filter(s => {
      const next = shots[s.index + 1]
      return (s.at < to && s.at + s.f > from) || (next && next.at < to && next.at + next.f > from)
    })
    const base64 = async blob => {
      const url = await new Promise(resolve => {
        const reader = new FileReader()
        reader.onload = () => resolve(reader.result)
        reader.readAsDataURL(blob)
      })
      return url.slice(url.indexOf(',') + 1)
    }

    let job = null
    async function encode (from, to, state) {
      await decodeFor(around(from, to))
      const encoder = new VideoEncoder({
        output: chunk => {
          const bytes = new Uint8Array(chunk.byteLength)
          chunk.copyTo(bytes)
          state.parts.push(bytes)
          state.size += bytes.length
          if (state.size > 4e6) state.wake?.()
        },
        error: e => { state.error = String(e); state.wake?.() }
      })
      encoder.configure({
        codec: 'avc1.640032', width: W, height: H, framerate: FPS, bitrate: 22e6, bitrateMode: 'variable',
        latencyMode: 'quality', hardwareAcceleration: 'prefer-hardware', avc: { format: 'annexb' }
      })
      for (let f = from; f < to && !state.error; f++) {
        frame(f)
        const image = new VideoFrame(sum, { timestamp: Math.round((f - from) * 1e6 / FPS) })
        encoder.encode(image, { keyFrame: (f - from) % 15 === 0 })   // short GOP: the editor seeks quickly
        image.close()
        while (encoder.encodeQueueSize > 4) await new Promise(resolve => encoder.addEventListener('dequeue', resolve, { once: true }))
      }
      await encoder.flush()
      encoder.close()
    }

    const api = { ...D, picture, pictures, shots, byNumber, data, stage: STAGE, colors: COLORS, pointer }

    return {
      ready: (async () => {
        const face = new FontFace('Poppins', `url("${font}")`, { weight: '700' })
        await face.load()
        document.fonts.add(face)
      })(),
      clips () {
        const list = []
        for (const s of shots) {
          if (s.first) list.push({ name: `s${String(s.n).padStart(3, '0')}`, n: s.n, from: s.at, to: s.at + s.f })
          else list[list.length - 1].to = s.at + s.f
        }
        return list
      },
      startClip (from, to) {
        const state = { parts: [], size: 0, done: false, error: null, wake: null }
        job = state
        encode(from, to, state).catch(e => { state.error = String(e.stack ?? e) }).finally(() => { state.done = true; state.wake?.() })
      },
      async takeChunk () {
        const state = job
        if (!state.done && state.size < 4e6) await new Promise(resolve => { state.wake = resolve })
        state.wake = null
        if (state.error) throw new Error(state.error)
        const done = state.done   // before the await: chunks that arrive during it need another round
        const parts = state.parts.splice(0)
        state.size = 0
        return { data: parts.length ? await base64(new Blob(parts)) : '', done }
      },
      async still (f, width = W) {
        await decodeFor(around(f, f + 1))
        frame(f)
        const small = new OffscreenCanvas(width, Math.round(width * H / W))
        const g = small.getContext('2d')
        g.imageSmoothingQuality = 'high'
        g.drawImage(sum, 0, 0, small.width, small.height)
        return base64(await small.convertToBlob({ type: 'image/jpeg', quality: 0.92 }))
      },
      stills: () => shots.map(s => ({ n: s.n, name: `s${String(s.n).padStart(3, '0')}`, frame: Math.round(s.at + Math.max(s.f * 0.72, Math.min(s.f - 1, 17))) })),
      check: () => [...problems],
      cues () {
        const list = clicks.filter(c => !c.auto).map(c => ({ t: c.t, sound: c.sound ?? 'click' }))
        for (const s of shots) for (const a of s.acts) if (SOUND[a.verb] && SOUND[a.verb] !== 'click') list.push({ t: a.at, sound: SOUND[a.verb] })
        return list.sort((a, b) => a.t - b.t)
      }
    }
  }

  const FilmKit = { create, extraPictures: null }
  window.FilmKit = FilmKit
})()
