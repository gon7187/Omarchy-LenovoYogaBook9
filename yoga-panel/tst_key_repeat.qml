import QtQuick
import QtTest
import "." as Panel
TestCase {
 name: "FnRepeat"; when: windowShown; visible: true; width: 200; height: 100
 Panel.Key { id:key; width:180; height:80; label:"F2"; repeatable:true; property int calls:0; onActivated:calls++ }
 Panel.Key { id:modifier; visible:false; property bool observed:false; onDownChanged: observed=down }
 function test_modifier_activity_is_counted() {
  modifier.down=true; compare(modifier.observed,true); compare(Panel.Theme.heldKeys,1);
  Panel.Theme.cancelInput(); compare(modifier.down,false); compare(Panel.Theme.heldKeys,0);
 }
 function test_fn_release_stops_repeat() {
  mousePress(key,90,40); wait(650);
  verify(key.calls>=2);
  key.repeatable=false;
  let before=key.calls; wait(200);
  compare(key.calls,before,"Releasing Fn must not leak repeated F2 into the app");
  mouseRelease(key,90,40);
 }
    function test_close_cancels_held_keys() {
        key.down=true; compare(Panel.Theme.heldKeys,1);
        Panel.Theme.cancelInput(); compare(key.down,false); compare(Panel.Theme.heldKeys,0);
    }

}
