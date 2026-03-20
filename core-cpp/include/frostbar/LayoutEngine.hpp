#pragma once

#include <vector>

#include "MenuItem.hpp"

namespace frostbar {

struct LayoutDecision {
    std::vector<std::string> visible;
    std::vector<std::string> hidden;
};

class LayoutEngine {
public:
    LayoutDecision compute(const std::vector<MenuItem>& items, double availableWidth) const;
};

} // namespace frostbar
