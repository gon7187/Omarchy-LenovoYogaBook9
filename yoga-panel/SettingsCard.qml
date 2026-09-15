import QtQuick
import QtQuick.Layouts

Rectangle {
    id: card
    property string title
    property string subtitle
    default property alias content: body.data
    Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: 1; Layout.minimumWidth: 0
    radius: 16; color: "#182230"; border.color: "#2d3d51"
    ColumnLayout {
        anchors.fill: parent; anchors.margins: 18; spacing: 7
        Text { text: card.title; font.pixelSize: 20; font.weight: Font.DemiBold; color: "#edf5ff" }
        Text { text: card.subtitle; font.pixelSize: 12; color: "#8599b2"; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        Rectangle { Layout.fillWidth: true; height: 1; color: "#2b3a4c"; Layout.topMargin: 5; Layout.bottomMargin: 7 }
        ColumnLayout { id: body; Layout.fillWidth: true; Layout.fillHeight: true; spacing: 12 }
    }
}
