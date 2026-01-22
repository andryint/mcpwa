//
//  BotChatWindowController+ZoomActions.h
//  mcpwa
//
//  Cmd+/- zoom support for font sizing
//

#import "BotChatWindowController.h"

NS_ASSUME_NONNULL_BEGIN

// Font size constants
extern const CGFloat kDefaultFontSize;
extern const CGFloat kMinFontSize;
extern const CGFloat kMaxFontSize;
extern const CGFloat kFontSizeStep;

@interface BotChatWindowController (ZoomActions)

/// Apply current font size to UI elements
- (void)applyFontSize;

@end

NS_ASSUME_NONNULL_END
