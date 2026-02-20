//
//  BotChatWindowController+DelegateHandlers.m
//  mcpwa
//
//  Delegate handlers for RAGClient
//

#import "BotChatWindowController+DelegateHandlers.h"
#import "BotChatWindowController+MessageRendering.h"
#import "BotChatWindowController+StreamingSupport.h"
#import "DebugConfigWindowController.h"

@implementation BotChatWindowController (DelegateHandlers)

#pragma mark - RAGClientDelegate

- (void)ragClient:(RAGClient *)client didReceiveStatusUpdate:(NSString *)stage message:(NSString *)message {
    // Update status line with pipeline stage information
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateStatus:message];
    });
}

- (void)ragClient:(RAGClient *)client didReceiveStreamChunk:(NSString *)chunk {
    // Use dispatch_sync to ensure UI update completes before processing next chunk
    // This forces the run loop to render each chunk before continuing
    dispatch_sync(dispatch_get_main_queue(), ^{
        // Append to streaming response
        [self.streamingResponse appendString:chunk];

        // Update the streaming bubble with accumulated text
        [self updateStreamingBubble:self.streamingResponse];

        // Update status to show we're generating
        [self updateStatus:@"Generating response..."];
    });
}

- (void)ragClient:(RAGClient *)client didCompleteQueryWithResponse:(RAGQueryResponse *)response {
    // Must dispatch to main thread for UI updates
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"[RAG UI] didCompleteQueryWithResponse called, isCancelled: %d, answer length: %lu",
              self.isCancelled, (unsigned long)response.answer.length);

        if (self.isCancelled) {
            NSLog(@"[RAG UI] Cancelled, returning early");
            return;
        }

        // Store sources for clickable reference lookup
        self.lastSources = response.sources;

        // Remove the streaming bubble - we'll replace it with the final formatted message
        NSLog(@"[RAG UI] Removing streaming bubble: %@", self.streamingBubbleView);
        if (self.streamingBubbleView) {
            [self.streamingBubbleView removeFromSuperview];
            [self finalizeStreamingBubble];
        }

        if (response.error) {
            NSLog(@"[RAG UI] Response has error: %@", response.error);
            [self addErrorMessage:response.error];
            [self setProcessing:NO];
            [self updateStatus:@"Error"];
            return;
        }

        // Build the response message
        NSMutableString *responseText = [NSMutableString string];

        if (response.answer.length > 0) {
            [responseText appendString:response.answer];
        }

        // Add sources if available
        if (response.sources.count > 0) {
            [responseText appendString:@"\n\n**Sources:**\n"];
            NSInteger sourceIndex = 1;

            // Check if Debug menu is visible (not hidden)
            BOOL showDebugInfo = NO;
            NSMenu *mainMenu = [NSApp mainMenu];
            for (NSMenuItem *item in mainMenu.itemArray) {
                if ([item.title isEqualToString:@"Debug"]) {
                    showDebugInfo = !item.hidden;
                    break;
                }
            }

            for (NSDictionary *source in response.sources) {
                // RAG API returns: chat_name, time_start, chat_id, is_group, participants, search_snippet, etc.
                NSString *chatName = [source[@"chat_name"] stringByReplacingOccurrencesOfString:@"_" withString:@" "] ?: @"Unknown";
                NSString *timeStart = source[@"time_start"];
                NSString *searchSnippet = source[@"search_snippet"];

                // Format date and time from ISO format (e.g., "2025-12-24T17:18:00")
                NSString *dateTimeStr = @"";
                if (timeStart.length >= 16) {
                    // Extract date and time (YYYY-MM-DD HH:MM)
                    NSString *datePart = [timeStart substringToIndex:10];
                    NSString *timePart = [timeStart substringWithRange:NSMakeRange(11, 5)];
                    dateTimeStr = [NSString stringWithFormat:@" [%@ %@]", datePart, timePart];
                } else if (timeStart.length >= 10) {
                    // Fallback to just date if time not available
                    dateTimeStr = [NSString stringWithFormat:@" [%@]", [timeStart substringToIndex:10]];
                }

                [responseText appendFormat:@"[%ld] %@%@\n", (long)sourceIndex, chatName, dateTimeStr];

                // Show search_snippet in debug mode
                if (showDebugInfo && searchSnippet.length > 0) {
                    [responseText appendFormat:@"    *%@*\n", searchSnippet];
                }

                sourceIndex++;
            }
        }

        NSLog(@"[RAG UI] Adding bot message, length: %lu", (unsigned long)responseText.length);
        @try {
            [self addBotMessage:responseText];
            NSLog(@"[RAG UI] addBotMessage completed");
        } @catch (NSException *exception) {
            NSLog(@"[RAG UI] EXCEPTION in addBotMessage: %@ - %@", exception.name, exception.reason);
        }
        NSLog(@"[RAG UI] Setting processing NO");
        [self setProcessing:NO];
        NSLog(@"[RAG UI] Updating status to Ready");
        [self updateStatus:@"Ready"];
        NSLog(@"[RAG UI] Generating title if needed");
        [self generateTitleIfNeeded];
        NSLog(@"[RAG UI] didCompleteQueryWithResponse finished");
    });
}

- (void)ragClient:(RAGClient *)client didCompleteSearchWithResponse:(RAGSearchResult *)response {
    if (self.isCancelled) return;

    if (response.error) {
        [self addErrorMessage:response.error];
        [self setProcessing:NO];
        [self updateStatus:@"Error"];
        return;
    }

    // Format search results
    NSMutableString *responseText = [NSMutableString stringWithString:@"**Search Results:**\n\n"];

    if (response.results.count == 0) {
        [responseText appendString:@"No results found."];
    } else {
        for (NSDictionary *result in response.results) {
            NSString *title = result[@"title"] ?: @"Untitled";
            NSString *content = result[@"content"] ?: result[@"text"] ?: @"";
            // Truncate long content
            if (content.length > 200) {
                content = [[content substringToIndex:197] stringByAppendingString:@"..."];
            }
            [responseText appendFormat:@"**%@**\n%@\n\n", title, content];
        }
    }

    [self addBotMessage:responseText];
    [self setProcessing:NO];
    [self updateStatus:@"Ready"];
}

- (void)ragClient:(RAGClient *)client didFailWithError:(NSError *)error {
    // Must dispatch to main thread for UI updates
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.isCancelled) return;

        // Remove streaming bubble if present
        if (self.streamingBubbleView) {
            [self.streamingBubbleView removeFromSuperview];
            [self finalizeStreamingBubble];
        }

        [self addErrorMessage:error.localizedDescription];
        [self setProcessing:NO];
        [self updateStatus:@"Error"];
    });
}

@end
