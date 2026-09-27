#include "touch_transfer.hpp"

#include <cassert>

using YogaTouchTransfer::Box;

int main() {
    const Box screen{0,0,100,100};
    assert(YogaTouchTransfer::crossesSharedInnerEdge(screen,{100,0,100,100},99,50));
    assert(YogaTouchTransfer::crossesSharedInnerEdge(screen,{-100,0,100,100},1,50));
    assert(YogaTouchTransfer::crossesSharedInnerEdge(screen,{0,100,100,100},50,99));
    assert(YogaTouchTransfer::crossesSharedInnerEdge(screen,{0,-100,100,100},50,1));
    assert(!YogaTouchTransfer::crossesSharedInnerEdge(screen,{102,0,100,100},99,50));
    assert(!YogaTouchTransfer::crossesSharedInnerEdge(screen,{100,100,100,100},99,50));
    assert(!YogaTouchTransfer::crossesSharedInnerEdge(screen,{100,0,100,100},75,50));
}
