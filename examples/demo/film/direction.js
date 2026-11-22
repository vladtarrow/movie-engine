// Direction of the demo film, one line per shot (syntax: engine/tools/film/film-kit.js).
// Coordinates are those of a 384x216 contact-sheet cell (x 5 = slide pixels). "@word" fires when the voice says it.
window.FILM_DIRECTION = String.raw`
1 | hover 192 108 @brand | tag 300 60 Your brand @deserves | confetti 192 90 @film
2 say=A film that/*explains* it
3 | click 116 108 @before | click 268 108 @after | chips Before~After @after
4 scene=counter | count 0 120 % @count
`
