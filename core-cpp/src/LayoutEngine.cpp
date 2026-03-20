#include "frostbar/LayoutEngine.hpp"

namespace frostbar {

LayoutDecision LayoutEngine::compute(const std::vector<MenuItem>& items, double availableWidth) const {
    LayoutDecision out;
    double used = 0.0;

    for (const auto& item : items) {
        if (item.pinnedHidden) {
            out.hidden.push_back(item.identifier);
            continue;
        }

        if (item.pinnedVisible) {
            out.visible.push_back(item.identifier);
            used += item.width;
            continue;
        }

        if (used + item.width <= availableWidth) {
            out.visible.push_back(item.identifier);
            used += item.width;
        } else {
            out.hidden.push_back(item.identifier);
        }
    }

    return out;
}

} // namespace frostbar
