#pragma once

#include <string>
#include <unordered_set>
#include <vector>

#include "MenuItem.hpp"

namespace frostbar {

struct PolicyConfig {
    std::unordered_set<std::string> alwaysHidden;
    std::unordered_set<std::string> alwaysVisible;
    std::unordered_set<std::string> autoRehide;
};

class PolicyEngine {
public:
    // Policy precedence: alwaysVisible > alwaysHidden > autoRehide > existing item flags.
    std::vector<MenuItem> apply(const std::vector<MenuItem>& items, const PolicyConfig& config) const;
};

} // namespace frostbar
