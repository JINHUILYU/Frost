#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FBMenuItemModel : NSObject
@property (nonatomic, copy) NSString* identifier;
@property (nonatomic, copy) NSString* ownerApp;
@property (nonatomic, assign) double width;
@property (nonatomic, assign) BOOL pinnedVisible;
@property (nonatomic, assign) BOOL pinnedHidden;
@end

@interface FBLayoutDecisionModel : NSObject
@property (nonatomic, copy) NSArray<NSString*>* visible;
@property (nonatomic, copy) NSArray<NSString*>* hidden;
@end

@interface FrostBarBridge : NSObject
+ (FBLayoutDecisionModel*)computeLayout:(NSArray<FBMenuItemModel*>*)items
                         availableWidth:(double)availableWidth;
@end

NS_ASSUME_NONNULL_END
