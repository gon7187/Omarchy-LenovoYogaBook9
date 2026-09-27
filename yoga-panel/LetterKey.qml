import QtQuick
import "KeyboardLayout.js" as Layouts

Key {
    id: key
    required property var symbols
    property bool russianActive: true
    property bool shifted: false
    property bool caps: false
    readonly property string character: Layouts.character(symbols,russianActive,shifted,caps)
    readonly property bool dual: symbols.en !== symbols.ru
    readonly property bool narrow: width < 65
    readonly property real legendHeight: height < 60 ? 14 : 24
    readonly property string shiftedLegend: russianActive ? symbols.ruShift : symbols.enShift
    readonly property bool showShift: shiftedLegend.toUpperCase() !== (russianActive ? symbols.ru : symbols.en).toUpperCase()
    radius: 8
    Text {
        visible: key.dual && !key.iconOnly
        anchors.left: parent.left; anchors.top: parent.top
        anchors.leftMargin: key.narrow ? 6 : 13; anchors.topMargin: key.narrow ? 4 : 7
        width: key.narrow ? (key.width-12)/(key.showShift ? 2 : 1) : undefined
        height: key.narrow ? key.legendHeight : undefined
        fontSizeMode: key.narrow ? Text.Fit : Text.FixedSize; minimumPixelSize: 10
        text: key.symbols.en.toUpperCase()
        color: key.russianActive ? Theme.textDim : Theme.letterActive
        font.pixelSize: key.height<60 ? 21 : 25; font.weight: key.russianActive ? Font.Normal : Font.Medium
    }
    Text {
        visible: key.dual && !key.iconOnly
        anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.rightMargin: key.narrow ? 6 : 13; anchors.bottomMargin: key.narrow ? 4 : key.height<60 ? 3 : 7
        width: key.narrow ? key.width-12 : undefined
        height: key.narrow ? key.height-8-key.legendHeight : undefined
        horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignBottom
        fontSizeMode: key.narrow ? Text.Fit : Text.FixedSize; minimumPixelSize: 12
        text: key.symbols.ru.toUpperCase()
        color: key.russianActive ? Theme.letterActive : Theme.textDim
        font.pixelSize: key.height<60 ? 21 : 25; font.weight: key.russianActive ? Font.Medium : Font.Normal
    }
    Text {
        visible: !key.dual && !key.iconOnly
        anchors.left: parent.left; anchors.bottom: parent.bottom
        anchors.leftMargin: key.narrow ? 6 : 16; anchors.bottomMargin: key.narrow ? 4 : 9
        width: key.narrow ? key.width-12 : undefined
        height: key.narrow ? key.height-8-key.legendHeight : undefined
        horizontalAlignment: key.narrow ? Text.AlignHCenter : Text.AlignLeft; verticalAlignment: Text.AlignBottom
        fontSizeMode: key.narrow ? Text.Fit : Text.FixedSize; minimumPixelSize: 12
        text: key.symbols.en
        color: Theme.text; font.pixelSize: key.height<60 ? 27 : 32; font.weight: Font.Medium
    }
    Text {
        visible: key.showShift && !key.iconOnly
        anchors.right: parent.right; anchors.top: parent.top
        anchors.rightMargin: key.narrow ? 6 : 10; anchors.topMargin: key.narrow ? 4 : key.height<60 ? 3 : 5
        width: key.narrow ? (key.width-12)/(key.dual ? 2 : 1) : undefined
        height: key.narrow ? key.legendHeight : undefined
        horizontalAlignment: Text.AlignRight
        fontSizeMode: key.narrow ? Text.Fit : Text.FixedSize; minimumPixelSize: 10
        text: key.shiftedLegend
        color: key.shifted ? Theme.text : Theme.textDim; font.pixelSize: key.height<60 ? 14 : 21
    }
}
