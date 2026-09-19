import QtQuick

Item {
    id: care
    property bool running: true
    property bool shiftEnabled: true
    property bool dimEnabled: true
    property bool busy: false
    property bool dimmed: false
    property real lastInput: Date.now()
    property real lastShift: Date.now()
    property int shiftIndex: 0
    readonly property var offsets: [[0,0],[2,0],[2,2],[0,2],[-2,2],[-2,0],[-2,-2],[0,-2],[2,-2]]
    readonly property real targetX: shiftEnabled ? offsets[shiftIndex][0] : 0
    readonly property real targetY: shiftEnabled ? offsets[shiftIndex][1] : 0
    property real visualX: 0
    property real visualY: 0
    function move() {
        if (busy) return;
        if (visualX!==targetX) { driftX.to=targetX; driftX.restart(); }
        if (visualY!==targetY) { driftY.to=targetY; driftY.restart(); }
    }
    NumberAnimation { id: driftX; target: care; property: "visualX"; duration: 450 }
    NumberAnimation { id: driftY; target: care; property: "visualY"; duration: 450 }
    onTargetXChanged: move()
    onTargetYChanged: move()
    function wake(now) { lastInput=now===undefined ? Date.now() : now; dimmed=false; }
    function tick(now) {
        if (busy) { wake(now); return; }
        if (now-lastInput>=3000) move();
        dimmed=dimEnabled && now-lastInput>=60000;
        if (shiftEnabled && now-lastShift>=180000 && now-lastInput>=3000) {
            shiftIndex=(shiftIndex+1)%offsets.length; lastShift=now;
        }
    }
    onBusyChanged: if (busy) {
        driftX.stop(); driftY.stop();
        // Do not leave text between physical pixels if a touch interrupts the drift.
        visualX=Math.round(visualX); visualY=Math.round(visualY);
        wake();
    }
    onDimEnabledChanged: if (!dimEnabled) dimmed=false
    onRunningChanged: { wake(); lastShift=Date.now(); }
    Timer { interval: 1000; repeat: true; running: care.running; onTriggered: care.tick(Date.now()) }
}
