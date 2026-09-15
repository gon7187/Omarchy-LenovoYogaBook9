import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "KeyboardLayout.js" as Layouts

ShellRoot {
    id: root
    property bool opened: false
    property bool russian: true
    property bool shift: false
    property bool caps: false
    property bool control: false
    property bool alt: false
    property bool logo: false
    property bool drag: false
    property bool settingsOpen: false
    property bool settingsLoaded: false
    property bool predictionEnabled: true
    property bool autocorrectEnabled: true
    onAutocorrectEnabledChanged: { clearWord(); if (settingsLoaded) saveSettings.restart(); }
    property string wordPrefix: ""
    property var suggestions: []
    property int predictionRequest: 0
    property real lastTypedAt: 0
    onRussianChanged: clearWord()
    onPredictionEnabledChanged: { clearWord(); if (settingsLoaded) saveSettings.restart(); }
    property real pointerSpeed: 2.4
    property real pointerAccel: 0.6
    property real scrollSpeed: 0.18
    onPointerSpeedChanged: if (settingsLoaded) saveSettings.restart()
    onPointerAccelChanged: if (settingsLoaded) saveSettings.restart()
    onScrollSpeedChanged: if (settingsLoaded) saveSettings.restart()
    Timer {
        id: saveSettings; interval: 350
        onTriggered: root.send({type:"settings",values:{pointerSpeed:root.pointerSpeed,pointerAccel:root.pointerAccel,scrollSpeed:root.scrollSpeed,predictionEnabled:root.predictionEnabled,autocorrectEnabled:root.autocorrectEnabled}})
    }
    property string status: "Подключение…"
    readonly property var bottom: Quickshell.screens.find(s => s.name === "eDP-2") ?? null
    readonly property string base: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "") + "/"

    function send(e) {
        if (!backend.running) { status = "Ошибка ввода — перезапусти панель"; return; }
        backend.write(JSON.stringify(e) + "\n");
    }
    Timer {
        id: predictTimer; interval: 65
        onTriggered: if (root.predictionEnabled && root.wordPrefix.length>=2)
            root.send({type:"suggest",prefix:root.wordPrefix,language:root.russian ? "ru" : "en",requestId:root.predictionRequest})
    }
    function clearWord(preserveUndo) {
        if (!preserveUndo) send({type:"resetWord"});
        wordPrefix=""; suggestions=[]; predictionRequest++;
    }
    function updateWord(char) {
        if (!predictionEnabled && !autocorrectEnabled) return;
        if (Date.now()-lastTypedAt>8000) clearWord(true);
        lastTypedAt=Date.now();
        if (/^[a-zа-яё]$/i.test(char)) {
            wordPrefix=(wordPrefix+char).slice(-64); suggestions=[]; predictionRequest++; predictTimer.restart();
        } else clearWord(true);
    }
    function completeWord(word) {
        if (!predictionEnabled || !wordPrefix || Date.now()-lastTypedAt>8000) { clearWord(); return; }
        let original=wordPrefix;
        let suffix=word.startsWith(original) ? word.slice(original.length)+" " : word+" ";
        clearWord();
        if (!word.startsWith(original)) for (let i=0;i<original.length;i++) send({type:"key",key:"BackSpace",mods:[]});
        for (let ch of suffix) send({type:"text",text:ch,mods:[]});
    }
    function switchLanguage() {
        russian=!russian; shift=false; alt=false; control=false; logo=false; clearWord();
        send({type:"language",language:russian ? "ru" : "en"});
    }
    function toggleShift() { if (alt) switchLanguage(); else shift=!shift; }
    function toggleAlt() { if (shift) switchLanguage(); else alt=!alt; }
    function typeKey(key) {
        let mods = [];
        if (control) mods.push("ctrl");
        if (alt) mods.push("alt");
        if (logo) mods.push("logo");
        if (shift) mods.push("shift");
        send({type: "key", key: key, mods: mods});
        if (key==="BackSpace" && !mods.length && wordPrefix.length) {
            wordPrefix=wordPrefix.slice(0,-1); suggestions=[]; predictionRequest++; predictTimer.restart(); lastTypedAt=Date.now();
        } else clearWord(key==="BackSpace" && !mods.length);
        control = false; alt = false; logo = false; shift = false;
    }
    function typeText(char) {
        if (Date.now()-lastTypedAt>8000) clearWord();
        let mods = [];
        if (control) mods.push("ctrl");
        if (alt) mods.push("alt");
        if (logo) mods.push("logo");
        if (shift && (logo || control || alt)) mods.push("shift");
        send({type: "text", text: char, mods: mods, autocorrect: autocorrectEnabled, language: russian ? "ru" : "en"});
        if (control || alt || logo) clearWord(); else updateWord(char);
        shift = false; control = false; alt = false; logo = false;
    }
    function click(button) {
        clearWord();
        send({type:"button",button:button,state:1});
        send({type:"button",button:button,state:0});
    }
    function closePanel() {
        clearWord();
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
                        let message=JSON.parse(data);
                        if (message.focusChanged) root.clearWord();
                        if (message.language) {
                            root.russian=message.language==="ru"; root.shift=false; root.alt=false;
                            root.send({type:"keyboardGroup",language:message.language});
                        }
                        if (message.suggestions && root.predictionEnabled && message.requestId===root.predictionRequest && message.prefix===root.wordPrefix)
                            root.suggestions=message.suggestions;
                        if (s) {
                            root.settingsLoaded=false;
                            root.pointerSpeed=s.pointerSpeed; root.pointerAccel=s.pointerAccel; root.scrollSpeed=s.scrollSpeed;
                            root.predictionEnabled=s.predictionEnabled ?? true;
                            root.autocorrectEnabled=s.autocorrectEnabled ?? true;
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
        function predictionStatus(): string { return JSON.stringify({enabled:root.predictionEnabled,autocorrect:root.autocorrectEnabled,ready:root.suggestions.length,prefixLength:root.wordPrefix.length,requestId:root.predictionRequest,language:root.russian ? "ru" : "en"}); }
        function setWords(enabled: bool): void { root.predictionEnabled=enabled; }
        function testPrediction(): void { root.russian=true; root.predictionEnabled=true; root.clearWord(); root.typeText("п"); root.typeText("р"); root.typeText("и"); }
        function acceptFirstPrediction(): void { if (root.suggestions.length) root.completeWord(root.suggestions[0]); }
        function touchStatus(): string { return JSON.stringify({pressed:pad.pressEvents,updated:pad.updateEvents,samples:pad.samples,moves:pad.moveEvents,count:pad.previousCount,peak:pad.peakCount,histogram:pad.histogram}); }
        function testKeys(): void { let old=root.russian; root.russian=true; digitKeys.itemAt(1).activated(); letterKeys.itemAt(0).activated(); root.typeText(" "); root.russian=old; }
        function testCenters(): string {
            return JSON.stringify([digitKeys.itemAt(1), letterKeys.itemAt(0), spaceKey].map(k => k.mapToGlobal(k.width/2,k.height/2)));
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
                Key { Layout.preferredWidth: 90; Layout.fillHeight: true; radius: 7; textSize: 12; label: "✦ Слова"; selected: root.predictionEnabled; onActivated: root.predictionEnabled=!root.predictionEnabled }
                Key { Layout.preferredWidth: 110; Layout.fillHeight: true; radius: 7; textSize: 13; label: root.settingsOpen ? "← Клавиатура" : "⚙ Настройки"; onActivated: { pad.resetGesture(); root.settingsOpen=!root.settingsOpen; } }
                Key { Layout.preferredWidth: 48; Layout.fillHeight: true; radius: 7; textSize: 13; label: "Esc"; onActivated: root.typeKey("Escape") }
                Key { Layout.preferredWidth: 36; Layout.fillHeight: true; radius: 7; textSize: 17; label: "✕"; onActivated: root.closePanel() }
            }
            RowLayout {
                visible: root.predictionEnabled && !root.settingsOpen
                Layout.fillWidth: true; Layout.preferredHeight: 32; Layout.maximumHeight: 32; spacing: 7
                Text { visible: root.suggestions.length===0; Layout.fillWidth: true; text: root.wordPrefix.length>=2 ? "Продолжай печатать…" : "Подсказки слов  ·  " + (root.russian ? "Русский" : "English"); color: "#71859f"; font.pixelSize: 13 }
                Repeater {
                    model: root.suggestions
                    Key { required property string modelData; Layout.fillWidth: true; Layout.fillHeight: true; radius: 7; textSize: 17; label: modelData; onActivated: root.completeWord(modelData) }
                }
            }
            ColumnLayout {
                id: keyboard
                visible: !root.settingsOpen
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(380, panel.height * 0.44)
                Layout.maximumHeight: Math.min(380, panel.height * 0.44)
                Layout.minimumHeight: 280
                spacing: 7
                readonly property real keyHeight: (Math.min(380,panel.height*0.44)-28)/5
                readonly property real unit: (panel.width - 32 - 14*7)/15
                Layout.minimumWidth: 0
                RowLayout {
                    Layout.fillWidth: true; Layout.preferredHeight: keyboard.keyHeight; Layout.minimumHeight: keyboard.keyHeight; Layout.maximumHeight: keyboard.keyHeight; spacing: 7
                    Repeater {
                        id: digitKeys
                        model: Layouts.numbers
                        LetterKey { required property var modelData; symbols: modelData; russianActive: root.russian; shifted: root.shift; caps: root.caps; Layout.preferredWidth: keyboard.unit; Layout.fillHeight: true; onActivated: root.typeText(character) }
                    }
                    Key { Layout.preferredWidth: keyboard.unit*2+7; Layout.fillHeight: true; label: "⌫"; repeatable: true; onActivated: root.typeKey("BackSpace") }
                }
                RowLayout {
                    Layout.fillWidth: true; Layout.preferredHeight: keyboard.keyHeight; Layout.minimumHeight: keyboard.keyHeight; Layout.maximumHeight: keyboard.keyHeight; spacing: 7
                    Key { Layout.preferredWidth: keyboard.unit*1.5+3.5; Layout.fillHeight: true; label: "Tab ⇥"; onActivated: root.typeKey("Tab") }
                    Repeater {
                        id: letterKeys
                        model: Layouts.upper
                        LetterKey { required property var modelData; symbols: modelData; russianActive: root.russian; shifted: root.shift; caps: root.caps; Layout.preferredWidth: keyboard.unit; Layout.fillHeight: true; onActivated: root.typeText(character) }
                    }
                    LetterKey { symbols: Layouts.pair("\\","\\","|","/"); russianActive: root.russian; shifted: root.shift; caps: root.caps; Layout.preferredWidth: keyboard.unit*1.5+3.5; Layout.fillHeight: true; onActivated: root.typeText(character) }
                }
                RowLayout {
                    Layout.fillWidth: true; Layout.preferredHeight: keyboard.keyHeight; Layout.minimumHeight: keyboard.keyHeight; Layout.maximumHeight: keyboard.keyHeight; spacing: 7
                    Key { Layout.preferredWidth: keyboard.unit*1.75+5.25; Layout.fillHeight: true; label: "Caps ⇪"; selected: root.caps; onActivated: root.caps=!root.caps }
                    Repeater {
                        model: Layouts.middle
                        LetterKey { required property var modelData; symbols: modelData; russianActive: root.russian; shifted: root.shift; caps: root.caps; Layout.preferredWidth: keyboard.unit; Layout.fillHeight: true; onActivated: root.typeText(character) }
                    }
                    Key { Layout.preferredWidth: keyboard.unit*2.25+8.75; Layout.fillHeight: true; label: "Enter ↵"; onActivated: root.typeKey("Return") }
                }
                RowLayout {
                    Layout.fillWidth: true; Layout.preferredHeight: keyboard.keyHeight; Layout.minimumHeight: keyboard.keyHeight; Layout.maximumHeight: keyboard.keyHeight; spacing: 7
                    Key { Layout.preferredWidth: keyboard.unit*2.25+8.75; Layout.fillHeight: true; label: "Shift ⇧"; selected: root.shift; onActivated: root.toggleShift() }
                    Repeater {
                        model: Layouts.lower
                        LetterKey { required property var modelData; symbols: modelData; russianActive: root.russian; shifted: root.shift; caps: root.caps; Layout.preferredWidth: keyboard.unit; Layout.fillHeight: true; onActivated: root.typeText(character) }
                    }
                    Key { Layout.preferredWidth: keyboard.unit*2.75+12.25; Layout.fillHeight: true; label: "Shift ⇧"; selected: root.shift; onActivated: root.toggleShift() }
                }
                RowLayout {
                    Layout.fillWidth: true; Layout.preferredHeight: keyboard.keyHeight; Layout.minimumHeight: keyboard.keyHeight; Layout.maximumHeight: keyboard.keyHeight; spacing: 7
                    Key { Layout.preferredWidth: keyboard.unit*1.25+1.75; Layout.minimumWidth: keyboard.unit*1.25+1.75; Layout.maximumWidth: keyboard.unit*1.25+1.75; Layout.fillHeight: true; label: "Ctrl"; selected: root.control; onActivated: root.control=!root.control }
                    Key { Layout.preferredWidth: keyboard.unit*1.25+1.75; Layout.minimumWidth: keyboard.unit*1.25+1.75; Layout.maximumWidth: keyboard.unit*1.25+1.75; Layout.fillHeight: true; label: "🚀"; selected: root.logo; onActivated: root.logo=!root.logo }
                    Key { Layout.preferredWidth: keyboard.unit*1.25+1.75; Layout.minimumWidth: keyboard.unit*1.25+1.75; Layout.maximumWidth: keyboard.unit*1.25+1.75; Layout.fillHeight: true; label: "Alt"; selected: root.alt; onActivated: root.toggleAlt() }
                    Key { id: spaceKey; Layout.fillWidth: true; Layout.fillHeight: true; label: root.russian ? "Русский  ·  пробел" : "English  ·  space"; onActivated: root.typeText(" ") }
                    Key { Layout.preferredWidth: keyboard.unit; Layout.minimumWidth: keyboard.unit; Layout.maximumWidth: keyboard.unit; Layout.fillHeight: true; label: "←"; repeatable: true; onActivated: root.typeKey("Left") }
                    ColumnLayout {
                        Layout.preferredWidth: keyboard.unit; Layout.minimumWidth: keyboard.unit; Layout.maximumWidth: keyboard.unit; Layout.fillHeight: true; spacing: 4
                        Key { Layout.fillWidth: true; Layout.fillHeight: true; label: "↑"; textSize: 18; repeatable: true; onActivated: root.typeKey("Up") }
                        Key { Layout.fillWidth: true; Layout.fillHeight: true; label: "↓"; textSize: 18; repeatable: true; onActivated: root.typeKey("Down") }
                    }
                    Key { Layout.preferredWidth: keyboard.unit; Layout.minimumWidth: keyboard.unit; Layout.maximumWidth: keyboard.unit; Layout.fillHeight: true; label: "→"; repeatable: true; onActivated: root.typeKey("Right") }
                }
            }
            ColumnLayout {
                visible: root.settingsOpen
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(400, panel.height * 0.48)
                Layout.maximumHeight: Math.min(400, panel.height * 0.48)
                spacing: 12
                Text { text: "Настройки"; color: "#f0f5ff"; font.pixelSize: 25 }
                Key { Layout.preferredWidth: 320; Layout.preferredHeight: 40; textSize: 16; label: root.autocorrectEnabled ? "✓ Автоисправление по пробелу" : "Автоисправление выключено"; selected: root.autocorrectEnabled; onActivated: root.autocorrectEnabled=!root.autocorrectEnabled }
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
                    property var scrollDirections: ({x:0,y:0})
                    property var scrollReversals: ({x:0,y:0})
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
                            if (scrolling) root.send({type:"scrollEnd"});
                            scrollDirections={x:0,y:0}; scrollReversals={x:0,y:0};
                            if (workspaceGesture) {
                                if (peakCount===3 && now-began < 1800 && Math.abs(swipeX)>=100 && Math.abs(swipeX)>Math.abs(swipeY)*1.5)
                                    root.send({type:"workspace",direction:swipeX<0 ? "next" : "previous"});
                                workspaceGesture=false; swipeX=0; swipeY=0; lastTapTime=-1000;
                            } else if (!scrolling && !endedDrag && previousCount && now-began < 350 && travel < 18 && !root.drag && peakCount <= 2) {
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
                        // Wait for all scrolling fingers to lift. The last
                        // finger's release must not turn into cursor movement.
                        if (scrolling && n<2) {
                            previousCount=n; lastX=x; lastY=y; return;
                        }
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
                                root.clearWord();
                                scrollEvents++;
                                let dx=filterScroll(moving.reduce((sum,p)=>sum+p.dx,0)/2,"x");
                                let dy=filterScroll(moving.reduce((sum,p)=>sum+p.dy,0)/2,"y");
                                if (dx || dy) root.send({type:"scroll",x:-dx*root.scrollSpeed,y:-dy*root.scrollSpeed});
                            } else {
                                root.clearWord();
                                moveEvents++;
                                let gain=root.pointerSpeed*(1+root.pointerAccel*Math.min(first.distance/elapsed/1.2,2));
                                root.send({type:"move",x:first.dx*gain,y:first.dy*gain});
                            }
                        }
                        previousCount=n; lastX=x; lastY=y;
                    }
                    function resetGesture() {
                        if (scrolling) root.send({type:"scrollEnd"});
                        if (tapDragging) root.send({type:"button",button:272,state:0});
                        tapDragging=false; dragPointId=-1; lastTapTime=-1000;
                        previousCount=0; positions={};
                        workspaceGesture=false; swipeX=0; swipeY=0;
                        scrolling=false;
                        scrollDirections={x:0,y:0}; scrollReversals={x:0,y:0};
                    }
                    function filterScroll(delta, axis) {
                        if (!delta) return 0;
                        let direction=Math.sign(delta);
                        if (!scrollDirections[axis] || direction===scrollDirections[axis]) {
                            scrollDirections[axis]=direction; scrollReversals[axis]=0; return delta;
                        }
                        scrollReversals[axis]+=delta;
                        if (Math.abs(scrollReversals[axis])<4) return 0;
                        let accumulated=scrollReversals[axis];
                        scrollDirections[axis]=direction; scrollReversals[axis]=0;
                        return accumulated;
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
