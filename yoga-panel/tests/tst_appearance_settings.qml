import QtQuick
import QtTest
import ".."

TestCase {
    name: "AppearanceSettings"
    visible: true; when: windowShown
    width: 1408; height: 420
    QtObject {
        id: values
        property var appearance: ({themes:[]})
        property string themeName: "system"
        property string iconStyle: "line"
        property real panelOpacity: .95
        property bool oledShift: true
        property bool oledDim: true
        property bool appearanceOpen: true
    }
    AppearanceSettings { id: panel; anchors.fill: parent; settings: values }
    function test_fine_opacity_and_binding() {
        let slider=findChild(panel,"settingsSlider");
        verify(slider!==null);
        let row=slider.parent.parent;
        row.change(-row.step); fuzzyCompare(values.panelOpacity,.94,.00001);
        row.change(row.step); fuzzyCompare(values.panelOpacity,.95,.00001);
        values.panelOpacity=1; wait(20);
        fuzzyCompare(slider.value,1,.00001);
        row.change(row.step); compare(values.panelOpacity,1);
        values.panelOpacity=row.minimum;
        row.change(-row.step); compare(values.panelOpacity,row.minimum);
    }
}
