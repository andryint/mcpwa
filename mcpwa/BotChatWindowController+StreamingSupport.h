//
//  BotChatWindowController+StreamingSupport.h
//  mcpwa
//
//  Live streaming bubble support for real-time response display
//

#import "BotChatWindowController.h"

NS_ASSUME_NONNULL_BEGIN

@interface BotChatWindowController (StreamingSupport)

/// Create an empty streaming bubble for live updates
- (void)createStreamingBubble;

/// Update the streaming bubble with new text content
- (void)updateStreamingBubble:(NSString *)text;

/// Finalize the streaming bubble (clear references)
- (void)finalizeStreamingBubble;

@end

NS_ASSUME_NONNULL_END
