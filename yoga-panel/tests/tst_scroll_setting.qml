import QtQuick
import QtTest
import ".."

TestCase {
    name: "ScrollSetting"
    visible: true; when: windowShown
    width: 1100; height: 100
    property real appliedSpeed: 0.09
    ScrollPreference { id: row; width: 1100; height: 54; value: appliedSpeed; onAdjusted: value => appliedSpeed=value }
    function test_drag_applies_and_external_update_stays_bound() {
        let slider=findChild(row,"scrollSpeedSlider");
        verify(slider!==null);wait(50);
        let touch=touchEvent(slider);
        touch.press(0,slider,slider.width*.07,slider.height/2).commit();
        touch.move(0,slider,slider.width*.6,slider.height/2).commit();wait(50);
        verify(appliedSpeed>.4,"Dragging applies before release");
        touch.release(0,slider,slider.width*.6,slider.height/2).commit();
        appliedSpeed=.09;wait(50);
        compare(slider.value,.09,"External setting remains bound after dragging");
    }
}
