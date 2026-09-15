#include "gesture.hpp"
#include <cassert>
int main() {
    OpenPanelTap g;
    g.down(0,100,0.2,0.2);g.down(1,110,0.3,0.2);g.down(2,120,0.4,0.2);
    assert(!g.up(0,150));assert(!g.up(1,160));assert(g.up(2,170));
    g.down(0,200,0.2,0.2);assert(!g.up(0,230));
    g.down(0,300,0.2,0.2);g.down(1,310,0.3,0.2);assert(!g.up(0,330));assert(!g.up(1,340));
    g.down(0,400,0.2,0.2);g.down(1,410,0.3,0.2);g.down(2,420,0.4,0.2);
    g.motion(0,0.6,0.2);g.up(0,450);g.up(1,460);assert(!g.up(2,470));
    g.down(0,500,0.2,0.2);g.down(1,510,0.3,0.2);g.down(2,520,0.4,0.2);
    g.up(0,1100);g.up(1,1100);assert(!g.up(2,1100));
    g.down(0,1200,0.2,0.2);g.down(1,1210,0.3,0.2);g.down(2,1220,0.4,0.2);
    g.reset();assert(!g.up(2,1240));

    // Eight to ten simultaneous contacts tolerate staggered landing/lifting.
    for (int count : {8, 9, 10}) {
        for (int i=0;i<count;i++) g.down(i,2000+i*20,0.1+i*0.06,0.5);
        for (int i=0;i<count;i++) assert(g.up(i,2300+i*20)==(i==count-1));
    }
    for (int count : {4, 5, 6, 7, 11}) {
        for (int i=0;i<count;i++) g.down(i,3000+i*10,0.1+i*0.05,0.5);
        for (int i=0;i<count;i++) assert(!g.up(i,3200+i*10));
    }
    for (int i=0;i<10;i++) g.down(i,4000+i*10,0.1+i*0.05,0.5);
    g.motion(5,0.9,0.8);
    for (int i=0;i<10;i++) assert(!g.up(i,4300+i*10));
    for (int i=0;i<8;i++) g.down(i,5000+i*10,0.1+i*0.05,0.5);
    for (int i=0;i<8;i++) assert(!g.up(i,5900+i*10));
    // Late extra contacts must not reset the age of an already-held gesture.
    g.down(0,7000,0.2,0.5);
    for (int i=1;i<4;i++) g.down(i,7800+i*10,0.2+i*0.05,0.5);
    for (int i=0;i<4;i++) assert(!g.up(i,7900+i*10));
}
