//
//  BotChatWindowController+MessageRendering.h
//  mcpwa
//
//  Message bubble creation and display
//

#import "BotChatWindowController.h"

NS_ASSUME_NONNULL_BEGIN

@interface BotChatWindowController (MessageRendering)

/// Add a user message to the chat
- (void)addUserMessage:(NSString *)text;

/// Add a bot response message to the chat
- (void)addBotMessage:(NSString *)text;

/// Add a function call result message
- (void)addFunctionMessage:(NSString *)functionName result:(NSString *)result;

/// Add a system message (mode changes, etc.)
- (void)addSystemMessage:(NSString *)text;

/// Add an error message
- (void)addErrorMessage:(NSString *)text;

/// Add a message bubble to the chat (core bubble rendering)
- (void)addMessageBubble:(ChatDisplayMessage *)message;

@end

NS_ASSUME_NONNULL_END
