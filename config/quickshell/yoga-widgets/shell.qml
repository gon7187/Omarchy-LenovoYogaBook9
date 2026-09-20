// Desktop widgets for the Yoga Book 9: clock, weather, calendar and machine
// stats, stacked down the right edge of the upper panel (eDP-1).
//
// The surface sits on the background layer with an empty input mask, so it
// draws over the wallpaper, below every window, and never steals a click.
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

ShellRoot {
  id: root

  // eDP-1 is the upper panel; the lower one belongs to yoga-panel.
  readonly property string monitorName: "eDP-1"
  readonly property string uiFont: "monospace"
  readonly property string emojiFont: "Noto Color Emoji"
  readonly property int cardWidth: 320

  // ---- type ----------------------------------------------------------------
  property int fontBase: 12
  function px(mult) { return Math.max(1, Math.round(root.fontBase * mult)) }

  // Parsing hangs off `loaded`, not off `reload()`: the reload is asynchronous,
  // so reading text() straight after it returns the previous contents.
  function applyFontBase() {
    const m = String(shellToml.text() || "").match(/\[font\][^[]*?base-size\s*=\s*(\d+)/)
    if (m) root.fontBase = Number(m[1])
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

  // The card is translucent, so its effective background depends on the
  // wallpaper. These two are the extremes it can sit on; a colour that clears
  // its target against both is legible over any wallpaper.
  readonly property real cardAlpha: 0.78
  readonly property color cardOnDark: Qt.rgba(surface.r * cardAlpha, surface.g * cardAlpha, surface.b * cardAlpha, 1)
  readonly property color cardOnLight: Qt.rgba(surface.r * cardAlpha + (1 - cardAlpha), surface.g * cardAlpha + (1 - cardAlpha), surface.b * cardAlpha + (1 - cardAlpha), 1)
  function worstContrast(c) { return Math.min(root.contrastOf(c, root.cardOnDark), root.contrastOf(c, root.cardOnLight)) }

  function mix(a, b, t) { return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1) }

  // A theme's foreground is picked against its own opaque background; on this
  // translucent card it can fall under 4.5:1 (everforest, gruvbox, rose-pine).
  // Push it away from the surface — white on dark themes, black on light ones
  // — until it clears, which keeps the hue and only lifts the contrast.
  function enforce(c, target) {
    const pole = root.lightMode ? Qt.rgba(0, 0, 0, 1) : Qt.rgba(1, 1, 1, 1)
    for (let t = 0; t < 1; t += 0.05) {
      const out = root.mix(c, pole, t)
      if (root.worstContrast(out) >= target) return out
    }
    return pole
  }

  readonly property color fg: enforce(rawFg, 4.5)
  // One dim tone derived from the text colour: `dark_foreground` and `muted`
  // both fall away to near-invisible on some light themes.
  readonly property color fgDim: root.mix(root.cardOnDark, root.fg, 0.8)

  // Theme accents are chosen against a terminal background, not against this
  // card: rose-pine, nord and miasma land near 3:1 or below. Blend such a
  // colour towards the text colour — which always clears the bar — until it
  // reads, and leave colours that already pass untouched.
  function readable(c, target) {
    for (let t = 0; t < 1; t += 0.1) {
      const out = root.mix(c, root.fg, t)
      if (root.worstContrast(out) >= target) return out
    }
    return root.fg
  }

  readonly property color accent: readable(rawAccent, 4.0)
  readonly property color warm: readable(col("yellow", "#e0af68"), 4.0)
  readonly property color hot: readable(col("red", "#f7768e"), 4.0)
  readonly property color cool: readable(col("cyan", "#449dab"), 3.0)
  readonly property color violet: readable(col("magenta", "#ad8ee6"), 3.0)

  // Card chrome: the theme background carries the glass, and the hairlines
  // lighten on dark themes, darken on light ones. 0.85 is the density where
  // the worst stock theme still clears 4.5:1 for body text over any wallpaper
  // — below that, a light wallpaper washes a dark card out completely.
  readonly property color cardColor: Qt.rgba(surface.r, surface.g, surface.b, cardAlpha)
  readonly property color hairline: lightMode ? Qt.rgba(0, 0, 0, 0.13) : Qt.rgba(1, 1, 1, 0.10)
  readonly property color sheen: lightMode ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.07)
  readonly property color trackColor: lightMode ? Qt.rgba(0, 0, 0, 0.10) : Qt.rgba(1, 1, 1, 0.09)

  // ---- glass ---------------------------------------------------------------
  // A layer surface cannot read what is behind it, but these cards sit on the
  // background layer, so what is behind them is the wallpaper. The panel draws
  // it into an off-screen texture at screen size and glass.frag samples it, so
  // the refracted pixels line up with what Hyprland paints below.
  property var glassSource: null
  property real panelOriginX: 0
  property real panelOriginY: 0
  property real screenW: 1
  property real screenH: 1
  readonly property string wallpaperPath: Quickshell.env("HOME") + "/.local/state/omarchy/current/background"
  property int wallpaperRevision: 0
  property real glassPhase: 0

  // The sheen crosses the card and then rests: an idle animation would keep
  // the GPU redrawing four card-sized shaders forever for no one to see.
  SequentialAnimation {
    running: true
    loops: Animation.Infinite
    NumberAnimation { target: root; property: "glassPhase"; from: 0; to: 1; duration: 5200; easing.type: Easing.InOutSine }
    PauseAnimation { duration: 24000 }
  }

  function capitalize(text) { return text.length ? text[0].toUpperCase() + text.slice(1) : text }

  function applyPalette() {
    root.wallpaperRevision++
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
    onLoaded: root.applyPalette()
  }

  // ---- clock ---------------------------------------------------------------
  property date now: new Date()
  Timer { interval: 1000; running: true; repeat: true; onTriggered: root.now = new Date() }

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

  Timer { interval: 2000; running: true; repeat: true; onTriggered: root.refreshStats() }

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
      0: "Ясно", 1: "Малооблачно", 2: "Переменная облачность", 3: "Пасмурно",
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
      "  curl -fsS --max-time 20 \"https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=3\" -o \"$cache/weather.tmp\" && mv \"$cache/weather.tmp\" \"$cache/weather.json\" || true; " +
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
          for (let i = 0; i < (d.time || []).length && i < 3; i++)
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
  component Card: Rectangle {
    id: card
    default property alias content: inner.data
    property int pad: 18
    implicitWidth: root.cardWidth
    implicitHeight: inner.implicitHeight + pad * 2
    radius: 22
    color: root.cardColor
    border.width: 1
    border.color: root.hairline

    // A faint top highlight is what sells the glass; without it the card
    // reads as a flat black box over a blurred wallpaper.
    Rectangle {
      anchors.fill: parent
      radius: parent.radius
      gradient: Gradient {
        GradientStop { position: 0.0; color: root.sheen }
        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.0) }
      }
    }

    // Refracted wallpaper along the rim, over the tint but under the content.
    ShaderEffect {
      anchors.fill: parent
      visible: root.glassSource !== null
      blending: true
      supportsAtlasTextures: false
      fragmentShader: Qt.resolvedUrl("glass.frag.qsb")

      property var src: root.glassSource
      property vector2d size: Qt.vector2d(width, height)
      property vector2d uvOffset: Qt.vector2d((root.panelOriginX + card.x) / root.screenW,
                                              (root.panelOriginY + card.y) / root.screenH)
      property vector2d uvScale: Qt.vector2d(width / root.screenW, height / root.screenH)
      property real radius: card.radius
      property real edge: root.px(2.4)
      property real strength: root.px(2.2)
      property real phase: root.glassPhase
      property real sheen: root.lightMode ? 0.14 : 0.22
      property real rainbow: root.lightMode ? 0.05 : 0.09
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

      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.namespace: "yoga-widgets"
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"

      anchors { top: true; right: true }
      margins { top: 56; right: 28 }
      implicitWidth: root.cardWidth
      implicitHeight: stack.implicitHeight

      // Empty mask: every click falls through to the desktop below.
      mask: Region {}

      // The wallpaper, drawn exactly as Omarchy's background plugin draws it
      // (PreserveAspectCrop at screen size), captured into a texture the cards
      // sample. hideSource keeps it off the screen itself.
      Item {
        id: wallHolder
        width: panel.screen.width
        height: panel.screen.height
        Image {
          id: wallImage
          anchors.fill: parent
          fillMode: Image.PreserveAspectCrop
          cache: false
          asynchronous: true
          source: "file://" + root.wallpaperPath + "?rev=" + root.wallpaperRevision
          onStatusChanged: if (status === Image.Ready) wallTexture.scheduleUpdate()
        }
      }

      ShaderEffectSource {
        id: wallTexture
        sourceItem: wallHolder
        hideSource: true
        live: false
        recursive: false
      }

      Binding { target: root; property: "glassSource"; value: wallTexture }
      Binding { target: root; property: "screenW"; value: panel.screen.width }
      Binding { target: root; property: "screenH"; value: panel.screen.height }
      Binding { target: root; property: "panelOriginX"; value: panel.screen.width - panel.width - panel.margins.right }
      Binding { target: root; property: "panelOriginY"; value: panel.margins.top }

      ColumnLayout {
        id: stack
        anchors.fill: parent
        spacing: 14

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
            Layout.topMargin: -6
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
          }

          Label {
            Layout.fillWidth: true
            text: root.weather
              ? "ощущается " + (root.weather.feels > 0 ? "+" : "") + root.weather.feels + "°  ·  " + root.weather.wind + " км/ч  ·  " + root.weather.humidity + "%"
              : ""
            visible: !!root.weather
            font.pixelSize: root.px(1.0)
          }

          Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: root.hairline
            visible: root.forecast.length > 0
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: root.px(0.8)
            visible: root.forecast.length > 0
            Repeater {
              model: root.forecast
              ColumnLayout {
                id: fc
                required property var modelData
                required property int index
                Layout.fillWidth: true
                spacing: 2
                Label {
                  Layout.alignment: Qt.AlignHCenter
                  font.pixelSize: root.px(1.0)
                  text: fc.index === 0 ? "сегодня" : new Date(fc.modelData.date).toLocaleDateString(Qt.locale("ru_RU"), "ddd")
                }
                Text {
                  Layout.alignment: Qt.AlignHCenter
                  text: root.wmoIcon(fc.modelData.code, true)
                  font.family: root.emojiFont
                  font.pixelSize: root.px(1.5)
                }
                Text {
                  Layout.alignment: Qt.AlignHCenter
                  text: fc.modelData.max + "°/" + fc.modelData.min + "°"
                  color: root.fg
                  font.family: root.uiFont
                  font.pixelSize: root.px(1.0)
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
                  color: day.today ? root.surface : (day.weekend ? root.hot : root.fg)
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
            tint: root.violet
          }
          Meter {
            // Iris Xe has no load counter without perf privileges; the render
            // clock is the honest stand-in.
            label: "GPU"
            value: root.gpuMhz > 0 ? root.gpuMhz + " МГц" : "простой"
            fraction: root.gpuMhz / root.gpuMaxMhz
            tint: root.cool
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
      }
    }
  }
}
