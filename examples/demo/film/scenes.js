// Shots built from scratch. A scene draws on the stage (y up to 925): name -> (api, context) => void,
// context = { shot, t, age, left, at(word, fallback), opt }. api has the drawing helpers of engine/tools/film/draw.js.
(() => {
  const scenes = {}

  // a bar chart that grows when the voice says "results"
  scenes.counter = (api, { t, at }) => {
    const { C } = api
    const start = at('results', 1.2)   // absolute seconds, like t
    api.text('Results', 960, 230, 96, C.ink)
    const bars = [0.35, 0.55, 0.8, 1]
    bars.forEach((v, i) => {
      const p = api.back(api.span(t, start + i * 0.12, 0.45))
      const h = 420 * v * p
      api.box(660 + i * 170, 820 - h, 120, h, { r: 18, fill: api.colors[i % api.colors.length] })
    })
  }

  window.FILM_SCENES = scenes
})()
