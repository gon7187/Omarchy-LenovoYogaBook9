import QtQuick
import Quickshell
import qs.Commons

// On-screen keyboard for the Omarchy lock screen, drawn inside the session-lock
// surface itself: while ext-session-lock is held Hyprland shows no other client,
// so yoga-panel cannot appear there. Keys only edit the lock's own password text;
// nothing is logged or sent anywhere. Use the upper panel when folded.
Item {
  id: keys
  required property Item view

  property bool shift: false
  property bool symbols: false

  readonly property var letterRows: [["q","w","e","r","t","y","u","i","o","p"], ["a","s","d","f","g","h","j","k","l"], ["⇧","z","x","c","v","b","n","m","⌫"], ["?123","space","↵"]]
  readonly property var symbolRows: [["1","2","3","4","5","6","7","8","9","0"],["@","#","$","%","&","*","-","+","(",")"],["!","\"","'",":",";","/","_","=",",",".","⌫"],["?","^","[","]","{","}","\\","`","~","<",">","|"],["abc","space","↵"]]
  readonly property var rows: symbols ? symbolRows : letterRows
  readonly property real keyH: Math.min(78, height / rows.length - 10)

  readonly property string keyboardScreen: Quickshell.screens.some(s => s.name === "eDP-2") ? "eDP-2" : "eDP-1"

  visible: Screen.name === keyboardScreen && view.inputEnabled
  anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 16 }
  height: Math.min(parent.height * 0.42, 360)

  function press(k) {
    view.wakeRequested()
    if (view.authenticatingPassword) return
    if (k === "⇧") { shift = !shift; return }
    if (k === "?123" || k === "abc") { symbols = !symbols; return }
    if (k === "⌫") { view.passwordTextEdited(view.passwordText.slice(0, -1)); return }
    if (k === "↵") {
      var submitted = view.passwordText
      view.passwordTextEdited("")
      if (submitted.length > 0) view.submitPassword(submitted)
      return
    }
    var ch = k === "space" ? " " : (shift ? k.toUpperCase() : k)
    if (view.failureMessage.length > 0) view.clearFailureRequested()
    view.passwordTextEdited(view.passwordText + ch)
    shift = false
  }

  Column {
    anchors.fill: parent
    spacing: 10

    Repeater {
      model: keys.rows

      Row {
        id: row
        required property var modelData
        readonly property real unit: (keys.width - 10 * (modelData.length - 1)) / modelData.reduce((n, k) => n + (k === "space" ? 5 : 1), 0)
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 10

        Repeater {
          model: row.modelData

          Rectangle {
            required property string modelData
            readonly property bool wide: modelData === "space"
            readonly property bool action: modelData.length > 1 || "⇧⌫↵".indexOf(modelData) !== -1
            width: row.unit * (wide ? 5 : 1)
            height: keys.keyH
            radius: Style.cornerRadius
            color: tap.pressed ? Color.lock.borderActive : (modelData === "⇧" && keys.shift ? Color.lock.selection : Color.lock.background)
            border.width: 1
            border.color: Color.lock.placeholder

            Text {
              anchors.centerIn: parent
              text: parent.modelData === "space" ? "" : (keys.shift && parent.modelData.length === 1 ? parent.modelData.toUpperCase() : parent.modelData)
              color: Color.lock.text
              font.family: Style.font.family
              font.pixelSize: Math.round(keys.keyH * 0.4)
            }

            MouseArea {
              id: tap
              anchors.fill: parent
              onClicked: keys.press(parent.modelData)
            }
          }
        }
      }
    }
  }
}
