//
//  BotChatWindowController+InputHandling.m
//  mcpwa
//
//  Input handling: send/stop actions, text view delegate, input height management
//

#import "BotChatWindowController+InputHandling.h"
#import "BotChatWindowController+MessageRendering.h"
#import "BotChatWindowController+StreamingSupport.h"
#import "DebugConfigWindowController.h"

@implementation BotChatWindowController (InputHandling)

#pragma mark - Actions

- (void)sendMessage:(id)sender {
    NSString *text = [self.inputTextView.string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0 || self.isProcessing) return;

    // Save the first user message for title generation
    if (!self.firstUserMessage) {
        self.firstUserMessage = text;
    }

    self.isCancelled = NO;
    self.inputTextView.string = @"";
    [self updatePlaceholder];
    [self updateInputHeight];
    [self addUserMessage:text];
    [self setProcessing:YES];

    // Route to appropriate backend based on current mode
    if (self.currentChatMode == WAChatModeRAG) {
        [self updateStatus:@"Querying knowledge base..."];
        [self.streamingResponse setString:@""];
        [self createStreamingBubble];  // Create empty bubble for streaming
        // Use selected model for RAG query
        [self.ragClient queryStream:text k:0 chatFilter:0 model:self.selectedRAGModelId systemPrompt:nil];
    } else {
        [self updateStatus:@"Thinking..."];
        [self.geminiClient sendMessage:text];
    }
}

- (void)stopProcessing:(id)sender {
    // Set cancellation flag first
    self.isCancelled = YES;

    // Cancel the current request based on mode
    if (self.currentChatMode == WAChatModeRAG) {
        [self.ragClient cancelRequest];
    } else {
        // Cancel the current Gemini request
        [self.geminiClient cancelRequest];
        // Clear conversation history to prevent stale function call chains
        [self.geminiClient clearHistory];
    }

    // Reset processing state
    [self setProcessing:NO];
    [self updateStatus:@"Stopped"];

    // Add a system message indicating the request was cancelled
    [self addSystemMessage:@"Request cancelled."];
}

#pragma mark - NSTextViewDelegate

- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    if (commandSelector == @selector(insertNewline:)) {
        // Shift+Enter or Option+Enter inserts a newline, plain Enter sends
        NSEvent *event = [NSApp currentEvent];
        if (event.modifierFlags & (NSEventModifierFlagShift | NSEventModifierFlagOption)) {
            return NO; // Let the text view handle it (insert newline)
        }
        [self sendMessage:nil];
        return YES;
    }
    return NO;
}

- (void)textDidChange:(NSNotification *)notification {
    [self updatePlaceholder];
    [self updateInputHeight];
}

#pragma mark - Input Management

- (void)updatePlaceholder {
    // Show/hide placeholder based on text content
    self.placeholderLabel.hidden = (self.inputTextView.string.length > 0);
}

- (void)updateInputHeight {
    // Calculate required height for the text
    NSLayoutManager *layoutManager = self.inputTextView.layoutManager;
    NSTextContainer *textContainer = self.inputTextView.textContainer;

    [layoutManager ensureLayoutForTextContainer:textContainer];
    NSRect usedRect = [layoutManager usedRectForTextContainer:textContainer];

    // Account for text container insets
    CGFloat textHeight = ceil(usedRect.size.height) + self.inputTextView.textContainerInset.height * 2;

    // Minimum height of one line (~28), maximum of ~150 (about 6 lines)
    CGFloat minTextHeight = 28;
    CGFloat maxTextHeight = 150;
    CGFloat clampedTextHeight = MAX(minTextHeight, MIN(maxTextHeight, textHeight));

    // Calculate total input container height (text area + bottom row for status/model)
    CGFloat bottomRowHeight = 30; // status label + padding
    CGFloat padding = 20; // top and bottom padding
    CGFloat newContainerHeight = clampedTextHeight + bottomRowHeight + padding;

    // Only animate if height changed
    if (fabs(self.inputContainerHeightConstraint.constant - newContainerHeight) > 1) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.15;
            context.allowsImplicitAnimation = YES;
            self.inputContainerHeightConstraint.constant = newContainerHeight;
            [self.window layoutIfNeeded];
        } completionHandler:nil];
    }
}

@end
