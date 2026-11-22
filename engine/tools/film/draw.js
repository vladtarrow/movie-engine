// draw.js — drawing primitives of the film kit.
// Every primitive reports where it is (rec) and draws nothing on a dry pass: the renderer uses two dry passes to
// measure how far things move inside one frame and takes as many motion-blur samples as that needs.
(() => {
  const W = 1920
  const H = 1080
  const C = {
    pink: '#f0337b', ink: '#26132e', cyan: '#18a8d8', violet: '#8a5cf6', orange: '#ff7a2f',
    yellow: '#ffd21f', green: '#22b573', red: '#f03c46', paper: '#fff9fb', white: '#ffffff', mute: '#8f7a95'
  }
  const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v))
  const lerp = (a, b, p) => a + (b - a) * p
  const span = (t, start, len) => clamp((t - start) / len)
  const out = p => 1 - (1 - p) ** 3
  const io = p => (p < 0.5 ? 4 * p ** 3 : 1 - (-2 * p + 2) ** 3 / 2)
  const back = p => 1 + 2.4 * (p - 1) ** 3 + 1.4 * (p - 1) ** 2
  const bump = (x, width) => Math.exp(-((x / width) ** 2))

  const pen = { g: null, dry: false, points: [] }

  function rec (x, y, w = 0, h = 0) {
    if (!pen.dry) return
    const m = pen.g.getTransform()
    for (const [px, py] of [[x, y], [x + w, y + h]]) pen.points.push(m.a * px + m.c * py + m.e, m.b * px + m.d * py + m.f)
  }
  // runs body with a moved, scaled, turned and faded pen (x, y = the new origin)
  function group ({ x = 0, y = 0, s = 1, sx = 1, rot = 0, alpha = 1 }, body) {
    if (alpha <= 0.002 || s <= 0.002) return
    const g = pen.g
    g.save()
    g.translate(x, y)
    if (rot) g.rotate(rot * Math.PI / 180)
    if (s !== 1 || sx !== 1) g.scale(s * sx, s)
    g.globalAlpha *= alpha
    body()
    g.restore()
  }
  function clip (x, y, w, h, radius, body) {
    const g = pen.g
    g.save()
    if (!pen.dry) {
      g.beginPath()
      g.roundRect(x, y, w, h, radius)
      g.clip()
    }
    body()
    g.restore()
  }
  function box (x, y, w, h, { r = 0, fill, stroke, line = 4, oval = false } = {}) {
    if (w <= 0 || h <= 0) return
    rec(x, y, w, h)
    if (pen.dry) return
    const g = pen.g
    g.beginPath()
    if (oval) g.ellipse(x + w / 2, y + h / 2, w / 2, h / 2, 0, 0, Math.PI * 2)
    else g.roundRect(x, y, w, h, Array.isArray(r) ? r : Math.min(r, w / 2, h / 2))
    if (fill) { g.fillStyle = fill; g.fill() }
    if (stroke) { g.strokeStyle = stroke; g.lineWidth = line; g.stroke() }
  }
  function dot (x, y, r, fill, stroke, line = 4) {
    box(x - r, y - r, r * 2, r * 2, { oval: true, fill, stroke, line })
  }
  const font = size => `700 ${size}px Poppins`
  const widths = new Map()
  function textWidth (text, size) {
    const key = `${size}|${text}`
    if (!widths.has(key)) {
      pen.g.save()
      pen.g.font = font(size)
      widths.set(key, pen.g.measureText(text).width)
      pen.g.restore()
    }
    return widths.get(key)
  }
  function text (value, x, y, size, color = C.ink, align = 'center') {
    rec(x, y)
    if (pen.dry) return
    const g = pen.g
    g.font = font(size)
    g.fillStyle = color
    g.textAlign = align
    g.textBaseline = 'middle'
    g.fillText(value, x, y + size * 0.04)
  }
  function wrap (value, size, width) {
    const rows = []
    for (const forced of value.split('/n')) {
      let row = ''
      for (const word of forced.split(' ')) {
        const next = row ? `${row} ${word}` : word
        if (row && textWidth(next, size) > width) { rows.push(row); row = word } else row = next
      }
      rows.push(row)
    }
    return rows
  }
  // a poly-line that draws itself on up to p
  function stroke (points, color, width, p = 1) {
    if (p <= 0 || points.length < 2) return null
    const at = (points.length - 1) * clamp(p)
    const k = Math.floor(at)
    const tip = k >= points.length - 1
      ? points[points.length - 1]
      : [lerp(points[k][0], points[k + 1][0], at - k), lerp(points[k][1], points[k + 1][1], at - k)]
    rec(tip[0], tip[1])
    if (pen.dry) return tip
    const g = pen.g
    g.beginPath()
    g.moveTo(...points[0])
    for (let i = 1; i <= k; i++) g.lineTo(...points[i])
    g.lineTo(...tip)
    g.strokeStyle = color
    g.lineWidth = width
    g.lineCap = 'round'
    g.lineJoin = 'round'
    g.stroke()
    return tip
  }
  function poly (points, fill, edge, line = 4) {
    rec(...points[0])
    if (pen.dry) return
    const g = pen.g
    g.beginPath()
    points.forEach((p, i) => (i ? g.lineTo(...p) : g.moveTo(...p)))
    g.closePath()
    if (fill) { g.fillStyle = fill; g.fill() }
    if (edge) { g.strokeStyle = edge; g.lineWidth = line; g.lineJoin = 'round'; g.stroke() }
  }
  function ringPoints (x, y, w, h) {
    const pts = []
    for (let i = 0; i <= 90; i++) {
      const q = i / 90
      const a = -2.2 + Math.PI * 2 * 1.1 * q
      const wobble = 1 + 0.035 * Math.sin(3 * a + 0.7) + 0.05 * q
      pts.push([x + w / 2 * wobble * Math.cos(a), y + h / 2 * wobble * Math.sin(a)])
    }
    return pts
  }
  function arcPoints (x1, y1, x2, y2, bend = 0.18) {
    const mx = (x1 + x2) / 2 - (y2 - y1) * bend
    const my = (y1 + y2) / 2 + (x2 - x1) * bend
    const pts = []
    for (let i = 0; i <= 36; i++) {
      const q = i / 36; const u = 1 - q
      pts.push([u * u * x1 + 2 * u * q * mx + q * q * x2, u * u * y1 + 2 * u * q * my + q * q * y2])
    }
    return pts
  }
  function arrowHead (points, color, width, len, p) {
    if (p <= 0) return
    const tip = points[points.length - 1]
    const from = points[Math.max(0, points.length - 4)]
    const a = Math.atan2(tip[1] - from[1], tip[0] - from[0])
    for (const d of [2.55, -2.55]) stroke([tip, [tip[0] + len * p * Math.cos(a + d), tip[1] + len * p * Math.sin(a + d)]], color, width)
  }

  // Soft shadows are expensive per sample, so one blurred rounded box is cached and stretched as nine slices.
  let shadowTile = null
  function shadow (x, y, w, h, radius = 28, strength = 1) {
    if (pen.dry || w < 4 || h < 4) return
    const pad = 80; const edge = 96; const size = (pad + edge) * 2 + 8
    if (!shadowTile) {
      shadowTile = new OffscreenCanvas(size, size)
      const s = shadowTile.getContext('2d')
      s.shadowColor = 'rgba(120,50,110,.30)'
      s.shadowBlur = 56
      s.shadowOffsetX = 10000
      s.shadowOffsetY = 18
      s.fillStyle = '#000'
      s.beginPath()
      s.roundRect(pad - 10000, pad, size - pad * 2, size - pad * 2, 48)
      s.fill()
    }
    const k = Math.min(1, w / (edge * 2 + 8), h / (edge * 2 + 8))
    const e = edge * k; const o = pad
    const sx = [0, pad + edge, size - pad - edge, size]
    const dx = [x - o, x + e, x + w - e, x + w + o]
    const dy = [y - o, y + e, y + h - e, y + h + o]
    const g = pen.g
    const was = g.globalAlpha
    g.globalAlpha *= strength
    for (let i = 0; i < 3; i++) {
      for (let j = 0; j < 3; j++) {
        const dw = dx[i + 1] - dx[i]; const dh = dy[j + 1] - dy[j]
        if (dw > 0 && dh > 0) g.drawImage(shadowTile, sx[i], sx[j], sx[i + 1] - sx[i], sx[j + 1] - sx[j], dx[i], dy[j], dw, dh)
      }
    }
    g.globalAlpha = was
  }
  function panel (x, y, w, h, r = 32, fill = C.white) {
    shadow(x, y, w, h, r)
    box(x, y, w, h, { r, fill })
  }
  function pill (value, x, y, { fill = C.white, color = C.ink, size = 32, dotColor, scale = 1, alpha = 1, rot = 0 } = {}) {
    const inner = textWidth(value, size) + (dotColor ? size : 0)
    const w = inner + size * 1.9; const h = size * 2.2
    group({ x, y, s: scale, alpha, rot }, () => {
      panel(-w / 2, -h / 2, w, h, h / 2, fill)
      if (dotColor) dot(-inner / 2 + size * 0.28, 0, size * 0.32, dotColor)
      text(value, dotColor ? size / 2 : 0, 0, size, color)
    })
    return w
  }
  function toggle (x, y, on, scale = 1) {
    group({ x, y, s: scale }, () => {
      box(-60, -34, 120, 68, { r: 34, fill: on > 0.5 ? C.pink : '#e2d5e4' })
      dot(lerp(-27, 27, on), 0, 26, C.white)
    })
  }
  function check (x, y, r, p, fill = C.green) {
    dot(x, y, r * back(clamp(p)), fill)
    stroke([[x - r * 0.45, y], [x - r * 0.1, y + r * 0.38], [x + r * 0.5, y - r * 0.38]], C.white, r * 0.22, p)
  }
  function cursor (x, y, scale = 1, color = C.ink, label = '') {
    group({ x, y, s: scale }, () => {
      poly([[1, 1], [50, 33], [28, 38], [17, 60]], color, C.white, 6)
      if (label) {
        const w = textWidth(label, 25) + 40
        box(36, 46, w, 48, { r: 24, fill: color })
        text(label, 36 + w / 2, 70, 25, C.white)
      }
    })
  }
  function burst (x, y, age, color = C.pink, size = 1) {
    if (age < 0 || age > 0.55) return
    const p = out(age / 0.55)
    group({ x, y, alpha: 1 - age / 0.55, s: size }, () => {
      dot(0, 0, 16 + 80 * p, null, color, 7)
      for (let k = 0; k < 8; k++) {
        const a = k * Math.PI / 4 + 0.35
        const r = 34 + 80 * p
        stroke([[Math.cos(a) * r, Math.sin(a) * r], [Math.cos(a) * (r + 14 + 20 * p), Math.sin(a) * (r + 14 + 20 * p)]], [color, C.yellow, C.cyan, C.violet][k % 4], 8)
      }
    })
  }
  function confetti (x, y, age, count = 26) {
    if (age < 0 || age > 1.3) return
    for (let k = 0; k < count; k++) {
      const a = k * 2.399963
      const speed = 420 + (k * 97) % 520
      group({
        x: x + Math.cos(a) * speed * out(clamp(age / 1.3)),
        y: y + Math.sin(a) * speed * 0.7 * out(clamp(age / 1.3)) + 380 * age * age,
        rot: k * 41 + age * 300,
        alpha: 1 - clamp((age - 0.75) / 0.55)
      }, () => box(-11, -7, 22, 14, { r: 4, fill: [C.pink, C.yellow, C.cyan, C.violet, C.orange, C.green][k % 6] }))
    }
  }
  function lock (x, y, open, scale = 1, color = C.pink) {
    group({ x, y, s: scale }, () => {
      const lift = -34 * open
      group({ x: 38, y: -18 + lift, rot: 26 * open }, () => {
        const pts = [[-76, 26]]
        for (let i = 0; i <= 18; i++) pts.push([-38 - 38 * Math.cos(Math.PI * i / 18), -34 - 38 * Math.sin(Math.PI * i / 18)])
        pts.push([0, 26])
        stroke(pts, color, 22)
      })
      box(-66, -8, 132, 108, { r: 24, fill: color })
      dot(0, 34, 15, C.white)
      box(-6, 38, 12, 32, { r: 6, fill: C.white })
    })
  }

  window.FilmDraw = {
    W, H, C, pen, clamp, lerp, span, out, io, back, bump, rec, group, clip, box, dot, font, textWidth, text, wrap,
    stroke, poly, ringPoints, arcPoints, arrowHead, shadow, panel, pill, toggle, check, cursor, burst, confetti, lock
  }
})()
