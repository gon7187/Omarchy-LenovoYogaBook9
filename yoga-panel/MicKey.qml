import QtQuick

Rectangle {
    id: mic
    property bool holding: false
    signal started()
    signal finished()
    signal aborted()
    radius: 8
    color: holding ? Theme.mic : Theme.key
    border.color: holding ? Theme.micBorder : Theme.keyBorder
    ControlIcon { anchors.centerIn: parent; kind: "mic"; width: 26; height: 26; visible: Theme.icons!=="text" }
    Text { anchors.centerIn: parent; text: "mic"; font.pixelSize: 17; color: Theme.text; visible: Theme.icons==="text" }
    onHoldingChanged: Theme.activity()
    function cancel() { if (holding) { holding=false; aborted(); } }
    onVisibleChanged: if (!visible) cancel()
    Component.onDestruction: cancel()
    MultiPointTouchArea {
        anchors.fill: parent
        minimumTouchPoints: 1; maximumTouchPoints: 1
        mouseEnabled: true
        onPressed: { if (!mic.holding) { mic.holding=true; mic.started(); } }
        onReleased: { if (mic.holding) { mic.holding=false; mic.finished(); } }
        onCanceled: mic.cancel()
    }
}
