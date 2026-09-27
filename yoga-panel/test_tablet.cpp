#include "tablet.hpp"
#include <cassert>
#include <iostream>

int main() {
    // A keyboard leaving 500px of usable height must fit a bottom-overlapping float.
    assert((fitTabletWindow({100,400,700,600},{0,29,1440,471}) == TabletBox{100,29,700,471}));
    assert((fitTabletWindow({40,50,300,200},{0,29,900,800}) == TabletBox{40,50,300,200}));
    assert((fitTabletWindow({1000,700,600,300},{0,29,900,800}) == TabletBox{300,529,600,300}));
    TabletAutoShow state;
    using Action = TabletAutoShow::Action;
    assert(state.step(true,false,false) == Action::Show);
    assert(state.step(true,false,false) == Action::None); // IPC still starting
    assert(state.step(true,true,false) == Action::None);
    assert(state.step(true,false,false) == Action::None); // manual close stays closed
    assert(state.step(true,false,true) == Action::Show); // tapping the same field reopens
    state.step(true,true,false);
    assert(state.step(false,true,false) == Action::None);
    assert(state.step(false,true,false) == Action::None);
    assert(state.step(false,true,false) == Action::Hide);
    TabletAutoShow manual;
    manual.step(true,true,false);
    for (int i=0;i<4;++i) assert(manual.step(false,true,false) == Action::None);
    TabletAutoShow manualClose;
    manualClose.step(true,true,false);
    assert(manualClose.step(true,false,false) == Action::None);
    assert(manualClose.step(true,false,true) == Action::Show);
    TabletAutoShow moving;
    moving.step(true,false,false);
    moving.step(true,true,false);
    assert(moving.step(true,false,false) == Action::None);
    assert(moving.owned && !moving.dismissed);
    moving.step(true,true,false);
    moving.step(false,true,false);
    moving.step(false,true,false);
    assert(moving.step(false,true,false) == Action::Hide);
    TabletAutoShow rotating;
    rotating.step(true,false,false);
    rotating.step(true,true,false);
    for (int i=0;i<3;++i) assert(rotating.step(true,false,false) == Action::None);
    rotating.step(true,true,false);
    assert(rotating.owned && !rotating.dismissed);
    for (int i=0;i<5;++i) assert(rotating.step(true,false,false) == Action::None);
    assert(rotating.dismissed && !rotating.owned);
    TabletAutoShow retry;
    retry.step(true,false,false);
    for (int i=0;i<4;++i) assert(retry.step(true,false,false) == Action::None);
    assert(retry.step(true,false,false) == Action::Show); // failed launch gets another chance
    std::cout << "PASS: tablet geometry, dismissal, debounce, manual ownership and retry\n";
}
