#!/usr/bin/env node
// The desktop widgets' card material, checked against real wallpaper readings.
//
// It loads config/quickshell/yoga-widgets/material.js itself — the same file
// shell.qml imports — so the numbers here are the ones the widgets use, not a
// copy that drifts. The readings come from bin/yoga-wallpaper-luma run over the
// stock Omarchy wallpapers.
//
// Two invariants, both of them the brief: the text has to stay readable on any
// wallpaper, and the card has to stay quiet — close enough to the wallpaper's
// own brightness that it sits in the picture instead of cutting a hole in it.
const fs = require('fs')
const path = require('path')

const source = fs.readFileSync(
  path.join(__dirname, '..', 'config', 'quickshell', 'yoga-widgets', 'material.js'), 'utf8')
// `.pragma library` is QML's, not JavaScript's.
const Material = {}
new Function('exports', source.replace(/^\s*\.pragma\s+library\s*$/m, '') +
  '\n;Object.assign(exports, {rgb, hsl, mix, luminance, contrast, tone, isLight, plate, hairline,' +
  ' hasHue, accent, backdrop, backdropPeak, pole, alphaFor, ALPHA_FLOOR, ALPHA_CEILING})')(Material)

// luma / peak / hue / chroma, as bin/yoga-wallpaper-luma reports them.
const WALLPAPERS = [
  ['black',        { luma: 0.0000, peak: 0.0000, hue: 0.0,   chroma: 0.0000 }],
  ['white',        { luma: 1.0000, peak: 1.0000, hue: 0.0,   chroma: 0.0000 }],
  ['pink sunset',  { luma: 0.4863, peak: 0.6902, hue: 354.6, chroma: 0.5506 }],
  ['sunset lake',  { luma: 0.1725, peak: 0.4353, hue: 277.0, chroma: 0.3970 }],
  ['forest',       { luma: 0.2667, peak: 0.5333, hue: 194.1, chroma: 0.0960 }],
  ['pale fade',    { luma: 0.8549, peak: 0.9020, hue: 317.8, chroma: 0.2747 }],
  // Synthetic worst cases: mid-grey is where no text colour has much room, and
  // a wallpaper that is half black and half glare is the widest swing a card
  // can sit on.
  ['mid grey',     { luma: 0.5000, peak: 0.5000, hue: 0.0,   chroma: 0.0000 }],
  ['black to sun', { luma: 0.1000, peak: 0.9500, hue: 40.0,  chroma: 0.6000 }],
]

let failures = 0
function check(label, condition, detail) {
  if (!condition) { failures++; console.log(`FAIL ${label}: ${detail}`) }
}

console.log('wallpaper       alpha  plate    backdrop  text  step')
for (const [name, wall] of WALLPAPERS) {
  const alpha = Material.alphaFor(wall)
  const plate = Material.plate(wall)
  const backdrop = Material.backdrop(wall, alpha)
  const peak = Material.backdropPeak(wall, alpha)
  const pole = Material.pole(wall)
  const text = Math.min(Material.contrast(pole, backdrop), Material.contrast(pole, peak))
  const step = Math.abs(Material.luminance(backdrop) - Material.luminance(Material.rgb(wall.luma, wall.luma, wall.luma)))
  const hex = c => '#' + [c.r, c.g, c.b].map(v => Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16).padStart(2, '0')).join('')
  console.log(`${name.padEnd(15)} ${alpha.toFixed(2)}   ${hex(plate)}  ${hex(backdrop)}   ${text.toFixed(2)}  ${step.toFixed(3)}`)

  // Readable: the extreme text colour clears 4.5:1 both over the typical
  // wallpaper and over its glare. Below that the widgets are decoration.
  check(name, text >= 4.5, `text tops out at ${text.toFixed(2)}:1`)
  // Quiet: the card never sits more than this far from the wallpaper's own
  // brightness. 0.25 is a visible plate; past it the card is a hole.
  check(name, step <= 0.25, `card sits ${step.toFixed(3)} off the wallpaper`)
  // In range, and no NaN from a hue of 0 or a chroma of 0.
  for (const channel of ['r', 'g', 'b']) {
    check(name, plate[channel] >= 0 && plate[channel] <= 1, `plate.${channel} = ${plate[channel]}`)
  }
  check(name, alpha >= Material.ALPHA_FLOOR && alpha <= Material.ALPHA_CEILING, `alpha ${alpha} out of range`)
}

// A flat wallpaper has no hue to lend, and the widgets fall back to the theme.
check('black', !Material.hasHue(WALLPAPERS[0][1]), 'a black wallpaper claims a hue')
check('white', !Material.hasHue(WALLPAPERS[1][1]), 'a white wallpaper claims a hue')
check('pink sunset', Material.hasHue(WALLPAPERS[2][1]), 'a pink sunset lends no hue')
// A black wallpaper is a dark place to sit, a white one a light place.
check('black', !Material.isLight(WALLPAPERS[0][1]), 'black reads as a light place')
check('white', Material.isLight(WALLPAPERS[1][1]), 'white reads as a dark place')
// Chroma 0 must stay grey, or a black wallpaper picks up hue 0 as red.
const grey = Material.plate(WALLPAPERS[0][1])
check('black', grey.r === grey.g && grey.g === grey.b, `plate is not neutral: ${JSON.stringify(grey)}`)

console.log(failures ? `\n${failures} failed` : '\nall good')
process.exit(failures ? 1 : 0)
