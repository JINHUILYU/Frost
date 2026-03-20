#import "FrostBarBridge.h"

#include "frostbar/LayoutEngine.hpp"

@implementation FBMenuItemModel
@end

@implementation FBLayoutDecisionModel
@end

@implementation FrostBarBridge

+ (FBLayoutDecisionModel*)computeLayout:(NSArray<FBMenuItemModel*>*)items
                         availableWidth:(double)availableWidth {
    std::vector<frostbar::MenuItem> input;
    input.reserve(items.count);

    for (FBMenuItemModel* model in items) {
        frostbar::MenuItem item;
        item.identifier = model.identifier.UTF8String;
        item.ownerApp = model.ownerApp.UTF8String;
        item.width = model.width;
        item.pinnedVisible = model.pinnedVisible;
        item.pinnedHidden = model.pinnedHidden;
        input.push_back(item);
    }

    frostbar::LayoutEngine engine;
    frostbar::LayoutDecision decision = engine.compute(input, availableWidth);

    FBLayoutDecisionModel* output = [FBLayoutDecisionModel new];

    NSMutableArray<NSString*>* visible = [NSMutableArray arrayWithCapacity:decision.visible.size()];
    for (const auto& id : decision.visible) {
        [visible addObject:[NSString stringWithUTF8String:id.c_str()]];
    }

    NSMutableArray<NSString*>* hidden = [NSMutableArray arrayWithCapacity:decision.hidden.size()];
    for (const auto& id : decision.hidden) {
        [hidden addObject:[NSString stringWithUTF8String:id.c_str()]];
    }

    output.visible = visible;
    output.hidden = hidden;
    return output;
}

@end
