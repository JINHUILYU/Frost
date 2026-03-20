#include "../include/frostbar/PolicyEngine.hpp"

namespace frostbar {

std::vector<MenuItem> PolicyEngine::apply(const std::vector<MenuItem>& items,
                                          const PolicyConfig& config) const {
    std::vector<MenuItem> out;
    out.reserve(items.size());

    for (const auto& item : items) {
        MenuItem normalized = item;
        const bool isAlwaysVisible = config.alwaysVisible.find(item.identifier) != config.alwaysVisible.end();
        const bool isAlwaysHidden = config.alwaysHidden.find(item.identifier) != config.alwaysHidden.end();
        const bool isAutoRehide = config.autoRehide.find(item.identifier) != config.autoRehide.end();

        if (isAlwaysVisible) {
            normalized.pinnedVisible = true;
            normalized.pinnedHidden = false;
        } else if (isAlwaysHidden || isAutoRehide) {
            normalized.pinnedVisible = false;
            normalized.pinnedHidden = true;
        }

        out.push_back(normalized);
    }

    return out;
}

} // namespace frostbar
