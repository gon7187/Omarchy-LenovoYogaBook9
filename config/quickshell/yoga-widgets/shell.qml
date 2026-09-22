// Desktop widgets for the Yoga Book 9: clock, weather, calendar and machine
// stats, stacked down the right edge of the upper panel (eDP-1).
//
// The surface sits on the bottom layer with an empty input mask, so it draws
// over the wallpaper, below every window, and never steals a click.
// Hyprland blurs it through the yoga-widgets layer rule (hypr/yoga-widgets.lua).
//
// Type and colour follow the Omarchy shell: the family is the fontconfig
// alias `monospace` that `omarchy font set` rewrites, sizes derive from the
// [font] base-size in shell.toml the way Style.qml derives the bar's, and every
// colour is a role from the active theme's colors.toml (all 24 stock themes
// define the ones used here). Both files are watched, so a theme or font change
// lands without a restart.
// CPU/RAM/temperature sampling mirrors the gon7187.sysstats bar plugin.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "material.js" as Material

ShellRoot {
  id: root

  // eDP-1 is the upper panel; the lower one belongs to yoga-panel.
  readonly property string monitorName: "eDP-1"
  readonly property string uiFont: "monospace"
  readonly property string emojiFont: "Noto Color Emoji"
  readonly property int cardWidth: 320

  // ---- type ----------------------------------------------------------------
  property int fontBase: 12
  // The widgets follow the Omarchy font size, but the screen does not grow
  // with it: at base-size 11 the stack outgrew the panel by 35px and the panel
  // cut the limits card in half, and a six-week month with four limit rows is
  // ~100px worse. `shrink` steps the widgets' own base down until the stack
  // fits. It only ever grows, and starts over when the font size changes, so it
  // cannot flip between two sizes.
  property int shrink: 0
  readonly property int widgetBase: Math.max(8, fontBase - shrink)
  function px(mult) { return Math.max(1, Math.round(root.widgetBase * mult)) }

  // Parsing hangs off `loaded`, not off `reload()`: the reload is asynchronous,
  // so reading text() straight after it returns the previous contents.
  function applyFontBase() {
    const m = String(shellToml.text() || "").match(/\[font\][^[]*?base-size\s*=\s*(\d+)/)
    if (m && Number(m[1]) !== root.fontBase) { root.fontBase = Number(m[1]); root.shrink = 0 }
  }

  FileView {
    id: shellToml
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.toml"
    blockLoading: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.applyFontBase()
  }

  // ---- theme ---------------------------------------------------------------
  property var palette: ({})
  function col(key, fallback) { return root.palette[key] ? root.palette[key] : fallback }

  readonly property bool lightMode: String(root.palette["mode"] || "dark") === "light"
  readonly property color rawAccent: col("accent", "#7aa2f7")
  readonly property color rawFg: col("foreground", "#a9b1d6")
  readonly property color surface: col("background", "#1a1b26")

  // Relative luminance and WCAG contrast, used to keep theme colours legible
  // on the card rather than trusting that they were picked for this purpose.
  function channel(v) { return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
  function luminance(c) { return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b) }
  function contrastOf(a, b) {
    const la = luminance(a), lb = luminance(b)
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
  }

  // Guarded: during the first binding pass one side can still be undefined
  // (fg is derived from the same palette these helpers feed).
  function mix(a, b, t) {
    if (!a || !b) return a || b || Qt.rgba(0, 0, 0, 1)
    return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
  }

  // ---- material ------------------------------------------------------------
  // What the wallpaper is doing where the cards sit: brightness, dominant hue
  // and how chromatic it is (bin/yoga-wallpaper-luma). A black or white
  // wallpaper reports chroma 0, which keeps the cards neutral by itself.
  property real wallLuma: 0.15
  property real wallPeak: 0.15
  property real wallHue: 0
  property real wallChroma: 0

  // Everything the card's colour is made of lives in material.js, so
  // test_widget_material.cjs can check the real formulas rather than a copy.
  readonly property var wall: ({ luma: wallLuma, peak: wallPeak, hue: wallHue, chroma: wallChroma })
  readonly property bool lightMaterial: Material.isLight(wall)
  readonly property color pole: lightMaterial ? Qt.rgba(0, 0, 0, 1) : Qt.rgba(1, 1, 1, 1)

  function opaque(c) { return Qt.rgba(c.r, c.g, c.b, 1) }

  readonly property color plate: opaque(Material.plate(wall))
  readonly property real cardAlpha: Material.alphaFor(wall)
  readonly property color cardColor: Qt.rgba(plate.r, plate.g, plate.b, cardAlpha)

  // The hairline is that same tone one step further out, at 38% — a seam
  // between card and wallpaper, not a frame drawn on top of it.
  readonly property color hairlineTone: opaque(Material.hairline(wall))
  readonly property color hairline: Qt.rgba(hairlineTone.r, hairlineTone.g, hairlineTone.b, 0.38)
  readonly property real hairlineWidth: 1
  readonly property real cardRadius: 20

  // The colour the text actually sits on: the card tint laid over the
  // wallpaper's own brightness. Contrast is measured against this, not against
  // the theme background, because the card is translucent.
  readonly property color wallGray: Qt.rgba(wallLuma, wallLuma, wallLuma, 1)
  readonly property color backdrop: mix(wallGray, plate, cardAlpha)
  // The same card over the strip's brightest region: text has to clear both,
  // or a sunset behind the cards eats it.
  readonly property color backdropPeak: mix(Qt.rgba(wallPeak, wallPeak, wallPeak, 1), plate, cardAlpha)
  readonly property color trackColor: lightMaterial ? Qt.rgba(0, 0, 0, 0.12) : Qt.rgba(1, 1, 1, 0.12)

  function worstContrast(c) { return Math.min(root.contrastOf(c, root.backdrop), root.contrastOf(c, root.backdropPeak)) }
  function midContrast(c) { return Math.min(root.contrastOf(c, root.backdrop), root.contrastOf(c, root.backdropPeak)) }

  function enforce(c, target) {
    for (let t = 0; t < 1; t += 0.05) {
      const out = root.mix(c, root.pole, t)
      if (root.worstContrast(out) >= target) return out
    }
    return root.pole
  }

  // On a light material the theme's background colour is the readable one and
  // its foreground is not, so take whichever of the pair stands out; enforce()
  // only steps in when neither does.
  readonly property color rawText: root.worstContrast(rawFg) >= root.worstContrast(surface) ? rawFg : surface
  readonly property color fg: enforce(rawText, 4.5)
  readonly property color fgDim: root.mix(backdrop, fg, 0.78)

  // Theme accents are chosen against a terminal background, not against this
  // card. Blend one towards the text colour until it reads, and leave the
  // colours that already pass untouched.
  function readable(c, target) {
    for (let t = 0; t < 1; t += 0.1) {
      const out = root.mix(c, root.fg, t)
      if (root.midContrast(out) >= target) return out
    }
    return root.fg
  }

  // The accent comes from the wallpaper as well; a near-grey one has no hue to
  // give, and then the theme's own accent stands in.
  readonly property color accent: readable(Material.hasHue(wall) ? opaque(Material.accent(wall)) : rawAccent, 4.0)
  readonly property color warm: readable(col("yellow", "#e0af68"), 3.6)
  readonly property color hot: readable(col("red", "#f7768e"), 3.6)

  // ---- agent limits --------------------------------------------------------
  // bin/yoga-ai-limits does the collecting: Claude Code's OAuth usage endpoint
  // (the one /usage reads) and the rate_limits Codex writes into its own
  // session log. It caches, so a failed poll keeps the last numbers.
  property var limits: null

  Process {
    id: limitsProc
    command: [Quickshell.env("HOME") + "/.local/bin/yoga-ai-limits"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.limits = JSON.parse(String(text || "")) } catch (e) { /* keep the previous reading */ }
      }
    }
  }

  Timer {
    interval: 5 * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!limitsProc.running) limitsProc.running = true
  }

  function windowLabel(minutes) {
    if (!minutes) return ""
    if (minutes % 1440 === 0) return (minutes / 1440) + " дн"
    if (minutes % 60 === 0) return (minutes / 60) + " ч"
    return minutes + " мин"
  }

  function resetLabel(when) {
    if (!when || isNaN(when.getTime())) return ""
    const left = when.getTime() - root.now.getTime()
    if (left <= 0) return "вот-вот"
    if (left < 24 * 3600 * 1000) return Qt.formatDateTime(when, "HH:mm")
    return when.toLocaleDateString(Qt.locale("ru_RU"), "d MMM")
  }

  // Green while there is room, amber past two thirds, red when nearly spent.
  function limitTint(pct) {
    if (pct >= 85) return root.hot
    if (pct >= 66) return root.warm
    return root.accent
  }

  // ---- wallpaper -----------------------------------------------------------
  // The state entry is a symlink, so a file watcher on it does not fire when
  // the wallpaper changes; poll it instead. One call returns everything the
  // cards take from the wallpaper: brightness, hue and how chromatic it is.

  Process {
    id: wallProc
    command: [Quickshell.env("HOME") + "/.local/bin/yoga-wallpaper-luma"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          const probe = JSON.parse(String(text || ""))
          if (isFinite(probe.luma)) root.wallLuma = probe.luma
          if (isFinite(probe.peak)) root.wallPeak = probe.peak
          if (isFinite(probe.hue)) root.wallHue = probe.hue
          if (isFinite(probe.chroma)) root.wallChroma = probe.chroma
        } catch (e) { /* keep the previous reading */ }
      }
    }
  }

  Timer {
    interval: 15000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!wallProc.running) wallProc.running = true
  }

  function capitalize(text) { return text.length ? text[0].toUpperCase() + text.slice(1) : text }

  function applyPalette() {
    const out = {}
    for (const line of String(themeFile.text() || "").split("\n")) {
      const m = line.match(/^\s*(\w+)\s*=\s*"([^"]+)"/)
      if (m) out[m[1]] = m[2]
    }
    if (Object.keys(out).length) root.palette = out
  }

  FileView {
    id: themeFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    blockLoading: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: { root.applyPalette(); if (!wallProc.running) wallProc.running = true }
  }

  // ---- clock ---------------------------------------------------------------
  property date now: new Date()
  // Nothing shows seconds, and every assignment to now re-evaluates the calendar
  // grid and repaints the layer: only publish a new minute.
  Timer {
    interval: 1000; running: true; repeat: true
    onTriggered: { const d = new Date(); if (d.getMinutes() !== root.now.getMinutes() || d.getDate() !== root.now.getDate()) root.now = d }
  }

  // ---- machine stats -------------------------------------------------------
  // Same sources as gon7187.sysstats: /proc for load and memory, hwmon for
  // temperatures. The Iris Xe iGPU exposes no load counter without perf
  // privileges, so its render-clock frequency stands in for utilisation.
  property int cpuPercent: 0
  property real ramUsedGiB: 0
  property real ramTotalGiB: 0
  property real ramFraction: 0
  property int cpuTemp: -1
  property int ssdTemp: -1
  property int gpuMhz: 0
  property int gpuMaxMhz: 1300
  property var fanRpm: []
  property var lastCpu: null
  property var tempFiles: []
  property string gpuActPath: ""

  function sampleCpu() {
    statFile.reload()
    const fields = String(statFile.text() || "").split("\n")[0].trim().split(/\s+/).slice(1).map(Number)
    if (fields.length < 4) return
    const idle = fields[3] + (fields[4] || 0)
    const total = fields.reduce((a, b) => a + b, 0)
    if (root.lastCpu) {
      const dTotal = total - root.lastCpu.total
      const dIdle = idle - root.lastCpu.idle
      if (dTotal > 0) root.cpuPercent = Math.round(100 * (dTotal - dIdle) / dTotal)
    }
    root.lastCpu = { total: total, idle: idle }
  }

  function sampleMem() {
    memFile.reload()
    const values = {}
    for (const line of String(memFile.text() || "").split("\n")) {
      const m = line.match(/^(\w+):\s+(\d+)/)
      if (m) values[m[1]] = Number(m[2])
    }
    if (!values.MemTotal || values.MemAvailable === undefined) return
    root.ramTotalGiB = values.MemTotal / 1048576
    root.ramUsedGiB = (values.MemTotal - values.MemAvailable) / 1048576
    root.ramFraction = 1 - values.MemAvailable / values.MemTotal
  }

  function refreshStats() {
    sampleCpu()
    sampleMem()
    fanFile.reload()
    root.fanRpm = String(fanFile.text() || "").trim().split(/\s+/).map(Number).filter(v => v > 0)
    if (root.gpuActPath) { gpuFile.reload(); root.gpuMhz = Number(String(gpuFile.text() || "0").trim()) || 0 }
    if (root.tempFiles.length && !tempProc.running) tempProc.running = true
  }

  // hwmon numbering and the DRM card index both move between boots; resolve
  // them once by sensor name at startup.
  Process {
    id: resolveProc
    running: true
    command: ["sh", "-c",
      "for h in /sys/class/hwmon/hwmon*; do n=$(cat $h/name 2>/dev/null); for t in $h/temp*_input; do [ -e \"$t\" ] || continue; l=$(cat ${t%_input}_label 2>/dev/null); echo \"$n|$l|$t\"; done; done; " +
      "for g in /sys/class/drm/card*/gt_act_freq_mhz; do [ -e \"$g\" ] && echo \"gpu|act|$g\"; done; " +
      "for g in /sys/class/drm/card*/gt_max_freq_mhz; do [ -e \"$g\" ] && echo \"gpu|max|$(cat $g)\"; done"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        const files = []
        for (const line of String(text || "").split("\n")) {
          const parts = line.split("|")
          const name = parts[0], label = parts[1], path = parts[2]
          if (name === "coretemp" && label === "Package id 0") files.push({ kind: "pkg", path: path })
          else if (name === "coretemp" && /^Core /.test(label)) files.push({ kind: "core", path: path })
          else if (name === "nvme" && label === "Composite") files.push({ kind: "ssd", path: path })
          else if (name === "gpu" && label === "act") root.gpuActPath = path
          else if (name === "gpu" && label === "max") root.gpuMaxMhz = Number(path) || 1300
        }
        root.tempFiles = files
        root.refreshStats()
      }
    }
  }

  Process {
    id: tempProc
    command: ["cat"].concat(root.tempFiles.map(f => f.path))
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        const values = String(text || "").trim().split("\n").map(v => Math.round(Number(v) / 1000))
        let pkg = -1, core = -1, ssd = -1
        root.tempFiles.forEach((f, i) => {
          const v = values[i]
          if (!(v > 0)) return
          if (f.kind === "pkg") pkg = v
          else if (f.kind === "core") core = Math.max(core, v)
          else if (f.kind === "ssd") ssd = v
        })
        root.cpuTemp = pkg >= 0 ? pkg : core
        root.ssdTemp = ssd
      }
    }
  }

  FileView { id: statFile; path: "/proc/stat"; blockLoading: true; printErrors: false }
  FileView { id: memFile; path: "/proc/meminfo"; blockLoading: true; printErrors: false }
  FileView { id: fanFile; path: "/run/yoga-fan"; blockLoading: true; printErrors: false }
  FileView { id: gpuFile; path: root.gpuActPath; blockLoading: true; printErrors: false }

  // Each refresh forks cat and animates every meter for 450 ms; at 2 s that kept
  // Hyprland compositing almost continuously (~1.5 W on battery).
  Timer { interval: 5000; running: true; repeat: true; onTriggered: root.refreshStats() }

  // ---- weather -------------------------------------------------------------
  // Open-Meteo: no key, answers in a fraction of a second. (wttr.in, which the
  // Omarchy bar pill uses, trickles its j1 payload out over a minute or more
  // and regularly times out.) Coordinates come from omarchy's weather.json when
  // it is set, from a cached IP lookup otherwise.
  property var weather: null
  property var forecast: []
  property string weatherPlace: ""

  // WMO weather codes -> emoji and a Russian label.
  function wmoIcon(code, isDay) {
    const c = Number(code)
    if (c >= 95) return "\u26c8\ufe0f"
    if (c >= 85 || (c >= 71 && c <= 77) || c === 56 || c === 57 || c === 66 || c === 67) return "\u2744\ufe0f"
    if (c >= 80 || (c >= 61 && c <= 65) || (c >= 51 && c <= 55)) return "\ud83c\udf27\ufe0f"
    if (c === 45 || c === 48) return "\ud83c\udf2b\ufe0f"
    if (c === 3) return "\u2601\ufe0f"
    if (c === 2) return isDay ? "\u26c5" : "\u2601\ufe0f"
    if (c === 1) return isDay ? "\ud83c\udf24\ufe0f" : "\ud83c\udf19"
    return isDay ? "\u2600\ufe0f" : "\ud83c\udf19"
  }

  function wmoText(code) {
    const map = {
      0: "Ясно", 1: "Малооблачно", 2: "Переменно облачно", 3: "Пасмурно",
      45: "Туман", 48: "Изморозь",
      51: "Слабая морось", 53: "Морось", 55: "Сильная морось",
      56: "Ледяная морось", 57: "Ледяная морось",
      61: "Слабый дождь", 63: "Дождь", 65: "Сильный дождь",
      66: "Ледяной дождь", 67: "Ледяной дождь",
      71: "Слабый снег", 73: "Снег", 75: "Сильный снег", 77: "Снежная крупа",
      80: "Слабый ливень", 81: "Ливень", 82: "Сильный ливень",
      85: "Снегопад", 86: "Сильный снегопад",
      95: "Гроза", 96: "Гроза с градом", 99: "Гроза с градом"
    }
    return map[Number(code)] || "—"
  }

  Process {
    id: weatherProc
    command: ["sh", "-c",
      "cache=\"$HOME/.cache/yoga-widgets\"; mkdir -p \"$cache\"; " +
      "cfg=\"$HOME/.config/omarchy/weather.json\"; " +
      "lat=$(sed -nE 's/.*\"latitude\"[: ]+([-0-9.]+).*/\\1/p' \"$cfg\" 2>/dev/null); " +
      "lon=$(sed -nE 's/.*\"longitude\"[: ]+([-0-9.]+).*/\\1/p' \"$cfg\" 2>/dev/null); " +
      "name=$(sed -nE 's/.*\"name\"[: ]+\"([^\"]*)\".*/\\1/p' \"$cfg\" 2>/dev/null); " +
      "if [ -z \"$lat\" ] || [ -z \"$lon\" ]; then " +
      "  [ -s \"$cache/location.json\" ] || curl -fsS --max-time 10 'http://ip-api.com/json/?fields=status,city,lat,lon&lang=ru' -o \"$cache/location.json\" || true; " +
      "  lat=$(sed -nE 's/.*\"lat\":([-0-9.]+).*/\\1/p' \"$cache/location.json\" 2>/dev/null); " +
      "  lon=$(sed -nE 's/.*\"lon\":([-0-9.]+).*/\\1/p' \"$cache/location.json\" 2>/dev/null); " +
      "  name=$(sed -nE 's/.*\"city\":\"([^\"]*)\".*/\\1/p' \"$cache/location.json\" 2>/dev/null); " +
      "fi; " +
      "if [ -n \"$lat\" ] && [ -n \"$lon\" ]; then " +
      "  curl -fsS --max-time 20 \"https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=7\" -o \"$cache/weather.tmp\" && mv \"$cache/weather.tmp\" \"$cache/weather.json\" || true; " +
      "fi; " +
      "echo \"$name\"; cat \"$cache/weather.json\" 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          const raw = String(text || "")
          const split = raw.indexOf("\n")
          if (split < 0) return
          const data = JSON.parse(raw.slice(split + 1))
          if (!data || !data.current) return
          root.weatherPlace = raw.slice(0, split).trim()
          const cur = data.current
          root.weather = {
            temp: Math.round(cur.temperature_2m),
            feels: Math.round(cur.apparent_temperature),
            code: cur.weather_code,
            isDay: cur.is_day === 1,
            desc: root.wmoText(cur.weather_code),
            wind: Math.round(cur.wind_speed_10m),
            humidity: Math.round(cur.relative_humidity_2m)
          }
          const d = data.daily
          const days = []
          for (let i = 0; i < (d.time || []).length && i < 7; i++)
            days.push({ date: d.time[i], max: Math.round(d.temperature_2m_max[i]), min: Math.round(d.temperature_2m_min[i]), code: d.weather_code[i] })
          root.forecast = days
        } catch (e) {
          // Offline: the previous reading stays on screen.
        }
      }
    }
  }

  Timer {
    interval: 15 * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!weatherProc.running) weatherProc.running = true
  }

  Component.onCompleted: { shellToml.reload(); themeFile.reload() }

  // ---- building blocks -----------------------------------------------------
  component Card: Item {
    id: card
    default property alias content: inner.data
    property int pad: root.px(1.6)
    implicitWidth: root.cardWidth
    implicitHeight: inner.implicitHeight + pad * 2

    // Hyprland blurs this layer (hypr/yoga-widgets.lua), so the tint below sits
    // on a blurred wallpaper rather than a sharp one.
    Rectangle {
      anchors.fill: parent
      radius: root.cardRadius
      color: root.cardColor
      border.width: root.hairlineWidth
      border.color: root.hairline

    }

    ColumnLayout {
      id: inner
      anchors.fill: parent
      anchors.margins: card.pad
      spacing: 10
    }
  }

  component Label: Text {
    color: root.fgDim
    font.family: root.uiFont
    font.pixelSize: root.px(1.1)
    font.letterSpacing: 0.4
    renderType: Text.NativeRendering
  }

  component Meter: ColumnLayout {
    id: meter
    property string label
    property string value
    property real fraction: 0
    property color tint: root.accent
    Layout.fillWidth: true
    spacing: 5

    RowLayout {
      Layout.fillWidth: true
      Label { text: meter.label; font.pixelSize: root.px(1.1) }
      Item { Layout.fillWidth: true }
      Text {
        text: meter.value
        color: root.fg
        font.family: root.uiFont
        font.pixelSize: root.px(1.15)
        font.weight: Font.Medium
        renderType: Text.NativeRendering
      }
    }

    Rectangle {
      Layout.fillWidth: true
      implicitHeight: 6
      radius: 3
      color: root.trackColor
      Rectangle {
        width: parent.width * Math.max(0, Math.min(1, meter.fraction))
        height: parent.height
        radius: parent.radius
        color: meter.tint
        Behavior on width { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
      }
    }
  }

  // ---- surface -------------------------------------------------------------
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      screen: modelData
      visible: modelData.name === root.monitorName

      // Bottom, not Background: Omarchy draws the wallpaper as its own
      // background-level surface, and within one level the surface created
      // last is on top. After a reboot the shell created its wallpaper after
      // the widgets and covered them completely; a theme change or
      // omarchy-restart-shell did the same. Bottom is above every background
      // surface and still below every window, whatever starts first.
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.namespace: "yoga-widgets"
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"

      anchors { top: true; right: true }
      margins { top: root.px(4.0); right: root.px(2.6) }
      implicitWidth: root.cardWidth
      readonly property int room: screen.height - margins.top - root.px(1.2)
      implicitHeight: Math.min(stack.implicitHeight, room)

      // Empty mask: every click falls through to the desktop below.
      mask: Region {}

      // Judged once the layout settles: a size step re-lays the cards one at a
      // time, and the half-updated sum in between read as an overflow (854px at
      // base 10 that settles to ~800) and stepped down a size too far. Only the
      // visible panel votes — Variants builds one per screen.
      Timer {
        id: fitCheck
        interval: 150
        onTriggered: if (panel.visible && stack.implicitHeight > panel.room && root.widgetBase > 8) root.shrink++
      }

      ColumnLayout {
        id: stack
        onImplicitHeightChanged: fitCheck.restart()
        anchors.fill: parent
        spacing: root.px(1.2)

        // Clock ---------------------------------------------------------------
        Card {
          Text {
            text: Qt.formatDateTime(root.now, "HH:mm")
            color: root.fg
            font.family: root.uiFont
            font.pixelSize: root.px(4.4)
            font.weight: Font.Light
            font.letterSpacing: -1
            renderType: Text.NativeRendering
            // -10: the clock's 44px glyphs hang ~12px of empty space above
            // their box, which put the ink 22.5px below the card edge.
            Layout.topMargin: -10
          }
          Label {
            text: root.capitalize(root.now.toLocaleDateString(Qt.locale("ru_RU"), "dddd, d MMMM"))
            font.pixelSize: root.px(1.15)
            color: root.accent
            Layout.topMargin: -6
          }
        }

        // Weather -------------------------------------------------------------
        Card {
          RowLayout {
            Layout.fillWidth: true
            // Same overhang correction as the clock, for the 26px temperature.
            Layout.topMargin: -4
            spacing: 14

            Text {
              text: root.weather ? root.wmoIcon(root.weather.code, root.weather.isDay) : "…"
              font.family: root.emojiFont
              font.pixelSize: root.px(3.2)
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 2
              Text {
                text: root.weather ? (root.weather.temp > 0 ? "+" : "") + root.weather.temp + "°" : "--"
                color: root.fg
                font.family: root.uiFont
                font.pixelSize: root.px(2.6)
                font.weight: Font.Light
                renderType: Text.NativeRendering
              }
              Label {
                Layout.fillWidth: true
                text: root.weather ? root.weather.desc : "загрузка"
                color: root.fg
                elide: Text.ElideRight
              }
              Label {
                Layout.fillWidth: true
                text: root.weatherPlace
                visible: root.weatherPlace.length > 0
                font.pixelSize: root.px(1.0)
                elide: Text.ElideRight
              }
            }

            // Feels-like, wind and humidity ride in the empty space beside the
            // temperature rather than on a line of their own: three short right
            // aligned rows cost no height at all.
            ColumnLayout {
              Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
              spacing: 2
              visible: !!root.weather
              Label {
                Layout.alignment: Qt.AlignRight
                text: root.weather ? "ощущается " + (root.weather.feels > 0 ? "+" : "") + root.weather.feels + "°" : ""
                font.pixelSize: root.px(0.95)
              }
              Label {
                Layout.alignment: Qt.AlignRight
                text: root.weather ? root.weather.wind + " км/ч" : ""
                font.pixelSize: root.px(0.95)
              }
              Label {
                Layout.alignment: Qt.AlignRight
                text: root.weather ? root.weather.humidity + "%" : ""
                font.pixelSize: root.px(0.95)
              }
            }
          }

          Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: root.hairline
            visible: root.forecast.length > 0
          }

          RowLayout {
            id: fcRow
            // A layout nested in the card keeps its own content width unless it
            // is told otherwise — fillWidth alone left the week bunched on the
            // left — and its columns then need an explicit share each, or the
            // spare width goes into the gaps between them instead.
            Layout.fillWidth: true
            Layout.preferredWidth: parent ? parent.width : 0
            Layout.bottomMargin: -2
            spacing: root.px(0.8)
            visible: root.forecast.length > 0
            Repeater {
              model: root.forecast
              ColumnLayout {
                id: fc
                required property var modelData
                required property int index
                Layout.fillWidth: true
                Layout.preferredWidth: root.forecast.length
                  ? (fcRow.width - fcRow.spacing * (root.forecast.length - 1)) / root.forecast.length
                  : 0
                spacing: 2
                Label {
                  Layout.alignment: Qt.AlignHCenter
                  font.pixelSize: root.px(0.95)
                  color: fc.index === 0 ? root.accent : root.fgDim
                  text: new Date(fc.modelData.date).toLocaleDateString(Qt.locale("ru_RU"), "ddd")
                }
                Text {
                  Layout.alignment: Qt.AlignHCenter
                  text: root.wmoIcon(fc.modelData.code, true)
                  font.family: root.emojiFont
                  font.pixelSize: root.px(1.4)
                }
                Text {
                  Layout.alignment: Qt.AlignHCenter
                  text: fc.modelData.max + "°"
                  color: root.fg
                  font.family: root.uiFont
                  font.pixelSize: root.px(1.0)
                  renderType: Text.NativeRendering
                }
                Text {
                  Layout.alignment: Qt.AlignHCenter
                  text: fc.modelData.min + "°"
                  color: root.fgDim
                  font.family: root.uiFont
                  font.pixelSize: root.px(0.95)
                  renderType: Text.NativeRendering
                }
              }
            }
          }
        }

        // Calendar ------------------------------------------------------------
        Card {
          id: calCard
          // Monday-first grid of the current month, padded to whole weeks.
          function cells() {
            const d = root.now
            const first = new Date(d.getFullYear(), d.getMonth(), 1)
            const lead = (first.getDay() + 6) % 7
            const days = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate()
            const out = []
            for (let i = 0; i < lead; i++) out.push(0)
            for (let i = 1; i <= days; i++) out.push(i)
            while (out.length % 7) out.push(0)
            return out
          }

          Label {
            text: root.capitalize(Qt.locale("ru_RU").standaloneMonthName(root.now.getMonth())) + " " + root.now.getFullYear()
            font.pixelSize: root.px(1.2)
            color: root.fg
          }

          GridLayout {
            Layout.fillWidth: true
            // The last row of dates keeps ~5px of empty cell below its digits;
            // without this the calendar looked bottom-heavy next to the others.
            Layout.bottomMargin: -5
            columns: 7
            columnSpacing: 0
            rowSpacing: 3

            Repeater {
              model: ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
              Label {
                id: dow
                required property var modelData
                required property int index
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: root.px(0.95)
                text: dow.modelData
                color: dow.index > 4 ? root.hot : root.fgDim
              }
            }

            Repeater {
              model: calCard.cells()
              Item {
                id: day
                required property var modelData
                required property int index
                Layout.fillWidth: true
                implicitHeight: root.px(2.3)
                readonly property bool today: modelData === root.now.getDate()
                readonly property bool weekend: (index % 7) > 4

                Rectangle {
                  anchors.centerIn: parent
                  width: root.px(2.2)
                  height: root.px(2.2)
                  radius: width / 2
                  visible: day.today
                  color: root.accent
                }
                Text {
                  anchors.centerIn: parent
                  text: day.modelData > 0 ? day.modelData : ""
                  font.family: root.uiFont
                  font.pixelSize: root.px(1.1)
                  font.weight: day.today ? Font.DemiBold : Font.Normal
                  renderType: Text.NativeRendering
                  color: day.today ? root.backdrop : (day.weekend ? root.hot : root.fg)
                }
              }
            }
          }
        }

        // Machine -------------------------------------------------------------
        Card {
          Meter {
            label: "CPU"
            value: root.cpuPercent + "%"
            fraction: root.cpuPercent / 100
            tint: root.accent
          }
          Meter {
            label: "RAM"
            value: root.ramUsedGiB.toFixed(1) + " / " + root.ramTotalGiB.toFixed(1) + " ГиБ"
            fraction: root.ramFraction
            tint: root.accent
          }
          Meter {
            // Iris Xe has no load counter without perf privileges; the render
            // clock is the honest stand-in.
            label: "GPU"
            value: root.gpuMhz > 0 ? root.gpuMhz + " МГц" : "простой"
            fraction: root.gpuMhz / root.gpuMaxMhz
            tint: root.accent
          }

          RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            Label {
              text: root.cpuTemp > 0 ? "темп " + root.cpuTemp + "°" : ""
              font.pixelSize: root.px(1.0)
              color: root.cpuTemp >= 85 ? root.hot : (root.cpuTemp >= 70 ? root.warm : root.fgDim)
            }
            Label {
              text: root.ssdTemp > 0 ? "SSD " + root.ssdTemp + "°" : ""
              font.pixelSize: root.px(1.0)
            }
            Item { Layout.fillWidth: true }
            Label {
              text: root.fanRpm.length ? root.fanRpm.join(" / ") + " об/мин" : ""
              font.pixelSize: root.px(1.0)
            }
          }
        }
        // Agent limits ---------------------------------------------------------
        Card {
          visible: root.limits && (root.limits.claude || root.limits.codex)

          Meter {
            visible: !!(root.limits && root.limits.claude && root.limits.claude.five_hour)
            label: "Claude 5 ч"
            value: root.limits && root.limits.claude && root.limits.claude.five_hour
              ? root.limits.claude.five_hour.pct + "%  ·  " + root.resetLabel(new Date(root.limits.claude.five_hour.resets))
              : ""
            fraction: root.limits && root.limits.claude && root.limits.claude.five_hour ? root.limits.claude.five_hour.pct / 100 : 0
            tint: root.limitTint(root.limits && root.limits.claude && root.limits.claude.five_hour ? root.limits.claude.five_hour.pct : 0)
          }

          Meter {
            visible: !!(root.limits && root.limits.claude && root.limits.claude.seven_day)
            label: "Claude 7 дн"
            value: root.limits && root.limits.claude && root.limits.claude.seven_day
              ? root.limits.claude.seven_day.pct + "%  ·  " + root.resetLabel(new Date(root.limits.claude.seven_day.resets))
              : ""
            fraction: root.limits && root.limits.claude && root.limits.claude.seven_day ? root.limits.claude.seven_day.pct / 100 : 0
            tint: root.limitTint(root.limits && root.limits.claude && root.limits.claude.seven_day ? root.limits.claude.seven_day.pct : 0)
          }

          Meter {
            visible: !!(root.limits && root.limits.codex && root.limits.codex.primary)
            label: "Codex " + (root.limits && root.limits.codex && root.limits.codex.primary ? root.windowLabel(root.limits.codex.primary.window_minutes) : "")
            value: root.limits && root.limits.codex && root.limits.codex.primary
              ? root.limits.codex.primary.pct + "%  ·  " + root.resetLabel(new Date(root.limits.codex.primary.resets_at * 1000))
              : ""
            fraction: root.limits && root.limits.codex && root.limits.codex.primary ? root.limits.codex.primary.pct / 100 : 0
            tint: root.limitTint(root.limits && root.limits.codex && root.limits.codex.primary ? root.limits.codex.primary.pct : 0)
          }

          Meter {
            visible: !!(root.limits && root.limits.codex && root.limits.codex.secondary)
            label: "Codex " + (root.limits && root.limits.codex && root.limits.codex.secondary ? root.windowLabel(root.limits.codex.secondary.window_minutes) : "")
            value: root.limits && root.limits.codex && root.limits.codex.secondary
              ? root.limits.codex.secondary.pct + "%  ·  " + root.resetLabel(new Date(root.limits.codex.secondary.resets_at * 1000))
              : ""
            fraction: root.limits && root.limits.codex && root.limits.codex.secondary ? root.limits.codex.secondary.pct / 100 : 0
            tint: root.limitTint(root.limits && root.limits.codex && root.limits.codex.secondary ? root.limits.codex.secondary.pct : 0)
          }
        }
      }
    }
  }
}
