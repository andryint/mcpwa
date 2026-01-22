//
//  BotChatWindowController+DelegateHandlers.m
//  mcpwa
//
//  Delegate handlers for GeminiClient and RAGClient
//

#import "BotChatWindowController+DelegateHandlers.h"
#import "BotChatWindowController+MessageRendering.h"
#import "BotChatWindowController+StreamingSupport.h"
#import "BotChatWindowController+MCPToolExecution.h"
#import "BotChatWindowController+ModeManagement.h"
#import "DebugConfigWindowController.h"

@implementation BotChatWindowController (DelegateHandlers)

#pragma mark - GeminiClientDelegate

- (void)geminiClient:(GeminiClient *)client didCompleteSendWithResponse:(GeminiChatResponse *)response {
    NSLog(@"[Gemini] didCompleteSendWithResponse - error: %@, text: %@, functionCalls: %lu",
          response.error ?: @"none",
          response.text ? @"yes" : @"no",
          (unsigned long)response.functionCalls.count);

    if (response.error) {
        [self addErrorMessage:response.error];
        [self setProcessing:NO];
        [self updateStatus:@"Error"];
        return;
    }

    // When toolExecutor is set, GeminiClient handles the tool loop internally.
    // This delegate is called for intermediate responses during the loop.
    if (client.toolExecutor) {
        // Show intermediate text alongside function calls if present
        if (response.text) {
            [self addBotMessage:response.text];
        }
        // Function calls are handled by the toolExecutor, no action needed here
        return;
    }

    // Legacy path: when toolExecutor is not set, handle function calls here
    if (response.hasFunctionCalls) {
        NSLog(@"[Gemini] Processing %lu function calls (legacy path)", (unsigned long)response.functionCalls.count);
        if (response.text) {
            [self addBotMessage:response.text];
        }
        [self handleFunctionCalls:response.functionCalls];
        return;
    }

    // No function calls - show text response and finish
    if (response.text) {
        [self addBotMessage:response.text];
    }
    [self setProcessing:NO];
    [self updateStatus:@"Ready"];
    [self generateTitleIfNeeded];
}

- (void)geminiClient:(GeminiClient *)client didCompleteToolLoopWithResponse:(GeminiChatResponse *)response {
    NSLog(@"[Gemini] didCompleteToolLoopWithResponse - error: %@, text: %@",
          response.error ?: @"none",
          response.text ? @"yes" : @"no");

    if (response.error) {
        [self addErrorMessage:response.error];
        [self setProcessing:NO];
        [self updateStatus:@"Error"];
        return;
    }

    // Tool loop completed - show final text response
    if (response.text) {
        [self addBotMessage:response.text];
    }
    [self setProcessing:NO];
    [self updateStatus:@"Ready"];
    [self generateTitleIfNeeded];
}

- (void)geminiClient:(GeminiClient *)client didFailWithError:(NSError *)error {
    [self addErrorMessage:error.localizedDescription];
    [self setProcessing:NO];
    [self updateStatus:@"Error"];
}

#pragma mark - Function Call Handling (Legacy)

- (void)handleFunctionCalls:(NSArray<GeminiFunctionCall *> *)calls {
    if (calls.count == 0) return;

    // Process function calls sequentially
    [self processFunctionCallAtIndex:0 calls:calls];
}

- (void)processFunctionCallAtIndex:(NSUInteger)index calls:(NSArray<GeminiFunctionCall *> *)calls {
    if (index >= calls.count) {
        NSLog(@"[Gemini] All function calls processed");
        return;
    }

    GeminiFunctionCall *call = calls[index];
    NSLog(@"[Gemini] Processing function call %lu/%lu: %@", (unsigned long)(index + 1), (unsigned long)calls.count, call.name);
    [self updateStatus:[self friendlyStatusForTool:call.name]];

    [self executeMCPTool:call.name args:call.args completion:^(NSString *result) {
        NSLog(@"[Gemini] Function %@ returned, sending result to Gemini", call.name);

        // Show function result in chat only if debug mode is enabled
        if ([DebugConfigWindowController showDebugInChatEnabled]) {
            [self addFunctionMessage:call.name result:result];
        }

        // Send result back to Gemini
        [self.geminiClient sendFunctionResult:call.name result:result];
        NSLog(@"[Gemini] sendFunctionResult called for %@", call.name);
    }];
}

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
            for (NSDictionary *source in response.sources) {
                // RAG API returns: chat_name, time_start, chat_id, is_group, participants, etc.
                NSString *chatName = source[@"chat_name"] ?: @"Unknown";
                NSString *timeStart = source[@"time_start"];

                // Format date from ISO format (e.g., "2025-12-24T17:18:00")
                NSString *dateStr = @"";
                if (timeStart.length >= 10) {
                    // Extract just the date portion (YYYY-MM-DD)
                    dateStr = [NSString stringWithFormat:@" [%@]", [timeStart substringToIndex:10]];
                }

                [responseText appendFormat:@"- %@%@\n", chatName, dateStr];
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
