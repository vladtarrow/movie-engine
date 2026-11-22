// Hand-written demo data in the shape a project's build-data.py makes (see engine/tools/film/film-kit.js).
// A real project builds this from its storyboard and the word times in voice.json (engine/voice/voice.mjs).
//   fps     frames per second
//   shots   n = shot number used by direction.js, at/f = first frame and length, g = VO line it belongs to,
//           els = storyboard elements in 1920x1080 slide pixels (k: img | text | box | line; text align l | ctr | r)
//   lines   VO lines with word times in seconds: [word, start, end]
//   images  per picture: lum (mean brightness 0-255), solid (no transparency); empty here: no pictures
window.FILM = {
  fps: 30,
  from: 0,
  to: 255,
  shots: [
    {
      n: 1, at: 0, f: 60, g: 1,
      els: [
        { k: 'box', x: 360, y: 240, w: 1200, h: 600, r: 48, fill: '#FFFFFF', line: { c: '#D9D9D9', w: 2 } },
        { k: 'text', x: 420, y: 330, w: 1080, h: 240, anchor: 't', pad: [0, 0, 0, 0],
          paras: [{ align: 'ctr', runs: [{ s: 'Your brand', size: 150, c: '#1B1B2F' }] }] },
        { k: 'text', x: 420, y: 600, w: 1080, h: 120, anchor: 't', pad: [0, 0, 0, 0],
          paras: [{ align: 'ctr', runs: [{ s: 'in one short film', size: 72, c: '#6B6B80' }] }] }
      ]
    },
    { n: 2, at: 60, f: 60, g: 1, els: [] },
    {
      n: 3, at: 120, f: 60, g: 2,
      els: [
        { k: 'box', x: 260, y: 200, w: 640, h: 680, r: 40, fill: '#F2F0FF' },
        { k: 'box', x: 1020, y: 200, w: 640, h: 680, r: 40, fill: '#FFF0F5' },
        { k: 'text', x: 300, y: 470, w: 560, h: 140, anchor: 't', pad: [0, 0, 0, 0],
          paras: [{ align: 'ctr', runs: [{ s: 'Before', size: 110, c: '#1B1B2F' }] }] },
        { k: 'text', x: 1060, y: 470, w: 560, h: 140, anchor: 't', pad: [0, 0, 0, 0],
          paras: [{ align: 'ctr', runs: [{ s: 'After', size: 110, c: '#1B1B2F' }] }] }
      ]
    },
    { n: 4, at: 180, f: 75, g: 2, els: [] }
  ],
  lines: [
    { n: 1, t: 0.2, text: 'Every brand deserves a film that explains it.',
      words: [['Every', 0.3, 0.6], ['brand', 0.6, 1.0], ['deserves', 1.0, 1.5], ['a', 1.5, 1.6], ['film', 1.6, 2.0],
        ['that', 2.1, 2.3], ['explains', 2.3, 2.9], ['it.', 2.9, 3.2]] },
    { n: 2, t: 4.0, text: 'Compare before and after, then count the results.',
      words: [['Compare', 4.1, 4.6], ['before', 4.6, 5.0], ['and', 5.0, 5.2], ['after,', 5.2, 5.7], ['then', 6.0, 6.3],
        ['count', 6.3, 6.8], ['the', 6.8, 6.9], ['results.', 6.9, 7.6]] }
  ],
  parts: [[0, 'Demo']],
  images: {}
}
