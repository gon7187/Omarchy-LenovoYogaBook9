import QtQuick

Rectangle {
    id: key
    property string label: ""
    property real textSize: label.length > 3 ? 17 : 24
    property bool selected: false
    property bool repeatable: false
    property bool activateOnRelease: false
    property bool down: false
    signal activated()
    onVisibleChanged: if (!visible) reset()
    radius: 11
    color: down ? "#446b96" : selected ? "#284e75" : "#202a38"
    border.color: down || selected ? "#87bcf5" : "#384658"
    border.width: 1
    Text {
        anchors.centerIn: parent
        text: key.label
        color: "#f0f5ff"
        font.pixelSize: key.textSize
        font.weight: Font.Medium
    }
    TapHandler {
        acceptedButtons: Qt.LeftButton
        onPressedChanged: {
            if (pressed) {
                key.down = true;
                if (!key.activateOnRelease) key.activated();
                if (key.repeatable) delay.restart();
            } else key.reset();
        }
        onTapped: if (key.activateOnRelease) key.activated()
        onCanceled: key.reset()
    }
    function reset() { down = false; delay.stop(); repeater.stop(); }
    Timer { id: delay; interval: 420; onTriggered: repeater.start() }
    Timer { id: repeater; interval: 65; repeat: true; onTriggered: key.activated() }
}
