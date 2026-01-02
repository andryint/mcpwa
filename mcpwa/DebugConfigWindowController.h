// DebugConfigWindowController.h
// Debug Configuration Window Controller

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// NSUserDefaults keys for debug settings
extern NSString *const WADebugLogAccessibilityKey;
extern NSString *const WADebugShowInChatKey;

@interface DebugConfigWindowController : NSWindowController

+ (instancetype)sharedController;

- (void)showWindow;
- (void)toggleWindow;

/// Whether to log Accessibility API calls (default: YES)
@property (class, readonly) BOOL logAccessibilityEnabled;

/// Whether to show debug info in chat view (default: NO)
@property (class, readonly) BOOL showDebugInChatEnabled;

@end

NS_ASSUME_NONNULL_END
