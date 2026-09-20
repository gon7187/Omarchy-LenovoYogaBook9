// Desktop widgets for the Yoga Book 9: clock, weather, calendar and machine
// stats, stacked down the right edge of the upper panel (eDP-1).
//
// The surface sits on the background layer with an empty input mask, so it
// draws over the wallpaper, below every window, and never steals a click.
// Hyprland blurs it through the yoga-widgets layer rule (hypr/yoga-widgets.lua).
//
// Colours follow the active Omarchy theme, read straight from its colors.toml.
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
  readonly property string uiFont: "Noto Sans"
  readonly property string emojiFont: "Noto Color Emoji"
  readonly property int cardWidth: 320

  // ---- theme ---------------------------------------------------------------
  property var palette: ({})
  function col(key, fallback) { return root.palette[key] ? root.palette[key] : fallback }
  readonly property color accent: col("accent", "#7aa2f7")
  readonly property color fg: col("bright_foreground", "#e6eaf5")
  readonly property color fgDim: col("dark_foreground", "#8b93b4")
  readonly property color warm: col("yellow", "#e0af68")
  readonly property color hot: col("red", "#f7768e")
  readonly property color cool: col("cyan", "#449dab")
  readonly property color violet: col("magenta", "#ad8ee6")

  function capitalize(text) { return text.length ? text[0].toUpperCase() + text.slice(1) : text }

  function loadPalette() {
    themeFile.reload()
    const out = {}
    for (const line of String(themeFile.text() || "").split("\n")) {
      const m = line.match(/^\s*(\w+)\s*=\s*"(#[0-9a-fA-F]{6})"/)
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
    onFileChanged: root.loadPalette()
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

  Component.onCompleted: root.loadPalette()

  // ---- building blocks -----------------------------------------------------
  component Card: Rectangle {
    id: card
    default property alias content: inner.data
    property int pad: 18
    implicitWidth: root.cardWidth
    implicitHeight: inner.implicitHeight + pad * 2
    radius: 22
    color: Qt.rgba(0, 0, 0, 0.42)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.10)

    // A faint top highlight is what sells the glass; without it the card
    // reads as a flat black box over a blurred wallpaper.
    Rectangle {
      anchors.fill: parent
      radius: parent.radius
      gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.07) }
        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.0) }
      }
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
    font.pixelSize: 12
    font.letterSpacing: 0.6
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
      Label { text: meter.label; font.pixelSize: 12 }
      Item { Layout.fillWidth: true }
      Text {
        text: meter.value
        color: root.fg
        font.family: root.uiFont
        font.pixelSize: 13
        font.weight: Font.Medium
        renderType: Text.NativeRendering
      }
    }

    Rectangle {
      Layout.fillWidth: true
      implicitHeight: 6
      radius: 3
      color: Qt.rgba(1, 1, 1, 0.09)
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
            font.pixelSize: 54
            font.weight: Font.Light
            font.letterSpacing: -1
            renderType: Text.NativeRendering
            Layout.topMargin: -6
          }
          Label {
            text: root.capitalize(root.now.toLocaleDateString(Qt.locale("ru_RU"), "dddd, d MMMM"))
            font.pixelSize: 13
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
              font.pixelSize: 38
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 2
              Text {
                text: root.weather ? (root.weather.temp > 0 ? "+" : "") + root.weather.temp + "°" : "--"
                color: root.fg
                font.family: root.uiFont
                font.pixelSize: 30
                font.weight: Font.Light
                renderType: Text.NativeRendering
              }
              Label {
                Layout.fillWidth: true
                text: root.weather ? root.weather.desc : "загрузка"
                elide: Text.ElideRight
              }
            }
          }

          Label {
            Layout.fillWidth: true
            text: root.weather
              ? (root.weatherPlace ? root.weatherPlace + "   ·   " : "") + "ощущается " + (root.weather.feels > 0 ? "+" : "") + root.weather.feels + "°   ·   " + root.weather.wind + " км/ч   ·   " + root.weather.humidity + "%"
              : ""
            visible: !!root.weather
            font.pixelSize: 11
          }

          Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Qt.rgba(1, 1, 1, 0.08)
            visible: root.forecast.length > 0
          }

          RowLayout {
            Layout.fillWidth: true
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
                  font.pixelSize: 11
                  text: fc.index === 0 ? "сегодня" : new Date(fc.modelData.date).toLocaleDateString(Qt.locale("ru_RU"), "ddd")
                }
                Text {
                  Layout.alignment: Qt.AlignHCenter
                  text: root.wmoIcon(fc.modelData.code, true)
                  font.family: root.emojiFont
                  font.pixelSize: 16
                }
                Text {
                  Layout.alignment: Qt.AlignHCenter
                  text: fc.modelData.max + "° / " + fc.modelData.min + "°"
                  color: root.fg
                  font.family: root.uiFont
                  font.pixelSize: 11
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
            font.pixelSize: 13
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
                font.pixelSize: 10
                text: dow.modelData
                color: dow.index > 4 ? Qt.darker(root.hot, 1.4) : root.fgDim
              }
            }

            Repeater {
              model: calCard.cells()
              Item {
                id: day
                required property var modelData
                required property int index
                Layout.fillWidth: true
                implicitHeight: 24
                readonly property bool today: modelData === root.now.getDate()
                readonly property bool weekend: (index % 7) > 4

                Rectangle {
                  anchors.centerIn: parent
                  width: 24
                  height: 24
                  radius: 12
                  visible: day.today
                  color: root.accent
                }
                Text {
                  anchors.centerIn: parent
                  text: day.modelData > 0 ? day.modelData : ""
                  font.family: root.uiFont
                  font.pixelSize: 12
                  font.weight: day.today ? Font.DemiBold : Font.Normal
                  renderType: Text.NativeRendering
                  color: day.today ? "#000000" : (day.weekend ? Qt.darker(root.hot, 1.2) : root.fg)
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
              font.pixelSize: 11
              color: root.cpuTemp >= 85 ? root.hot : (root.cpuTemp >= 70 ? root.warm : root.fgDim)
            }
            Label {
              text: root.ssdTemp > 0 ? "SSD " + root.ssdTemp + "°" : ""
              font.pixelSize: 11
            }
            Item { Layout.fillWidth: true }
            Label {
              text: root.fanRpm.length ? root.fanRpm.join(" / ") + " об/мин" : ""
              font.pixelSize: 11
            }
          }
        }
      }
    }
  }
}
