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
#import "WAAccessibility.h"
#import "WALogger.h"

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

    // Send to backend
    [self updateStatus:@"Querying backend..."];
    [self.streamingResponse setString:@""];
    [self createStreamingBubble];  // Create empty bubble for streaming
    // Use selected model for query
    [self.ragClient queryStream:text k:0 chatFilter:0 model:self.selectedRAGModelId systemPrompt:nil];
}

- (void)stopProcessing:(id)sender {
    // Set cancellation flag first
    self.isCancelled = YES;

    // Cancel the current request
    [self.ragClient cancelRequest];

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

- (BOOL)textView:(NSTextView *)textView clickedOnLink:(id)link atIndex:(NSUInteger)charIndex {
    // Handle wasource:// links (clickable source references)
    NSURL *url = nil;
    if ([link isKindOfClass:[NSURL class]]) {
        url = link;
    } else if ([link isKindOfClass:[NSString class]]) {
        url = [NSURL URLWithString:link];
    }

    if (!url || ![[url scheme] isEqualToString:@"wasource"]) {
        return NO;  // Let default handling take care of regular links
    }

    // Extract source index from wasource://N
    NSInteger sourceIndex = [[url host] integerValue];
    if (sourceIndex <= 0) {
        [WALogger warn:@"[Source Link] Invalid source index: %@", [url host]];
        return YES;
    }

    // Look up source in lastSources (1-based index)
    NSArray<NSDictionary *> *sources = self.lastSources;
    if (!sources || sourceIndex > (NSInteger)sources.count) {
        [WALogger warn:@"[Source Link] Source index %ld out of range (have %lu sources)",
            (long)sourceIndex, (unsigned long)sources.count];
        return YES;
    }

    NSDictionary *source = sources[sourceIndex - 1];
    NSString *chatName = source[@"chat_name"];
    NSString *timeStart = source[@"time_start"];
    NSString *searchSnippet = source[@"search_snippet"];

    if (!chatName) {
        [WALogger warn:@"[Source Link] No chat_name in source %ld", (long)sourceIndex];
        return YES;
    }

    [WALogger info:@"[Source Link] Navigating to source [%ld]: chat='%@', time='%@', snippet='%@'",
        (long)sourceIndex, chatName, timeStart ?: @"unknown",
        searchSnippet.length > 40 ? [[searchSnippet substringToIndex:40] stringByAppendingString:@"..."] : (searchSnippet ?: @"none")];

    // Navigate on background thread (WAAccessibility uses sleeps)
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        WAAccessibility *wa = [WAAccessibility shared];
        BOOL success = [wa navigateToChat:chatName nearDate:timeStart searchSnippet:searchSnippet];
        if (success) {
            [WALogger info:@"[Source Link] Successfully navigated to source [%ld] in chat '%@'",
                (long)sourceIndex, chatName];
        } else {
            [WALogger error:@"[Source Link] Failed to navigate to source [%ld] in chat '%@'",
                (long)sourceIndex, chatName];
        }
    });

    return YES;  // We handled this link
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
