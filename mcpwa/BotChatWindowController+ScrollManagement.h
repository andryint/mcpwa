//
//  BotChatWindowController+ScrollManagement.h
//  mcpwa
//
//  Scrolling, spacers, and layout management
//

#import "BotChatWindowController.h"

NS_ASSUME_NONNULL_BEGIN

@interface BotChatWindowController (ScrollManagement)

/// Scroll to bottom with delay for layout
- (void)scrollToBottom;

/// Scroll to bottom immediately
- (void)scrollToBottomImmediate;

/// Add spacer to position prompt bubble at top of view
- (void)addBottomSpacerForBubble:(NSView *)bubbleView;

/// Scroll to position prompt at top of visible area
- (void)scrollToPromptAtTop:(NSView *)bubbleView;

/// Remove the bottom spacer
- (void)removeBottomSpacer;

/// Update spacer height based on response content growth
- (void)updateSpacerForCurrentContent;

/// Recalculate spacer height after window resize
- (void)updateBottomSpacerHeight;

@end

NS_ASSUME_NONNULL_END
