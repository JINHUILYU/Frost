#include <iostream>
#include <string>
#include <unordered_set>
#include <vector>

#include "../core-cpp/include/frostbar/LayoutEngine.hpp"
#include "../core-cpp/include/frostbar/MenuItem.hpp"
#include "../core-cpp/include/frostbar/PolicyEngine.hpp"

namespace {

bool expectVector(const std::vector<std::string>& actual,
                  const std::vector<std::string>& expected,
                  const std::string& label) {
    if (actual == expected) {
        return true;
    }

    std::cerr << "Mismatch in " << label << "\n";
    std::cerr << "Expected: ";
    for (const auto& value : expected) {
        std::cerr << value << " ";
    }
    std::cerr << "\nActual: ";
    for (const auto& value : actual) {
        std::cerr << value << " ";
    }
    std::cerr << "\n";
    return false;
}

frostbar::MenuItem makeItem(const std::string& id,
                            double width,
                            bool pinnedVisible = false,
                            bool pinnedHidden = false) {
    frostbar::MenuItem item;
    item.identifier = id;
    item.ownerApp = "test.app";
    item.width = width;
    item.pinnedVisible = pinnedVisible;
    item.pinnedHidden = pinnedHidden;
    return item;
}

} // namespace

int main() {
    frostbar::LayoutEngine engine;
    frostbar::PolicyEngine policyEngine;

    {
        std::vector<frostbar::MenuItem> items = {
            makeItem("wifi", 20.0),
            makeItem("clock", 30.0),
            makeItem("battery", 25.0)
        };

        frostbar::LayoutDecision decision = engine.compute(items, 50.0);
        if (!expectVector(decision.visible, {"wifi", "clock"}, "visible-basic")) {
            return 1;
        }
        if (!expectVector(decision.hidden, {"battery"}, "hidden-basic")) {
            return 1;
        }
    }

    {
        std::vector<frostbar::MenuItem> items = {
            makeItem("always-hidden", 10.0, false, true),
            makeItem("always-visible", 100.0, true, false),
            makeItem("normal", 10.0)
        };

        frostbar::LayoutDecision decision = engine.compute(items, 50.0);
        if (!expectVector(decision.visible, {"always-visible"}, "visible-pinned")) {
            return 1;
        }
        if (!expectVector(decision.hidden, {"always-hidden", "normal"}, "hidden-pinned")) {
            return 1;
        }
    }

    {
        std::vector<frostbar::MenuItem> items = {
            makeItem("a", 10.0),
            makeItem("b", 15.0)
        };
        frostbar::LayoutDecision first = engine.compute(items, 20.0);
        frostbar::LayoutDecision second = engine.compute(items, 20.0);
        if (!expectVector(first.visible, second.visible, "deterministic-visible")) {
            return 1;
        }
        if (!expectVector(first.hidden, second.hidden, "deterministic-hidden")) {
            return 1;
        }
    }

    {
        std::vector<frostbar::MenuItem> items = {
            makeItem("clock", 20.0),
            makeItem("wifi", 25.0),
            makeItem("battery", 30.0),
            makeItem("vpn", 10.0)
        };

        frostbar::PolicyConfig config;
        config.alwaysVisible = std::unordered_set<std::string>{"clock", "battery"};
        config.alwaysHidden = std::unordered_set<std::string>{"wifi"};
        config.autoRehide = std::unordered_set<std::string>{"vpn", "battery"};

        std::vector<frostbar::MenuItem> normalized = policyEngine.apply(items, config);
        frostbar::LayoutDecision decision = engine.compute(normalized, 40.0);

        // battery is in both alwaysVisible and autoRehide; alwaysVisible should win.
        if (!expectVector(decision.visible, {"clock", "battery"}, "visible-policy")) {
            return 1;
        }
        if (!expectVector(decision.hidden, {"wifi", "vpn"}, "hidden-policy")) {
            return 1;
        }
    }

    std::cout << "core_smoke_test passed\n";
    return 0;
}
