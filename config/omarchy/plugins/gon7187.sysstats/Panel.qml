import QtQuick
import Quickshell.Io
import qs.Ui
import qs.Commons

// CPU load and available RAM, read straight from /proc every few seconds.
// Click opens btop.
BarWidget {
  id: root
  moduleName: "gon7187.sysstats"

  property int cpuPercent: -1
  property int ramFreePercent: -1
  property real ramAvailableGiB: 0
  property real ramTotalGiB: 0
  property var lastCpu: null

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
  }

  FileView { id: statFile; path: "/proc/stat"; blockLoading: true; printErrors: false }
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
    text: root.vertical
      ? (root.cpuPercent < 0 ? "…" : root.cpuPercent + "%") + "\n" + (root.ramFreePercent < 0 ? "…" : root.ramFreePercent + "%")
      : "CPU " + (root.cpuPercent < 0 ? "…" : root.cpuPercent + "%") + "  RAM " + (root.ramFreePercent < 0 ? "…" : root.ramFreePercent + "%")
    tooltipText: "CPU загрузка: " + Math.max(root.cpuPercent, 0) + "%\n"
      + "RAM свободно: " + Math.max(root.ramFreePercent, 0) + "% ("
      + root.ramAvailableGiB.toFixed(1) + " из " + root.ramTotalGiB.toFixed(1) + " ГиБ)"
    onPressed: function() { if (root.bar) root.bar.run("omarchy-launch-or-focus-tui btop") }
  }
}
