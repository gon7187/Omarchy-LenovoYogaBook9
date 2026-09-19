import QtQuick
import QtTest

TestCase {
    name: "OledCare"
    OledCare { id: care; running: false }
    function test_idle_and_touch() {
        care.shiftEnabled=true; care.dimEnabled=true; care.busy=false;
        care.wake(1000); care.lastShift=1000;
        care.tick(60999); compare(care.dimmed,false);
        care.tick(61000); compare(care.dimmed,true);
        care.busy=true; care.tick(200000);
        compare(care.dimmed,false); compare(care.shiftIndex,0);
        care.busy=false; care.wake(200000); care.tick(202999);
        compare(care.shiftIndex,0);
        care.tick(203000); compare(care.shiftIndex,1);
        verify(Math.abs(care.targetX)<=2); verify(Math.abs(care.targetY)<=2);
        wait(100);
        care.busy=true;
        compare(care.visualX,Math.round(care.visualX));
        let frozen=care.visualX; wait(500); compare(care.visualX,frozen);
        care.wake(203001); compare(care.dimmed,false);
        care.shiftEnabled=false; compare(care.targetX,0); compare(care.targetY,0);
    }
}
