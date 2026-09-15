#include "gesture.hpp"
#include <cassert>
int main() {
    ThreeFingerTap g;
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
}
