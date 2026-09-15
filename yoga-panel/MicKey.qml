import QtQuick

Rectangle {
    id: mic
    property bool holding: false
    signal started()
    signal finished()
    signal aborted()
    radius: 8
    color: holding ? "#ad3848" : "#202a38"
    border.color: holding ? "#ff9da9" : "#384658"
    Text { anchors.centerIn: parent; text: "🎤"; font.pixelSize: 26; color: "#f0f5ff" }
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
