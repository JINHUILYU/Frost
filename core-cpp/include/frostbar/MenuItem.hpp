#pragma once

#include <string>

namespace frostbar {

struct MenuItem {
    std::string identifier;
    std::string ownerApp;
    double width = 0.0;
    bool pinnedVisible = false;
    bool pinnedHidden = false;
};

} // namespace frostbar
