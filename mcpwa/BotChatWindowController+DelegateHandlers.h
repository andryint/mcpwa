//
//  BotChatWindowController+DelegateHandlers.h
//  mcpwa
//
//  Delegate handlers for GeminiClient and RAGClient
//

#import "BotChatWindowController.h"

NS_ASSUME_NONNULL_BEGIN

@interface BotChatWindowController (DelegateHandlers) <GeminiClientDelegate, RAGClientDelegate>

#pragma mark - GeminiClientDelegate

- (void)geminiClient:(GeminiClient *)client didCompleteSendWithResponse:(GeminiChatResponse *)response;
- (void)geminiClient:(GeminiClient *)client didCompleteToolLoopWithResponse:(GeminiChatResponse *)response;
- (void)geminiClient:(GeminiClient *)client didFailWithError:(NSError *)error;

#pragma mark - Function Call Handling (Legacy)

/// Handle function calls from Gemini response (used when toolExecutor is not set)
- (void)handleFunctionCalls:(NSArray<GeminiFunctionCall *> *)calls;

/// Process a single function call at the given index (recursive for sequential execution)
- (void)processFunctionCallAtIndex:(NSUInteger)index calls:(NSArray<GeminiFunctionCall *> *)calls;

#pragma mark - RAGClientDelegate

- (void)ragClient:(RAGClient *)client didReceiveStatusUpdate:(NSString *)stage message:(NSString *)message;
- (void)ragClient:(RAGClient *)client didReceiveStreamChunk:(NSString *)chunk;
- (void)ragClient:(RAGClient *)client didCompleteQueryWithResponse:(RAGQueryResponse *)response;
- (void)ragClient:(RAGClient *)client didCompleteSearchWithResponse:(RAGSearchResult *)response;
- (void)ragClient:(RAGClient *)client didFailWithError:(NSError *)error;

@end

NS_ASSUME_NONNULL_END
