import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root
    property bool opened: false
    property bool russian: true
    property bool shift: false
    property bool control: false
    property bool alt: false
    property bool logo: false
    property bool drag: false
    property bool settingsOpen: false
    property bool settingsLoaded: false
    property real pointerSpeed: 2.4
    property real pointerAccel: 0.6
    property real scrollSpeed: 0.18
    onPointerSpeedChanged: if (settingsLoaded) saveSettings.restart()
    onPointerAccelChanged: if (settingsLoaded) saveSettings.restart()
    onScrollSpeedChanged: if (settingsLoaded) saveSettings.restart()
    Timer {
        id: saveSettings; interval: 350
        onTriggered: root.send({type:"settings",values:{pointerSpeed:root.pointerSpeed,pointerAccel:root.pointerAccel,scrollSpeed:root.scrollSpeed}})
    }
    property string status: "Подключение…"
    readonly property var bottom: Quickshell.screens.find(s => s.name === "eDP-2") ?? null
    readonly property string base: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "") + "/"

    function send(e) {
        if (!backend.running) { status = "Ошибка ввода — перезапусти панель"; return; }
        backend.write(JSON.stringify(e) + "\n");
    }
    function typeKey(key) {
        let mods = [];
        if (control) mods.push("ctrl");
        if (alt) mods.push("alt");
        if (logo) mods.push("logo");
        if (shift) mods.push("shift");
        send({type: "key", key: key, mods: mods});
        control = false; alt = false; logo = false; shift = false;
    }
    function typeText(char) {
        let mods = [];
        if (control) mods.push("ctrl");
        if (alt) mods.push("alt");
        if (logo) mods.push("logo");
        if (shift) mods.push("shift");
        send({type: "text", text: shift ? char.toUpperCase() : char, mods: mods});
        shift = false; control = false; alt = false; logo = false;
    }
    function click(button) {
        send({type:"button",button:button,state:1});
        send({type:"button",button:button,state:0});
    }
    function closePanel() {
        pad.resetGesture();
        send({type:"release"}); drag = false; opened = false;
        shift = false; control = false; alt = false; logo = false;
    }
    Process {
        id: backend
        command: ["python3", root.base + "backend.py"]
        running: true
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => {
                if (data.startsWith("{")) {
                    try {
                        let s=JSON.parse(data).settings;
                        if (s) {
                            root.settingsLoaded=false;
                            root.pointerSpeed=s.pointerSpeed; root.pointerAccel=s.pointerAccel; root.scrollSpeed=s.scrollSpeed;
                            root.settingsLoaded=true;
                        }
                    } catch(e) { root.status="Не удалось загрузить настройки"; }
                } else root.status = data === "ready" ? "Готово" : "Ошибка ввода — проверь журнал";
            }
        }
        stderr: SplitParser { onRead: data => console.warn(data) }
        onExited: root.status = "Служба ввода остановлена"
    }
    IpcHandler {
        target: "panel"
        function toggle(): void { if (root.opened) root.closePanel(); else root.opened = true; }
        function openPanel(): void { root.opened = true; }
        function hide(): void { root.closePanel(); }
        function status(): string { return root.opened ? "open" : "closed"; }
        function touchStatus(): string { return JSON.stringify({pressed:pad.pressEvents,updated:pad.updateEvents,samples:pad.samples,moves:pad.moveEvents,count:pad.previousCount,peak:pad.peakCount,histogram:pad.histogram}); }
        function testKeys(): void { digitKeys.itemAt(0).activated(); letterKeys.itemAt(0).activated(); root.typeText(" "); }
        function testCenters(): string {
            return JSON.stringify([digitKeys.itemAt(0), letterKeys.itemAt(0), spaceKey].map(k => k.mapToGlobal(k.width/2,k.height/2)));
        }
    }
    PanelWindow {
        id: handle
        screen: root.bottom
        visible: root.bottom !== null && !root.opened
        anchors { bottom: true }
        implicitWidth: 360
        implicitHeight: 45
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "yoga-panel-handle"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        Rectangle {
            anchors.fill: parent
            radius: 16
            color: "#ec172231"
            border.color: "#556a85"
            Text { anchors.centerIn: parent; text: "⌨  Клавиатура и тачпад"; color: "#e3edff"; font.pixelSize: 17 }
            MultiPointTouchArea {
                anchors.fill: parent
                minimumTouchPoints: 1
                maximumTouchPoints: 5
                onReleased: root.opened = true
            }
        }
    }
    PanelWindow {
        id: panel
        screen: root.bottom
        visible: root.bottom !== null && root.opened
        anchors { top: true; bottom: true; left: true; right: true }
        color: "#101722"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "yoga-input-panel"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            anchors.topMargin: 8
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                Layout.minimumHeight: 32
                Layout.maximumHeight: 32
                spacing: 6
                Text { text: "YOGA"; color: "#b9cbe4"; font.pixelSize: 13; font.letterSpacing: 1 }
                Item { Layout.fillWidth: true }
                Text { text: root.status; color: "#89a6c9"; font.pixelSize: 12 }
                Key { Layout.preferredWidth: 110; Layout.fillHeight: true; radius: 7; textSize: 13; label: root.settingsOpen ? "← Клавиатура" : "⚙ Тачпад"; onActivated: { pad.resetGesture(); root.settingsOpen=!root.settingsOpen; } }
                Key { Layout.preferredWidth: 80; Layout.fillHeight: true; radius: 7; textSize: 13; label: root.russian ? "RU → EN" : "EN → RU"; onActivated: root.russian = !root.russian }
                Key { Layout.preferredWidth: 36; Layout.fillHeight: true; radius: 7; textSize: 17; label: "✕"; onActivated: root.closePanel() }
            }
            ColumnLayout {
                id: keyboard
                visible: !root.settingsOpen
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(400, panel.height * 0.48)
                Layout.maximumHeight: Math.min(400, panel.height * 0.48)
                Layout.minimumHeight: 240
                spacing: 8
                RowLayout {
                    Layout.fillWidth: true; Layout.fillHeight: true; spacing: 7
                    Key { Layout.preferredWidth: 72; Layout.fillHeight: true; label: "Esc"; onActivated: root.typeKey("Escape") }
                    Repeater {
                        id: digitKeys
                        model: root.shift ? ["!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_", "+"] : ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="]
                        Key { required property string modelData; Layout.fillWidth: true; Layout.fillHeight: true; label: modelData; onActivated: root.typeText(modelData) }
                    }
                    Key { Layout.preferredWidth: 118; Layout.fillHeight: true; label: "⌫"; repeatable: true; onActivated: root.typeKey("BackSpace") }
                }
                RowLayout {
                    Layout.fillWidth: true; Layout.fillHeight: true; spacing: 7
                    Key { Layout.preferredWidth: 92; Layout.fillHeight: true; label: "Tab"; onActivated: root.typeKey("Tab") }
                    Repeater {
                        id: letterKeys
                        model: (root.russian ? "йцукенгшщзхъё" : "qwertyuiop[]\\").split("")
                        Key { required property string modelData; Layout.fillWidth: true; Layout.fillHeight: true; label: root.shift ? modelData.toUpperCase() : modelData; onActivated: root.typeText(modelData) }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true; Layout.fillHeight: true; spacing: 7
                    Item { Layout.preferredWidth: 26 }
                    Repeater {
                        model: (root.russian ? "фывапролджэ" : "asdfghjkl;'").split("")
                        Key { required property string modelData; Layout.fillWidth: true; Layout.fillHeight: true; label: root.shift ? modelData.toUpperCase() : modelData; onActivated: root.typeText(modelData) }
                    }
                    Key { Layout.preferredWidth: 135; Layout.fillHeight: true; label: "Enter ↵"; onActivated: root.typeKey("Return") }
                }
                RowLayout {
                    Layout.fillWidth: true; Layout.fillHeight: true; spacing: 7
                    Key { Layout.preferredWidth: 122; Layout.fillHeight: true; label: "Shift ⇧"; selected: root.shift; onActivated: root.shift = !root.shift }
                    Repeater {
                        model: (root.russian ? "ячсмитьбю.," : "zxcvbnm,./?").split("")
                        Key { required property string modelData; Layout.fillWidth: true; Layout.fillHeight: true; label: root.shift ? modelData.toUpperCase() : modelData; onActivated: root.typeText(modelData) }
                    }
                    Key { Layout.preferredWidth: 85; Layout.fillHeight: true; label: "↑"; repeatable: true; onActivated: root.typeKey("Up") }
                }
                RowLayout {
                    Layout.fillWidth: true; Layout.fillHeight: true; spacing: 7
                    Key { Layout.preferredWidth: 92; Layout.fillHeight: true; label: "Ctrl"; selected: root.control; onActivated: root.control = !root.control }
                    Key { Layout.preferredWidth: 115; Layout.fillHeight: true; label: "Super ⊞"; selected: root.logo; onActivated: root.logo = !root.logo }
                    Key { Layout.preferredWidth: 92; Layout.fillHeight: true; label: "Alt"; selected: root.alt; onActivated: root.alt = !root.alt }
                    Key { id: spaceKey; Layout.fillWidth: true; Layout.fillHeight: true; label: "Пробел"; onActivated: root.typeText(" ") }
                    Key { Layout.preferredWidth: 85; Layout.fillHeight: true; label: "←"; repeatable: true; onActivated: root.typeKey("Left") }
                    Key { Layout.preferredWidth: 85; Layout.fillHeight: true; label: "↓"; repeatable: true; onActivated: root.typeKey("Down") }
                    Key { Layout.preferredWidth: 85; Layout.fillHeight: true; label: "→"; repeatable: true; onActivated: root.typeKey("Right") }
                }
            }
            ColumnLayout {
                visible: root.settingsOpen
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(400, panel.height * 0.48)
                Layout.maximumHeight: Math.min(400, panel.height * 0.48)
                spacing: 12
                Text { text: "Настройки тачпада"; color: "#f0f5ff"; font.pixelSize: 25 }
                PreferenceRow { label: "Скорость курсора"; value: root.pointerSpeed; minimum: 0.5; maximum: 5; step: 0.1; onAdjusted: value => root.pointerSpeed=value }
                PreferenceRow { label: "Ускорение"; value: root.pointerAccel; minimum: 0; maximum: 2; step: 0.1; onAdjusted: value => root.pointerAccel=value }
                PreferenceRow { label: "Скорость прокрутки"; value: root.scrollSpeed; minimum: 0.03; maximum: 1; step: 0.03; onAdjusted: value => root.scrollSpeed=value }
                Text { text: "Ускорение: быстрый жест перемещает курсор дальше. 0 — без ускорения.\nЗначения сохраняются автоматически. Тачпад внизу можно сразу проверить."; color: "#89a6c9"; font.pixelSize: 16 }
                Key { Layout.preferredWidth: 245; Layout.preferredHeight: 44; label: "Сбросить настройки"; onActivated: { root.pointerSpeed=2.4; root.pointerAccel=0.6; root.scrollSpeed=0.18; } }
                Item { Layout.fillHeight: true }
            }
            Rectangle {
                Layout.fillWidth: true; Layout.fillHeight: true
                Layout.minimumHeight: 120
                radius: 15
                color: "#151f2c"
                border.color: "#344356"
                Text {
                    anchors.centerIn: parent
                    text: "ТАЧПАД\nТап — левый клик · тап двумя — правый\nДва пальца — прокрутка · три влево / вправо — рабочие столы\nДвойной тап и движение — выделение / перетаскивание"
                    horizontalAlignment: Text.AlignHCenter
                    color: "#60748e"; font.pixelSize: 17; lineHeight: 1.5
                }
                MultiPointTouchArea {
                    id: pad
                    anchors.fill: parent
                    minimumTouchPoints: 1; maximumTouchPoints: 5
                    mouseEnabled: false
                    property real lastX: 0
                    property real lastY: 0
                    property real travel: 0
                    property real began: 0
                    property int previousCount: 0
                    property int peakCount: 0
                    property int pressEvents: 0
                    property int updateEvents: 0
                    property int samples: 0
                    property int moveEvents: 0
                    property var histogram: [0,0,0,0,0,0]
                    property var positions: ({})
                    property int scrollEvents: 0
                    property real lastSampleTime: 0
                    property real lastTapTime: -1000
                    property real lastTapX: 0
                    property real lastTapY: 0
                    property bool tapDragging: false
                    property int dragPointId: -1
                    property bool workspaceGesture: false
                    property real swipeX: 0
                    property real swipeY: 0
                    property bool scrolling: false
                    touchPoints: [TouchPoint { id: p1 }, TouchPoint { id: p2 }, TouchPoint { id: p3 }, TouchPoint { id: p4 }, TouchPoint { id: p5 }]
                    function sample(currentPoints) {
                        samples++;
                        let points = Array.from(currentPoints).filter(p => p.pressed);
                        let n = points.length;
                        histogram[n]++;
                        let now=Date.now();
                        let elapsed=Math.max(4,Math.min(40,now-lastSampleTime));
                        lastSampleTime=now;
                        let endedDrag=false;
                        if (tapDragging && !points.some(p => p.pointId === dragPointId)) {
                            root.send({type:"button",button:272,state:0});
                            tapDragging=false; endedDrag=true; lastTapTime=-1000;
                        }
                        if (!n) {
                            if (workspaceGesture) {
                                if (peakCount===3 && now-began < 1800 && Math.abs(swipeX)>=100 && Math.abs(swipeX)>Math.abs(swipeY)*1.5)
                                    root.send({type:"workspace",direction:swipeX<0 ? "next" : "previous"});
                                workspaceGesture=false; swipeX=0; swipeY=0; lastTapTime=-1000;
                            } else if (!endedDrag && previousCount && now-began < 350 && travel < 18 && !root.drag && peakCount <= 2) {
                                root.click(peakCount === 2 ? 273 : 272);
                                lastTapTime=peakCount === 1 ? now : -1000;
                                lastTapX=lastX; lastTapY=lastY;
                            }
                            previousCount=0; positions={}; scrolling=false;
                            return;
                        }
                        if (!previousCount) {
                            began=now; travel=0; peakCount=0;
                            if (n===1 && !root.drag && now-lastTapTime < 350 && Math.hypot(points[0].x-lastTapX,points[0].y-lastTapY)<60) {
                                tapDragging=true; dragPointId=points[0].pointId;
                                root.send({type:"button",button:272,state:1});
                            }
                            lastTapTime=-1000;
                        }
                        let x = points.reduce((a,p) => a+p.x,0)/n;
                        let y = points.reduce((a,p) => a+p.y,0)/n;
                        peakCount = Math.max(peakCount,n);
                        let startingSwipe = n >= 3 && !workspaceGesture;
                        if (startingSwipe) {
                            workspaceGesture=true; swipeX=0; swipeY=0; lastTapTime=-1000;
                            if (tapDragging) {
                                root.send({type:"button",button:272,state:0}); tapDragging=false;
                            }
                        }
                        let next = {}, moving = [];
                        for (let p of points) {
                            let before = positions[p.pointId];
                            next[p.pointId] = {x:p.x,y:p.y};
                            if (!before) continue;
                            let dx=p.x-before.x, dy=p.y-before.y;
                            let distance=Math.hypot(dx,dy);
                            if (distance > 0.05) moving.push({dx:dx,dy:dy,distance:distance});
                        }
                        positions=next;
                        if (workspaceGesture && n<3 && Math.abs(swipeX)<30)
                            workspaceGesture=false;
                        if (workspaceGesture) {
                            // Accumulate only movement while all three fingers
                            // are present; lifting them cannot move or click.
                            if (!startingSwipe && n===3 && previousCount===3) {
                                swipeX+=moving.reduce((sum,p)=>sum+p.dx,0)/3;
                                swipeY+=moving.reduce((sum,p)=>sum+p.dy,0)/3;
                            }
                            previousCount=n; lastX=x; lastY=y;
                            return;
                        }
                        moving.sort((a,b) => b.distance-a.distance);
                        if (n<2) scrolling=false;
                        if (moving.length) {
                            let first=moving[0], second=moving[1];
                            travel += first.distance;
                            // A resting palm or stale contact must not turn a
                            // moving finger into a two-finger scroll gesture.
                            let scrollIntent = !root.drag && n === 2 && second &&
                                second.distance > first.distance*0.25 &&
                                first.dx*second.dx + first.dy*second.dy > 0;
                            if (scrollIntent) {
                                scrolling=true; lastTapTime=-1000;
                                if (tapDragging) {
                                    root.send({type:"button",button:272,state:0}); tapDragging=false;
                                }
                            }
                            if (scrolling && n===2) {
                                scrollEvents++;
                                root.send({type:"scroll",x:-moving.reduce((sum,p)=>sum+p.dx,0)*root.scrollSpeed/2,y:-moving.reduce((sum,p)=>sum+p.dy,0)*root.scrollSpeed/2});
                            } else {
                                moveEvents++;
                                let gain=root.pointerSpeed*(1+root.pointerAccel*Math.min(first.distance/elapsed/1.2,2));
                                root.send({type:"move",x:first.dx*gain,y:first.dy*gain});
                            }
                        }
                        previousCount=n; lastX=x; lastY=y;
                    }
                    function resetGesture() {
                        if (tapDragging) root.send({type:"button",button:272,state:0});
                        tapDragging=false; dragPointId=-1; lastTapTime=-1000;
                        previousCount=0; positions={};
                        workspaceGesture=false; swipeX=0; swipeY=0;
                        scrolling=false;
                    }
                    onPressed: { pressEvents++; }
                    onUpdated: { updateEvents++; }
                    // Use the completed event's active list once, not intermediate
                    // pressed/released snapshots while Qt updates its point pool.
                    onTouchUpdated: points => sample(points)
                    onCanceled: { resetGesture(); root.send({type:"release"}); root.drag=false; }
                }
            }
        }
    }
}
