#pragma once
#include <algorithm>
#include <array>

using TabletBox = std::array<double,4>;

inline TabletBox fitTabletWindow(TabletBox box, const TabletBox& area) {
    if (area[2]<=0 || area[3]<=0) return box;
    for (int axis=0;axis<2;++axis) {
        box[axis+2]=std::min(box[axis+2],area[axis+2]);
        box[axis]=std::clamp(box[axis],area[axis],area[axis]+area[axis+2]-box[axis+2]);
    }
    return box;
}

// The mapped layer acknowledges show requests; a manual close suppresses reopen
// until a fresh field activation or tap. Failed IPC is retried after one second.
struct TabletAutoShow {
    enum class Action { None, Show, Hide };
    bool owned=false, dismissed=false, wasVisible=false;
    int idle=0, pending=0;

    Action step(bool wanted, bool visible, bool tapped, bool relocated=false) {
        // Changing a layer's output briefly unmaps it; this is not a manual close.
        if (relocated && owned) { wasVisible=false; pending=5; }
        if (!wanted) {
            dismissed=false; wasVisible=visible;
            if (++idle>=3 && owned) { owned=false; pending=0; return Action::Hide; }
            return Action::None;
        }
        idle=0;
        if (wasVisible && !visible) dismissed=true;
        wasVisible=visible;
        if (visible) { pending=0; return Action::None; }
        if (tapped) dismissed=false;
        if (pending>0) {
            if (--pending>0) return Action::None;
            owned=false;
        } else if (owned) owned=false;
        if (dismissed) return Action::None;
        owned=true; pending=5;
        return Action::Show;
    }
};
