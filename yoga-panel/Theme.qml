pragma Singleton
import QtQuick

QtObject {
    id: theme
    // Theme data is validated by the private backend before reaching QML.
    property var palette: ({})
    property string name: "oled-black"
    property real surfaceOpacity: 1
    property string iconStyle: "theme"
    property bool oled: false // Retained for older preview/test clients.
    property int heldKeys: 0
    signal activity()
    signal cancelInput()
    readonly property bool light: palette.mode==="light"
    readonly property bool black: name==="oled-black" || name==="vantablack"
    readonly property string icons: iconStyle!=="theme" ? iconStyle : ["oled-black","catppuccin","catppuccin-latte","lupine","rose-pine","retro-82","hackerman"].includes(name) ? "pixel" : name==="gruvbox" ? "text" : "line"
    function token(key, fallback) { return palette[key] || fallback; }
    function alpha(value) { let c=Qt.color(value); return Qt.rgba(c.r,c.g,c.b,surfaceOpacity); }
    function mix(a,b,weight) { let x=Qt.color(a),y=Qt.color(b); return Qt.rgba(x.r*weight+y.r*(1-weight),x.g*weight+y.g*(1-weight),x.b*weight+y.b*(1-weight),1); }
    readonly property color base: token("background","#000000")
    readonly property color background: alpha(base)
    // A second panel-wide fill would multiply opacity and hide the wallpaper.
    readonly property color canvas: surfaceOpacity>=1 ? base : Qt.rgba(base.r,base.g,base.b,.18)
    readonly property color surface: alpha(base)
    readonly property color surfaceBorder: black ? "#292929" : mix(text,base,.25)
    readonly property color key: alpha(token("lighter_background","#000000"))
    readonly property color keyBorder: black ? "#383838" : mix(text,base,.30)
    readonly property color keyDown: alpha(token("selection","#242424"))
    readonly property color keySelected: keyDown
    readonly property color keyActiveBorder: accent
    readonly property color text: token("foreground","#d8d8d8")
    readonly property color textDim: mix(text,base,light ? .70 : .65)
    readonly property color textMuted: textDim
    readonly property color accent: token("accent","#d8d8d8")
    readonly property color accentDim: textDim
    readonly property color card: alpha(base)
    readonly property color cardBorder: surfaceBorder
    readonly property color track: mix(text,base,.25)
    readonly property color trackFill: accent
    readonly property color knob: light ? "#ffffff" : text
    readonly property color mic: alpha(token("selection","#242424"))
    readonly property color micBorder: token("red","#ff9da9")
}
