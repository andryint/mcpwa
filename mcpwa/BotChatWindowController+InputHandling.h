//
//  BotChatWindowController+InputHandling.h
//  mcpwa
//
//  Input handling: send/stop actions, text view delegate, input height management
//

#import "BotChatWindowController.h"

NS_ASSUME_NONNULL_BEGIN

@interface BotChatWindowController (InputHandling) <NSTextViewDelegate>

/// Send the current message
- (void)sendMessage:(nullable id)sender;

/// Stop the current processing
- (void)stopProcessing:(nullable id)sender;

/// Update placeholder visibility based on input content
- (void)updatePlaceholder;

/// Update input container height based on text content
- (void)updateInputHeight;

@end

NS_ASSUME_NONNULL_END
