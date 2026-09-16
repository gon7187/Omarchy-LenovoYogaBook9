import QtQuick
import Quickshell.Io
import qs.Ui
import qs.Commons

// CPU load, available RAM and temperatures, read from /proc and hwmon every
// few seconds. The Iris Xe iGPU shares the CPU package and has no sensor of
// its own (i915 exposes none), so the package temperature covers it.
// Fan speeds come from /run/yoga-fan (bin/yoga-fan), absent if not installed.
// Click opens btop.
BarWidget {
  id: root
  moduleName: "gon7187.sysstats"

  property int cpuPercent: -1
  property int ramFreePercent: -1
  property real ramAvailableGiB: 0
  property real ramTotalGiB: 0
  property var lastCpu: null
  property int cpuTemp: -1
  property int coreMaxTemp: -1
  property int ssdTemp: -1
  property var fanRpm: []
  // hwmon numbering changes between boots; resolved once by sensor name.
  property var tempFiles: []

  function sampleCpu() {
    statFile.reload()
    const line = statFile.text().split("\n")[0]
    const fields = line.trim().split(/\s+/).slice(1).map(Number)
    if (fields.length < 4) return
    // idle + iowait count as idle time
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
    for (const line of memFile.text().split("\n")) {
      const m = line.match(/^(\w+):\s+(\d+)/)
      if (m) values[m[1]] = Number(m[2])
    }
    if (!values.MemTotal || values.MemAvailable === undefined) return
    root.ramFreePercent = Math.round(100 * values.MemAvailable / values.MemTotal)
    root.ramAvailableGiB = values.MemAvailable / 1048576
    root.ramTotalGiB = values.MemTotal / 1048576
  }

  function refresh() {
    sampleCpu()
    sampleMem()
    fanFile.reload()
    root.fanRpm = fanFile.text().trim().split(/\s+/).map(Number).filter(v => v > 0)
    if (root.tempFiles.length && !tempProc.running) tempProc.running = true
  }

  Process {
    id: resolveProc
    running: true
    command: ["sh", "-c", "for h in /sys/class/hwmon/hwmon*; do n=$(cat $h/name); for t in $h/temp*_input; do [ -e \"$t\" ] || continue; l=$(cat ${t%_input}_label 2>/dev/null); echo \"$n|$l|$t\"; done; done"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        const files = []
        for (const line of String(text || "").split("\n")) {
          const [name, label, path] = line.split("|")
          if (name === "coretemp" && label === "Package id 0") files.push({ kind: "pkg", path: path })
          else if (name === "coretemp" && /^Core /.test(label)) files.push({ kind: "core", path: path })
          else if (name === "nvme" && label === "Composite") files.push({ kind: "ssd", path: path })
        }
        root.tempFiles = files
        root.refresh()
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
        root.coreMaxTemp = core
        root.ssdTemp = ssd
      }
    }
  }

  FileView { id: statFile; path: "/proc/stat"; blockLoading: true; printErrors: false }
  FileView { id: fanFile; path: "/run/yoga-fan"; blockLoading: true; printErrors: false }
  FileView { id: memFile; path: "/proc/meminfo"; blockLoading: true; printErrors: false }

  Timer {
    interval: root.setting("interval", 2) * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    fontSize: Style.font.caption
    horizontalMargin: 6
    // Theme's urgent colour once the package reaches throttling territory.
    active: root.cpuTemp >= root.setting("hotTemp", 90)
    text: root.vertical
      ? (root.cpuPercent < 0 ? "…" : root.cpuPercent + "%") + "\n" + (root.ramFreePercent < 0 ? "…" : root.ramFreePercent + "%")
        + (root.cpuTemp < 0 ? "" : "\n" + root.cpuTemp + "°")
      : "CPU " + (root.cpuPercent < 0 ? "…" : root.cpuPercent + "%")
        + (root.cpuTemp < 0 ? "" : " " + root.cpuTemp + "°C")
        + "  RAM " + (root.ramFreePercent < 0 ? "…" : root.ramFreePercent + "%")
    tooltipText: "CPU загрузка: " + Math.max(root.cpuPercent, 0) + "%\n"
      + (root.cpuTemp < 0 ? "" : "CPU + видеоядро Iris Xe: " + root.cpuTemp + " °C (самое горячее ядро " + root.coreMaxTemp + " °C)\n")
      + (root.ssdTemp < 0 ? "" : "SSD: " + root.ssdTemp + " °C\n")
      + (root.fanRpm.length ? "Вентиляторы: " + root.fanRpm.join(" / ") + " об/мин\n" : "")
      + "RAM свободно: " + Math.max(root.ramFreePercent, 0) + "% ("
      + root.ramAvailableGiB.toFixed(1) + " из " + root.ramTotalGiB.toFixed(1) + " ГиБ)"
    onPressed: function() { if (root.bar) root.bar.run("omarchy-launch-or-focus-tui btop") }
  }
}
