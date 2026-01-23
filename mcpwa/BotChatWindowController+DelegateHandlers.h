//
//  BotChatWindowController+DelegateHandlers.h
//  mcpwa
//
//  Delegate handlers for RAGClient
//

#import "BotChatWindowController.h"

NS_ASSUME_NONNULL_BEGIN

@interface BotChatWindowController (DelegateHandlers) <RAGClientDelegate>

#pragma mark - RAGClientDelegate

- (void)ragClient:(RAGClient *)client didReceiveStatusUpdate:(NSString *)stage message:(NSString *)message;
- (void)ragClient:(RAGClient *)client didReceiveStreamChunk:(NSString *)chunk;
- (void)ragClient:(RAGClient *)client didCompleteQueryWithResponse:(RAGQueryResponse *)response;
- (void)ragClient:(RAGClient *)client didCompleteSearchWithResponse:(RAGSearchResult *)response;
- (void)ragClient:(RAGClient *)client didFailWithError:(NSError *)error;

@end

NS_ASSUME_NONNULL_END
