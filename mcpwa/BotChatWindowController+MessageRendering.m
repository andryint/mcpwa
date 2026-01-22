//
//  BotChatWindowController+MessageRendering.m
//  mcpwa
//
//  Message bubble creation and display
//

#import "BotChatWindowController+MessageRendering.h"
#import "BotChatWindowController+ThemeHandling.h"
#import "BotChatWindowController+ScrollManagement.h"
#import "BotChatWindowController+ZoomActions.h"

@implementation BotChatWindowController (MessageRendering)

#pragma mark - Message Display

- (void)addUserMessage:(NSString *)text {
    ChatDisplayMessage *msg = [[ChatDisplayMessage alloc] init];
    msg.type = ChatMessageTypeUser;
    msg.text = text;
    [self.messages addObject:msg];
    [self addMessageBubble:msg];
}

- (void)addBotMessage:(NSString *)text {
    NSLog(@"[RAG UI] addBotMessage START, text length: %lu", (unsigned long)text.length);
    ChatDisplayMessage *msg = [[ChatDisplayMessage alloc] init];
    msg.type = ChatMessageTypeBot;
    msg.text = text;
    [self.messages addObject:msg];
    NSLog(@"[RAG UI] addBotMessage calling addMessageBubble");
    [self addMessageBubble:msg];
    // Update spacer after adding content
    [self updateSpacerForCurrentContent];
    NSLog(@"[RAG UI] addBotMessage END");
}

- (void)addFunctionMessage:(NSString *)functionName result:(NSString *)result {
    ChatDisplayMessage *msg = [[ChatDisplayMessage alloc] init];
    msg.type = ChatMessageTypeFunction;
    msg.functionName = functionName;
    msg.text = result;
    [self.messages addObject:msg];
    [self addMessageBubble:msg];
    // Update spacer after adding content
    [self updateSpacerForCurrentContent];
}

- (void)addSystemMessage:(NSString *)text {
    ChatDisplayMessage *msg = [[ChatDisplayMessage alloc] init];
    msg.type = ChatMessageTypeSystem;
    msg.text = text;
    [self.messages addObject:msg];
    [self addMessageBubble:msg];
}

- (void)addErrorMessage:(NSString *)text {
    ChatDisplayMessage *msg = [[ChatDisplayMessage alloc] init];
    msg.type = ChatMessageTypeError;
    msg.text = text;
    [self.messages addObject:msg];
    [self addMessageBubble:msg];
}

- (void)addMessageBubble:(ChatDisplayMessage *)message {
    NSView *bubbleContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    bubbleContainer.translatesAutoresizingMaskIntoConstraints = NO;

    // Create bubble background
    NSView *bubble = [[NSView alloc] initWithFrame:NSZeroRect];
    bubble.translatesAutoresizingMaskIntoConstraints = NO;
    bubble.wantsLayer = YES;

    // Style based on message type
    NSColor *bubbleColor;
    NSColor *textColor;
    BOOL alignRight = NO;
    BOOL useMarkdown = NO;
    BOOL useBubbleStyle = YES;  // Whether to show bubble background
    NSString *displayText = message.text;
    CGFloat cornerRadius = 16;

    // Calculate max width as 3/4 of the chat view width
    CGFloat chatWidth = self.chatScrollView.bounds.size.width;
    if (chatWidth < 100) chatWidth = 500;  // Fallback if not yet laid out
    CGFloat maxBubbleWidth = floor(chatWidth * 0.75);
    CGFloat horizontalPadding = 14;
    CGFloat maxTextWidth = maxBubbleWidth - (horizontalPadding * 2);

    switch (message.type) {
        case ChatMessageTypeUser:
            // Claude-style user bubble: warm beige/tan, right-aligned
            bubbleColor = userBubbleColor();
            textColor = primaryTextColor();
            alignRight = YES;
            useBubbleStyle = YES;
            break;
        case ChatMessageTypeBot:
            // Claude-style: no bubble, just text on the left spanning 3/4 width
            bubbleColor = [NSColor clearColor];
            textColor = primaryTextColor();
            useMarkdown = YES;
            useBubbleStyle = NO;  // No bubble background for bot
            horizontalPadding = 0;
            maxTextWidth = maxBubbleWidth;  // Full 3/4 width for text (no padding)
            break;
        case ChatMessageTypeFunction:
            bubbleColor = functionBubbleColor();
            textColor = [NSColor whiteColor]; // Always white on purple
            if (message.functionName) {
                displayText = [NSString stringWithFormat:@"[%@]\n%@", message.functionName, message.text];
            }
            cornerRadius = 8;
            break;
        case ChatMessageTypeError:
            // Muted red for errors
            if (isDarkMode()) {
                bubbleColor = [NSColor colorWithRed:0.5 green:0.2 blue:0.2 alpha:1.0];
            } else {
                bubbleColor = [NSColor colorWithRed:0.95 green:0.9 blue:0.9 alpha:1.0];
            }
            textColor = isDarkMode() ? [NSColor whiteColor] : [NSColor colorWithRed:0.6 green:0.2 blue:0.2 alpha:1.0];
            cornerRadius = 8;
            break;
        case ChatMessageTypeSystem:
            // System messages: subtle, muted appearance, wider (90% width)
            if (isDarkMode()) {
                bubbleColor = [NSColor colorWithWhite:0.2 alpha:1.0];
            } else {
                bubbleColor = [NSColor colorWithRed:0.96 green:0.95 blue:0.93 alpha:1.0];
            }
            textColor = secondaryTextColor();
            cornerRadius = 8;
            maxBubbleWidth = floor(chatWidth * 0.90);  // Wider for system messages
            maxTextWidth = maxBubbleWidth - (horizontalPadding * 2);
            break;
    }

    bubble.layer.cornerRadius = useBubbleStyle ? cornerRadius : 0;

    // Build attributed string first to measure it properly
    NSAttributedString *attributedText;
    if (useMarkdown) {
        attributedText = [self attributedStringFromMarkdown:displayText textColor:textColor];
    } else {
        CGFloat fontSize = self.currentFontSize;
        NSFont *font = (message.type == ChatMessageTypeFunction) ?
            [NSFont monospacedSystemFontOfSize:fontSize - 3 weight:NSFontWeightRegular] :
            [NSFont systemFontOfSize:fontSize];
        NSDictionary *attrs = @{
            NSFontAttributeName: font,
            NSForegroundColorAttributeName: textColor
        };
        attributedText = [[NSAttributedString alloc] initWithString:displayText attributes:attrs];
    }

    // Calculate text size using boundingRect - this is the most reliable method
    NSRect boundingRect = [attributedText boundingRectWithSize:NSMakeSize(maxTextWidth, CGFLOAT_MAX)
                                                       options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading];
    CGFloat textWidth = ceil(boundingRect.size.width);
    CGFloat textHeight = ceil(boundingRect.size.height);

    // Ensure minimum height based on font
    CGFloat minHeight = ceil(self.currentFontSize * 1.5);
    if (textHeight < minHeight) textHeight = minHeight;

    // Create text view with calculated size
    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, textWidth, textHeight)];
    textView.translatesAutoresizingMaskIntoConstraints = NO;
    textView.editable = NO;
    textView.selectable = YES;
    textView.backgroundColor = [NSColor clearColor];
    textView.drawsBackground = NO;
    textView.textContainerInset = NSZeroSize;
    textView.textContainer.lineFragmentPadding = 0;
    textView.textContainer.widthTracksTextView = NO;
    textView.textContainer.containerSize = NSMakeSize(maxTextWidth, CGFLOAT_MAX);
    textView.verticallyResizable = NO;
    textView.horizontallyResizable = NO;

    // Enable clickable links
    textView.automaticLinkDetectionEnabled = NO;
    [textView setLinkTextAttributes:@{
        NSForegroundColorAttributeName: [NSColor linkColor],
        NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
        NSCursorAttributeName: [NSCursor pointingHandCursor]
    }];

    // Set the text content
    [textView.textStorage setAttributedString:attributedText];

    bubble.layer.backgroundColor = bubbleColor.CGColor;

    [bubble addSubview:textView];
    [bubbleContainer addSubview:bubble];

    // Padding for text inside bubble
    CGFloat verticalPadding = useBubbleStyle ? 10 : 4;

    // Cap text width to max
    CGFloat actualTextWidth = MIN(textWidth, maxTextWidth);

    // Constraints for text view in bubble
    [NSLayoutConstraint activateConstraints:@[
        [textView.leadingAnchor constraintEqualToAnchor:bubble.leadingAnchor constant:horizontalPadding],
        [textView.trailingAnchor constraintEqualToAnchor:bubble.trailingAnchor constant:-horizontalPadding],
        [textView.topAnchor constraintEqualToAnchor:bubble.topAnchor constant:verticalPadding],
        [textView.bottomAnchor constraintEqualToAnchor:bubble.bottomAnchor constant:-verticalPadding],
        [textView.widthAnchor constraintEqualToConstant:actualTextWidth],
        [textView.heightAnchor constraintEqualToConstant:textHeight]
    ]];

    // Constraints for bubble in container
    if (alignRight) {
        // User messages: right-aligned, bubble hugs content
        [NSLayoutConstraint activateConstraints:@[
            [bubble.trailingAnchor constraintEqualToAnchor:bubbleContainer.trailingAnchor]
        ]];
    } else {
        // Bot/other messages: left-aligned
        [NSLayoutConstraint activateConstraints:@[
            [bubble.leadingAnchor constraintEqualToAnchor:bubbleContainer.leadingAnchor]
        ]];
    }

    [NSLayoutConstraint activateConstraints:@[
        [bubble.topAnchor constraintEqualToAnchor:bubbleContainer.topAnchor],
        [bubble.bottomAnchor constraintEqualToAnchor:bubbleContainer.bottomAnchor]
    ]];

    // Add to stack view - insert before spacer if present (for non-user messages)
    if (message.type != ChatMessageTypeUser && self.bottomSpacerView) {
        NSUInteger spacerIndex = [self.chatStackView.arrangedSubviews indexOfObject:self.bottomSpacerView];
        [self.chatStackView insertArrangedSubview:bubbleContainer atIndex:spacerIndex];
    } else {
        [self.chatStackView addArrangedSubview:bubbleContainer];
    }

    // Container spans full width (margins handled by stackView edgeInsets)
    [bubbleContainer.widthAnchor constraintEqualToAnchor:self.chatStackView.widthAnchor constant:-48].active = YES;

    // ChatGPT-style scrolling: for user messages, add spacer to position prompt at top
    if (message.type == ChatMessageTypeUser) {
        self.lastUserBubble = bubbleContainer;
        // Add spacer after a short delay to allow layout
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self addBottomSpacerForBubble:bubbleContainer];
        });
    }
    // Don't scroll for non-user messages - keep prompt position stable during generation
}

@end
