// The card material, as plain numbers.
//
// Everything here works on {r, g, b} in 0..1 and knows nothing about Qt, so
// test_widget_material.cjs can run the very formulas the widgets use instead of
// a copy of them that drifts. shell.qml wraps the results in Qt.rgba().
//
// The idea in one line: the card is the wallpaper, one shade over — its hue, a
// fraction of its chroma, and a brightness step away from its own — so it sits
// inside the picture instead of cutting a hole in it.
.pragma library

function rgb(r, g, b) { return { r: r, g: g, b: b } }

// HSL to RGB, the CSS formula.
function hsl(hue, saturation, lightness) {
  const h = ((hue % 360) + 360) % 360 / 30
  const a = saturation * Math.min(lightness, 1 - lightness)
  function channel(n) {
    const k = (n + h) % 12
    return lightness - a * Math.max(-1, Math.min(k - 3, Math.min(9 - k, 1)))
  }
  return rgb(channel(0), channel(8), channel(4))
}

function mix(a, b, t) {
  return rgb(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
}

function linear(v) { return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
function luminance(c) { return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b) }

function contrast(a, b) {
  const la = luminance(a), lb = luminance(b)
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
}

// The wallpaper's hue at a given lightness, with its chroma scaled down. A
// black or white wallpaper reports chroma 0, so this yields a neutral grey and
// no theme needs special-casing.
function tone(wall, lightness, satScale) {
  return hsl(wall.hue, Math.min(0.85, wall.chroma * satScale), lightness)
}

// The median says whether the strip is a dark or a light place to sit; the peak
// still gets a third of the vote, so a wallpaper whose bright half is exactly
// behind the cards does not get a dark plate laid over a glare.
function isLight(wall) { return wall.luma * 0.67 + wall.peak * 0.33 > 0.5 }

function plate(wall) {
  const lightness = isLight(wall) ? Math.min(0.94, wall.luma + 0.12) : Math.max(0.06, wall.luma - 0.08)
  return tone(wall, lightness, 0.45)
}

// One step further out than the plate, so the line reads as the seam between
// card and wallpaper rather than a frame drawn on top of it.
function hairline(wall) {
  const lightness = isLight(wall) ? Math.min(0.94, wall.luma + 0.12) : Math.max(0.06, wall.luma - 0.08)
  return tone(wall, isLight(wall) ? lightness - 0.18 : lightness + 0.22, 0.35)
}

// The accent comes from the wallpaper too, a step more saturated than the plate
// so it still reads as a highlight. Below 0.12 chroma the wallpaper has no hue
// to give and the caller keeps the theme's own accent.
function hasHue(wall) { return wall.chroma >= 0.12 }
function accent(wall) {
  return hsl(wall.hue, Math.min(0.80, wall.chroma * 1.3), isLight(wall) ? 0.34 : 0.68)
}

// What the text actually sits on: the plate laid over the wallpaper, both where
// the wallpaper is typical and where it glares.
function backdrop(wall, alpha) { return mix(rgb(wall.luma, wall.luma, wall.luma), plate(wall), alpha) }
function backdropPeak(wall, alpha) { return mix(rgb(wall.peak, wall.peak, wall.peak), plate(wall), alpha) }

function pole(wall) { return isLight(wall) ? rgb(0, 0, 0) : rgb(1, 1, 1) }

// The alpha is a floor, not a fixed value: behind one card a picture can swing
// from near-black to a sunset, and over a half-lit plate no text colour reaches
// 4.5:1. The plate thickens until the extreme text colour clears 5:1, leaving
// enforce() room to keep some of the theme's own hue. On a calm wallpaper the
// floor already passes and nothing moves, which is what keeps the cards quiet.
var ALPHA_FLOOR = 0.52
var ALPHA_CEILING = 0.76

function alphaFor(wall) {
  const extreme = pole(wall)
  for (let a = ALPHA_FLOOR; a < ALPHA_CEILING; a += 0.04) {
    if (Math.min(contrast(extreme, backdrop(wall, a)), contrast(extreme, backdropPeak(wall, a))) >= 5.0) return a
  }
  return ALPHA_CEILING
}
