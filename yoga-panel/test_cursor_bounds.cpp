#include "cursor_bounds.hpp"
#include <cassert>

int main() {
    using Point=std::pair<double,double>;
    assert(confinePointer(400,300,0,0,1440,900)==Point(400,300));
    assert(confinePointer(400,900,0,0,1440,900)==Point(400,899));
    assert(confinePointer(500,1800,0,0,1440,900)==Point(500,899));
    assert(confinePointer(-10,-10,0,0,1440,900)==Point(0,0));
    assert(confinePointer(2000,500,0,0,1440,900)==Point(1439,500));
    // Monitor coordinates can be negative, scaled, or rotated.
    assert(confinePointer(0,2000,-900,100,900,1440)==Point(-1,1539));
    assert(confinePointer(500,900,0,0,960,600)==Point(500,599));
    assert(confinePointer(50,50,10,20,0,900)==Point(50,50));
}
