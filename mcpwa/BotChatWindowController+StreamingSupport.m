//
//  BotChatWindowController+StreamingSupport.m
//  mcpwa
//
//  Live streaming bubble support for real-time response display
//

#import "BotChatWindowController+StreamingSupport.h"
#import "BotChatWindowController+ThemeHandling.h"
#import "BotChatWindowController+ScrollManagement.h"
#import "BotChatWindowController+MarkdownParser.h"

@implementation BotChatWindowController (StreamingSupport)

- (void)createStreamingBubble {
    // Don't remove spacer yet - we'll shrink it as content grows

    // Reset response height tracking for new streaming session
    self.lastResponseBubbleHeight = 0;

    // Remove any existing streaming bubble
    if (self.streamingBubbleView) {
        [self.streamingBubbleView removeFromSuperview];
        self.streamingBubbleView = nil;
        self.streamingTextView = nil;
    }

    // Create container (same pattern as addMessageBubble for bot messages)
    NSView *bubbleContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    bubbleContainer.translatesAutoresizingMaskIntoConstraints = NO;

    // Create bubble background (bot style - no visible bubble)
    NSView *bubble = [[NSView alloc] initWithFrame:NSZeroRect];
    bubble.translatesAutoresizingMaskIntoConstraints = NO;
    bubble.wantsLayer = YES;
    bubble.layer.backgroundColor = [NSColor clearColor].CGColor;

    // Calculate max width as 3/4 of the chat view width
    CGFloat chatWidth = self.chatScrollView.bounds.size.width;
    if (chatWidth < 100) chatWidth = 500;
    CGFloat maxBubbleWidth = floor(chatWidth * 0.75);
    self.streamingMaxWidth = maxBubbleWidth;

    // Create NSTextView for streaming content with formatting support
    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, maxBubbleWidth, 20)];
    textView.translatesAutoresizingMaskIntoConstraints = NO;
    textView.editable = NO;
    textView.selectable = YES;
    textView.backgroundColor = [NSColor clearColor];
    textView.drawsBackground = NO;
    textView.textContainerInset = NSZeroSize;
    textView.textContainer.lineFragmentPadding = 0;
    textView.textContainer.widthTracksTextView = NO;
    textView.textContainer.containerSize = NSMakeSize(maxBubbleWidth, CGFLOAT_MAX);
    textView.verticallyResizable = YES;
    textView.horizontallyResizable = NO;

    [bubble addSubview:textView];
    [bubbleContainer addSubview:bubble];

    // Constraints for text view in bubble
    [NSLayoutConstraint activateConstraints:@[
        [textView.leadingAnchor constraintEqualToAnchor:bubble.leadingAnchor],
        [textView.trailingAnchor constraintEqualToAnchor:bubble.trailingAnchor],
        [textView.topAnchor constraintEqualToAnchor:bubble.topAnchor constant:4],
        [textView.bottomAnchor constraintEqualToAnchor:bubble.bottomAnchor constant:-4],
        [textView.widthAnchor constraintEqualToConstant:maxBubbleWidth]
    ]];

    // Constraints for bubble in container (left-aligned like bot messages)
    [NSLayoutConstraint activateConstraints:@[
        [bubble.leadingAnchor constraintEqualToAnchor:bubbleContainer.leadingAnchor],
        [bubble.topAnchor constraintEqualToAnchor:bubbleContainer.topAnchor],
        [bubble.bottomAnchor constraintEqualToAnchor:bubbleContainer.bottomAnchor]
    ]];

    // Add to stack view - insert before spacer if present
    if (self.bottomSpacerView) {
        NSUInteger spacerIndex = [self.chatStackView.arrangedSubviews indexOfObject:self.bottomSpacerView];
        [self.chatStackView insertArrangedSubview:bubbleContainer atIndex:spacerIndex];
    } else {
        [self.chatStackView addArrangedSubview:bubbleContainer];
    }
    [bubbleContainer.widthAnchor constraintEqualToAnchor:self.chatStackView.widthAnchor constant:-48].active = YES;

    // Store references for updates
    self.streamingBubbleView = bubbleContainer;
    self.streamingTextView = textView;

    // Update spacer height now that we have new content
    [self updateSpacerForCurrentContent];
    // Don't scroll during generation - keep prompt position stable
}

- (void)updateStreamingBubble:(NSString *)text {
    if (!self.streamingTextView) {
        return;
    }

    // Apply markdown formatting to the streaming text
    NSAttributedString *formattedText = [self attributedStringFromMarkdown:text textColor:primaryTextColor()];

    // Update the text view
    [self.streamingTextView.textStorage setAttributedString:formattedText];

    // Recalculate height based on content
    [self.streamingTextView.layoutManager ensureLayoutForTextContainer:self.streamingTextView.textContainer];
    NSRect usedRect = [self.streamingTextView.layoutManager usedRectForTextContainer:self.streamingTextView.textContainer];

    // Update the text view's frame height
    NSRect frame = self.streamingTextView.frame;
    frame.size.height = ceil(usedRect.size.height);
    self.streamingTextView.frame = frame;

    // Force layout update
    [self.streamingBubbleView setNeedsLayout:YES];
    [self.streamingBubbleView layoutSubtreeIfNeeded];

    // Update spacer as content grows
    [self updateSpacerForCurrentContent];

    // Force window to display NOW and process the display
    [self.window display];

    // Process any pending display operations in the run loop
    // This is critical - it actually flushes the graphics to screen
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.001, false);
    // Don't scroll during generation - keep prompt position stable
}

- (void)finalizeStreamingBubble {
    // The streaming bubble will be replaced by the final message in didCompleteQueryWithResponse
    // Just clear our references
    self.streamingBubbleView = nil;
    self.streamingTextView = nil;
}

@end
