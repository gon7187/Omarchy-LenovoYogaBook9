#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <unordered_map>

// Observe a short 3-finger or 8–10-finger tap without grabbing touch events.
class OpenPanelTap {
    struct Point { double x, y; };
    std::unordered_map<int, Point> points;
    uint32_t started = 0;
    unsigned peak = 0;
    bool moved = false;
public:
    void reset() { points.clear(); peak=0; moved=false; }
    void down(int id, uint32_t time, double x, double y) {
        if (points.empty()) { reset(); started=time; }
        points[id]={x,y}; peak=std::max(peak,unsigned(points.size()));
    }
    void motion(int id, double x, double y) {
        auto p=points.find(id);
        if (p!=points.end() && std::hypot(x-p->second.x,y-p->second.y)>0.025) moved=true;
    }
    bool up(int id, uint32_t time) {
        if (!points.erase(id) || !points.empty()) return false;
        bool many=peak>=8 && peak<=10;
        bool fire=(peak==3 || many) && !moved && uint32_t(time-started)<=(many ? 800u : 500u);
        reset(); return fire;
    }
};
