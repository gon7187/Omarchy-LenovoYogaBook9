#pragma once
#include <algorithm>
#include <utility>

// Keep the hotspot one logical pixel inside the monitor's exclusive far edges.
inline std::pair<double,double> confinePointer(double x,double y,double left,double top,double width,double height) {
    if (width<=0 || height<=0) return {x,y};
    return {std::clamp(x,left,left+std::max(0.0,width-1)),
            std::clamp(y,top,top+std::max(0.0,height-1))};
}
