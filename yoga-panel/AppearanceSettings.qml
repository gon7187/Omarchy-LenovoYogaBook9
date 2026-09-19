import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls

ColumnLayout {
    id: view
    required property var settings
    spacing: 12
    RowLayout {
        Layout.fillWidth: true; Layout.preferredHeight: 32; Layout.minimumHeight: 32; Layout.maximumHeight: 32
        Text { text: "Внешний вид"; color: Theme.text; font.pixelSize: 23; font.weight: Font.DemiBold }
        Item { Layout.fillWidth: true }
        Key { label: "Тачпад и ввод"; textSize: 13; Layout.preferredWidth: 150; Layout.fillHeight: true; onActivated: settings.appearanceOpen=false }
    }
    RowLayout {
        Layout.fillWidth: true; Layout.fillHeight: true; spacing: 12
        SettingsCard {
            title: "Цвета"; subtitle: "Палитры установленных тем Omarchy"
            Controls.ComboBox {
                id: themes
                Layout.fillWidth: true; implicitHeight: 44
                model: [{name:"system",label:"Как в ОС"}].concat(view.settings.appearance.themes || [])
                textRole: "label"; valueRole: "name"
                currentIndex: Math.max(0,model.findIndex(t=>t.name===view.settings.themeName))
                onActivated: view.settings.themeName=currentValue
                palette.button: Theme.card; palette.buttonText: Theme.text; palette.base: Theme.card; palette.text: Theme.text; palette.highlight: Theme.keyDown; palette.highlightedText: Theme.text
            }
            Text { text: "Сейчас: "+Theme.name; color: Theme.textMuted; font.pixelSize: 13; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            SettingsSlider { label: "Непрозрачность фона"; value: settings.panelOpacity; minimum: .65; maximum: 1; step: .05; displayValue: Math.round(value*100)+"%"; onAdjusted: value => settings.panelOpacity=value }
            Text { text: "Буквы и значки остаются чёткими.\nFn + пробел: OLED Black / тема ОС."; color: Theme.textMuted; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            Item { Layout.fillHeight: true }
        }
        SettingsCard {
            title: "Значки"; subtitle: "Сердце — клавиша Super"
            Repeater {
                model: [{value:"theme",label:"По теме"},{value:"pixel",label:"Пиксельные"},{value:"line",label:"Контурные"},{value:"text",label:"Микрофон: mic"}]
                Key { required property var modelData; label: modelData.label; textSize: 15; Layout.fillWidth: true; Layout.preferredHeight: 42; selected: settings.iconStyle===modelData.value; onActivated: settings.iconStyle=modelData.value }
            }
            Item { Layout.fillHeight: true }
        }
        SettingsCard {
            title: "OLED"; subtitle: "Снижение статичной нагрузки"
            SettingsSwitch { label: "Сдвиг на 1–2 пикселя"; checked: settings.oledShift; onToggled: value => settings.oledShift=value }
            SettingsSwitch { label: "Приглушать в простое"; checked: settings.oledDim; onToggled: value => settings.oledDim=value }
            Text { text: "Сдвиг раз в 3 минуты, в паузах.\nПриглушение через минуту без ввода.\nПервое касание работает как обычно.\n\nВ настройках эффекты приостановлены.\nЭто не гарантия от выгорания."; color: Theme.textMuted; font.pixelSize: 13; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            Item { Layout.fillHeight: true }
        }
    }
}
