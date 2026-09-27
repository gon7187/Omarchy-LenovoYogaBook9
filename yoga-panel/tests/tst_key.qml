import QtQuick
import QtTest
import ".."

TestCase {
    name: "KeyHold"
    when: windowShown
    width: 260; height: 140
    visible: true
    Key { id: key; x: 10; y: 10; width: 220; height: 80; label: "Backspace"; repeatable: true }
    Key { id: narrow; width: 47; height: 32; label: "F12"; textSize: 13; compactHint: true; hintIcon: "audio" }
    function test_narrow_function_label() {
        narrow.hintActive=false;
        let text=narrow.children.find(c=>c.text==="F12");
        let icon=narrow.children.find(c=>c.name==="audio");
        verify(text!==undefined); verify(icon!==undefined);
        wait(10);
        compare(text.truncated,false,"Portrait F12 must remain readable");
        compare(icon.visible,false,"Inactive hint must leave room for the label");
        narrow.hintActive=true; wait(10);
        compare(text.visible,false); compare(icon.visible,true);
        compare(icon.x,(narrow.width-icon.width)/2);
        narrow.hintActive=false;
    }
    SignalSpy { id: spy; target: key; signalName: "activated" }
    function init() { key.visible=true; key.reset(); wait(50); spy.clear(); }
    function test_slide_inside_keeps_repeating() {
        let touch=touchEvent(key);
        touch.press(0,key,30,35).commit();
        wait(530);
        verify(spy.count>=2,"Held key should repeat");
        touch.move(0,key,140,40).commit();
        let before=spy.count;
        wait(200);
        verify(spy.count>before,"Movement inside key must not cancel repetition");
        touch.release(0,key,140,40).commit();
        wait(20);before=spy.count;wait(200);
        compare(spy.count,before,"Release must stop repetition");
        compare(key.down,false);
    }
    function test_outside_cancels_repetition() {
        let touch=touchEvent(key);
        touch.press(0,key,30,35).commit();wait(530);
        touch.move(0,key,240,40).commit();wait(20);
        let before=spy.count;wait(200);compare(spy.count,before);
        compare(key.down,false);
        touch.release(0,key,240,40).commit();
    }
    function test_hide_cancels_repetition() {
        let touch=touchEvent(key);
        touch.press(0,key,30,35).commit();wait(530);
        key.visible=false;let before=spy.count;wait(200);
        compare(spy.count,before);compare(key.down,false);
        touch.release(0,key,30,35).commit();
    }
}
