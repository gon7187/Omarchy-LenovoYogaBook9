#pragma once

#include <algorithm>
#include <cmath>

namespace YogaTouchTransfer {
    struct Box {
        double x, y, w, h;
    };

    inline bool crossesSharedInnerEdge(const Box& source, const Box& target, double x, double y, double edge=24.0, double tolerance=1.0) {
        const auto overlaps = [](double value, double first, double firstSize, double second, double secondSize) {
            return value >= std::max(first,second) && value <= std::min(first + firstSize,second + secondSize);
        };
        if (source.w <= 0 || source.h <= 0 || target.w <= 0 || target.h <= 0)
            return false;
        if (std::abs(source.x + source.w - target.x) <= tolerance)
            return x >= source.x + source.w - edge && x <= source.x + source.w && overlaps(y,source.y,source.h,target.y,target.h);
        if (std::abs(target.x + target.w - source.x) <= tolerance)
            return x >= source.x && x <= source.x + edge && overlaps(y,source.y,source.h,target.y,target.h);
        if (std::abs(source.y + source.h - target.y) <= tolerance)
            return y >= source.y + source.h - edge && y <= source.y + source.h && overlaps(x,source.x,source.w,target.x,target.w);
        if (std::abs(target.y + target.h - source.y) <= tolerance)
            return y >= source.y && y <= source.y + edge && overlaps(x,source.x,source.w,target.x,target.w);
        return false;
    }
}
