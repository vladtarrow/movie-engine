// live.js — the living interface around the content of a film-kit shot: browser windows, side widgets that react
// to the spoken words, and teammates' named pointers. Everything is a pure function of time, like the kit.
(() => {
  const D = window.FilmDraw
  const { W, C, clamp, lerp, span, out, io, back, bump, group } = D
  const BAR = 60              // browser bar, in slide pixels
  const COLORS = [C.pink, C.cyan, C.violet, C.orange, C.yellow, C.green]
  const TEAM = [['UI designer', C.violet], ['Art director', C.cyan], ['Motion designer', C.orange], ['Copywriter', C.green]]

  // state: how many word beats have passed, p: 0..1 since the last beat, look: the pointer
  const WIDGETS = {
    type (t, state) {
      D.panel(-82, -82, 164, 164, 28)
      group({ y: -6, rot: 3 * Math.sin(t * 2), sx: [1, 0.8, 1.15, 0.9][state % 4] }, () => D.text('Aa', 0, 0, 76, [C.ink, C.pink, C.violet, C.cyan][state % 4]))
    },
    swatches (t, state) {
      D.panel(-82, -82, 164, 164, 28)
      for (let i = 0; i < 4; i++) {
        const x = i % 2 ? 34 : -34; const y = i < 2 ? -34 : 34
        D.dot(x, y, 24, COLORS[i])
        if (state % 4 === i) D.dot(x, y, 31, null, C.ink, 5)
      }
    },
    toggle (t, state, p) {
      D.panel(-82, -82, 164, 164, 28)
      D.text('Motion', 0, -36, 25)
      D.toggle(0, 26, state % 2 ? p : 1 - p, 0.85)
    },
    sliders (t, state, p) {
      D.panel(-82, -82, 164, 164, 28)
      for (let i = 0; i < 3; i++) {
        const value = k => 0.5 + 0.45 * Math.sin(k * 1.9 + i * 2)
        const v = lerp(value(state - 1), value(state), p); const y = -42 + i * 42
        D.box(-58, y - 5, 116, 10, { r: 5, fill: '#f3e8f3' })
        D.box(-58, y - 5, Math.max(1, 116 * v), 10, { r: 5, fill: COLORS[i] })
        D.dot(-58 + 116 * v, y, 14, C.white, COLORS[i], 6)
      }
    },
    grid (t, state, p) {
      D.panel(-82, -82, 164, 164, 28)
      for (let i = 0; i < 4; i++) {
        const on = state % 4 === i ? p : 0
        group({ x: (i % 2 ? 32 : -32) + on * (i % 2 ? 16 : -16), y: (i < 2 ? -32 : 32) - on * 10, rot: on * 12 }, () => D.box(-27, -27, 54, 54, { r: 12, fill: COLORS[i] }))
      }
    },
    doodle (t, state, p) {
      group({ rot: -4 + 2 * Math.sin(t * 1.7) }, () => {
        D.panel(-82, -82, 164, 164, 10, '#fff3c4')
        if (state % 3 === 0) {
          D.stroke(D.ringPoints(0, 4, 96, 88), C.orange, 8, p)
          D.stroke(D.arcPoints(-24, 16, 24, 16, 0.4), C.ink, 7, p)
        } else if (state % 3 === 1) {
          const star = []
          for (let i = 0; i <= 10; i++) {
            const r = i % 2 ? 24 : 58; const a = i * Math.PI / 5 - Math.PI / 2
            star.push([Math.cos(a) * r, 4 + Math.sin(a) * r])
          }
          D.stroke(star, C.pink, 8, p)
        } else {
          const curve = D.arcPoints(-54, 36, 52, -26, 0.3)
          D.stroke(curve, C.violet, 8, p)
          D.arrowHead(curve, C.violet, 8, 22, p)
        }
      })
    },
    cube (t, state, p) {
      const a = t * 0.8 + (state + p) * 0.7
      const top = []; const low = []
      for (let i = 0; i < 4; i++) {
        const x = Math.cos(a + i * Math.PI / 2) * 72; const y = Math.sin(a + i * Math.PI / 2) * 30
        top.push([x, y - 50]); low.push([x, y + 40])
      }
      const sides = [0, 1, 2, 3].sort((i, j) => (top[i][1] + top[(i + 1) % 4][1]) - (top[j][1] + top[(j + 1) % 4][1]))
      for (const i of sides) D.poly([top[i], top[(i + 1) % 4], low[(i + 1) % 4], low[i]], COLORS[i], C.white, 4)
      D.poly(top, C.yellow, C.white, 4)
    },
    dial (t, state, p) {
      D.panel(-82, -82, 164, 164, 82)
      for (let i = 0; i < 8; i++) D.dot(Math.cos(i * Math.PI / 4) * 64, Math.sin(i * Math.PI / 4) * 64, 5, i === state % 8 ? C.pink : '#e2d5e4')
      group({ rot: (state - 1 + p) * 45 }, () => {
        D.dot(0, 0, 46, C.violet)
        D.box(6, -5, 34, 10, { r: 5, fill: C.white })
      })
    },
    palette (t, state, p) {
      for (let i = 0; i < 5; i++) {
        const on = state % 5 === i ? p : 0
        group({ y: 44, rot: (i - 2) * 22 + 3 * Math.sin(t * 2 + i) }, () => D.box(-25, -136 - 22 * on, 50, 120, { r: 16, fill: COLORS[i], stroke: C.white, line: 4 }))
      }
    },
    eye (t, state, p, look, at) {
      const blink = 1 - bump(p - 0.5, 0.18)
      const a = Math.atan2(look[1] - at[1], look[0] - at[0])
      D.panel(-82, -82, 164, 164, 82, state % 2 ? C.cyan : C.violet)
      if (blink < 0.12) D.box(-54, -4, 108, 8, { r: 4, fill: C.ink })
      else {
        D.box(-54, -54 * blink, 108, 108 * blink, { oval: true, fill: C.white })
        D.dot(Math.cos(a) * 22, Math.sin(a) * 22 * blink, 24 * blink, C.ink)
      }
    },
    blob (t, state) {
      const points = []
      for (let i = 0; i < 40; i++) {
        const a = i * Math.PI / 20
        const r = 70 + 12 * Math.sin(3 * a + t * 3) + 6 * Math.cos(5 * a - t * 2)
        points.push([Math.cos(a) * r, Math.sin(a) * r])
      }
      D.poly(points, COLORS[state % 6])
    },
    ball (t, state) {
      const hop = Math.abs(Math.sin(t * 3.2))
      D.box(-60, 70, 120, 10, { r: 5, fill: '#ecd8e8' })
      group({ y: 24 - hop * 90, rot: t * 120 }, () => {
        D.dot(0, 0, 44, COLORS[state % 6])
        D.box(-34, -6, 68, 12, { r: 6, fill: C.white })
      })
    },
    minimal (t, state, p) {
      D.panel(-82, -82, 164, 164, 28)
      const left = 2 - state % 3
      for (let i = 0; i < 3; i++) {
        const show = i <= left ? 1 : i === left + 1 ? 1 - p : 0
        if (show > 0) D.box(-52, -42 + i * 36, 104 * show, i ? 12 : 22, { r: 8, fill: i ? '#d9cbdd' : C.ink })
      }
    }
  }
  const THEMES = [
    ['swatches', 'toggle'], ['type', 'sliders'], ['grid', 'toggle'], ['doodle', 'type'], ['cube', 'dial'],
    ['palette', 'swatches'], ['eye', 'blob'], ['ball', 'toggle'], ['minimal', 'sliders']
  ]

  function create ({ data, shots, toStage }) {
    const starts = data.parts.map(([at]) => at / data.fps)
    const chapterAt = t => Math.max(0, starts.filter(s => s <= t).length - 1)
    const beats = data.lines.flatMap(line => line.words.filter((w, i) => i % 3 === 1 || /[.!?:]$/.test(w[0])).map(w => w[1]))
    beats.sort((a, b) => a - b)
    function beat (t) {
      let a = 0; let b = beats.length
      while (a < b) {
        const m = (a + b) >> 1
        if (beats[m] <= t) a = m + 1
        else b = m
      }
      return { state: a, p: io(span(t, a ? beats[a - 1] : 0, 0.28)) }
    }

    // room beside the content of every shot
    for (const s of shots) {
      s.chapter = chapterAt(s.t0)
      if (s.opt.scene) {
        s.side = [null, null]
      } else if (s.opt.say) {
        s.side = [{ x: 160, y: 150, s: 0.95 }, { x: W - 160, y: 790, s: 0.95 }]
      } else {
        let left = W; let right = 0
        for (const e of s.items) {
          left = Math.min(left, toStage(s, e.x, 0)[0])
          right = Math.max(right, toStage(s, e.x + e.w, 0)[0])
        }
        const room = [left - 22, W - right - 22]
        s.side = room.map((free, i) => {
          if (free < 118 || (i && s.opt.panel)) return null
          return { x: i ? W - free / 2 - 4 : free / 2 + 4, y: i ? 640 : 280, s: Math.min(1.15, (free - 12) / 185) }
        })
      }
    }

    function sides (shot, t, look) {
      const p = io(span(t, shot.t0, 0.4))
      const { state, p: turn } = beat(t)
      for (let i = 0; i < 2; i++) {
        const b = shot.side[i]
        const a = shot.prev ? shot.prev.side[i] : null
        if (!a && !b) continue
        const from = a ?? { ...b, s: 0 }
        const to = b ?? { ...a, s: 0 }
        const changed = shot.prev && shot.prev.chapter !== shot.chapter
        const size = lerp(from.s, to.s, p) * (changed ? back(p) : 1)
        const at = [lerp(from.x, to.x, p), lerp(from.y, to.y, p)]
        const near = bump(look[0] - at[0], 170) * bump(look[1] - at[1], 170)
        group({
          x: at[0] + (i ? -1 : 1) * 14 * near, y: at[1] + 9 * Math.sin(t * 1.8 + i * 2) - 12 * near,
          s: size * (1 + 0.1 * Math.sin(Math.PI * turn) + 0.1 * near),
          rot: (i ? 5 : -5) + 3 * Math.sin(t * 1.2 + i)
        }, () => WIDGETS[THEMES[shot.chapter][i]](t, state, turn, look, at))
      }
    }

    // a named teammate joins where something is being worked on
    for (const s of shots) {
      s.mate = null
      if (s.opt.scene || s.opt.say || !s.lead || s.t1 - s.t0 < 1.9 || s.items.some(e => e.k === 'text')) continue
      const work = s.acts.some(a => ['drag', 'select', 'ring', 'box', 'under', 'zoom', 'scroll', 'chips', 'slider', 'toggle', 'lens', 'spin', 'swatches'].includes(a.verb))
      if (!work && s.index % 2) continue
      const right = s.index % 2 === 0
      const e = s.lead
      const [x, y] = toStage(s, e.x + e.w * (right ? 0.84 : 0.12), e.y + e.h * (right ? 0.22 : 0.72))
      const [label, color] = TEAM[s.index % TEAM.length]
      s.mate = {
        label, color,
        at: [clamp(x, 40, W - 290), clamp(y, 40, 770)],
        from: [right ? W + 260 : -340, right ? 120 : 840],
        out: Math.max(s.t0 + 1.2, s.t1 - 0.55)
      }
    }
    function team (shot, t) {
      const m = shot.mate
      if (!m) return
      const come = io(span(t, shot.t0 + 0.25, 0.75)); const go = io(span(t, m.out, 0.55))
      if (come <= 0 || go >= 1) return
      const x = lerp(lerp(m.from[0], m.at[0], come), m.from[0], go) + 12 * Math.sin(t * 2.1)
      const y = lerp(lerp(m.from[1], m.at[1], come), m.from[1], go) + 10 * Math.cos(t * 1.7)
      D.cursor(x, y, 1, m.color, m.label)
      D.burst(x, y, t - (shot.t0 + 1.02), m.color, 0.7)
    }

    // the browser bar above a screenshot (l, top, w = the picture's box in the current group)
    function bar (shot, l, top, w, scale, t) {
      const h = BAR * scale
      D.box(l, top - h, w, h + 1, { r: [32 * scale, 32 * scale, 0, 0], fill: C.white })
      for (let i = 0; i < 3; i++) D.dot(l + (42 + i * 34) * scale, top - h / 2, 10 * scale, [C.pink, C.yellow, C.cyan][i])
      const al = l + 170 * scale; const aw = Math.min(w * 0.5, 640 * scale)
      D.box(al, top - h + 14 * scale, aw, 32 * scale, { r: 16 * scale, fill: '#f4ecf5' })
      const load = out(span(t, shot.segT0, 0.8))
      if (load < 1) D.box(l, top - 6 * scale, Math.max(1, w * load), 6 * scale, { r: 3 * scale, fill: C.pink })
    }

    return { sides, team, bar }
  }

  window.FilmLive = { create, BAR }
})()
