//
//  BotChatWindowController+ScrollManagement.m
//  mcpwa
//
//  Scrolling, spacers, and layout management
//

#import "BotChatWindowController+ScrollManagement.h"

@implementation BotChatWindowController (ScrollManagement)

- (void)scrollToBottom {
    // Delay scroll to allow layout to complete
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self scrollToBottomImmediate];
    });
}

- (void)scrollToBottomImmediate {
    // Force layout
    [self.window layoutIfNeeded];

    // Scroll to bottom of document view
    NSView *documentView = self.chatScrollView.documentView;
    if (documentView) {
        // In non-flipped coordinates, the bottom is at y=0
        // We want to scroll so that the bottom of the document is visible
        NSPoint bottomPoint = NSMakePoint(0, 0);
        [documentView scrollPoint:bottomPoint];
    }
}

#pragma mark - Prompt-at-Top Scrolling (ChatGPT-style)

- (void)addBottomSpacerForBubble:(NSView *)bubbleView {
    // Remove existing spacer if any
    [self removeBottomSpacer];

    // Force layout to get accurate heights
    [self.window layoutIfNeeded];

    // Calculate spacer height accounting for stack view layout:
    // Stack view has: topInset(16) + bubble + spacing(12) + [other content] + spacer + bottomInset(16)
    CGFloat viewHeight = self.chatScrollView.bounds.size.height;
    CGFloat bubbleHeight = bubbleView.fittingSize.height;
    CGFloat topInset = 16;      // Stack view top edge inset
    CGFloat bottomInset = 16;   // Stack view bottom edge inset
    CGFloat stackSpacing = 12;  // Stack view spacing between items

    // Calculate total height of any content between user bubble and where spacer will be
    // This includes streaming bubble if present
    CGFloat additionalContentHeight = 0;
    NSArray *arrangedSubviews = self.chatStackView.arrangedSubviews;
    NSUInteger userBubbleIndex = [arrangedSubviews indexOfObject:bubbleView];
    if (userBubbleIndex != NSNotFound) {
        for (NSUInteger i = userBubbleIndex + 1; i < arrangedSubviews.count; i++) {
            NSView *view = arrangedSubviews[i];
            additionalContentHeight += view.fittingSize.height + stackSpacing;
        }
    }

    // Add extra spacing to fully hide previous content (the spacing between previous bubble and user bubble)
    CGFloat spacerHeight = viewHeight - topInset - bubbleHeight - stackSpacing - additionalContentHeight - bottomInset;

    // Only add spacer if it makes sense (content is smaller than view)
    if (spacerHeight <= 0) {
        // Content is larger than view, just scroll to show the bottom
        [self scrollToBottom];
        return;
    }

    // Create spacer view
    self.bottomSpacerView = [[NSView alloc] initWithFrame:NSZeroRect];
    self.bottomSpacerView.translatesAutoresizingMaskIntoConstraints = NO;

    // Add to stack view
    [self.chatStackView addArrangedSubview:self.bottomSpacerView];

    // Set width and height constraints
    [self.bottomSpacerView.widthAnchor constraintEqualToAnchor:self.chatStackView.widthAnchor constant:-48].active = YES;
    self.bottomSpacerHeightConstraint = [self.bottomSpacerView.heightAnchor constraintEqualToConstant:spacerHeight];
    self.bottomSpacerHeightConstraint.active = YES;

    // Scroll to bottom - with the spacer in place, this positions the prompt at the top
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self scrollToBottomImmediate];
    });
}

- (void)scrollToPromptAtTop:(NSView *)bubbleView {
    [self.window layoutIfNeeded];

    NSClipView *clipView = self.chatScrollView.contentView;
    NSView *documentView = self.chatScrollView.documentView;
    if (!documentView || !bubbleView || !clipView) return;

    // Convert bubble's frame to document view coordinates
    NSRect bubbleFrameInDoc = [bubbleView convertRect:bubbleView.bounds toView:documentView];

    // In non-flipped coordinates (Y increases upward, origin at bottom-left):
    // - bubbleFrameInDoc.origin.y is the BOTTOM of the bubble
    // - NSMaxY(bubbleFrameInDoc) is the TOP of the bubble
    //
    // We want the TOP of the bubble to appear near the top of the visible area (with some padding).
    // The clip view's bounds origin determines what part of the document is visible.
    // Setting bounds.origin.y = Y means Y is at the BOTTOM of the visible area.

    CGFloat visibleHeight = clipView.bounds.size.height;
    CGFloat topOfBubble = NSMaxY(bubbleFrameInDoc);
    CGFloat topPadding = 16;  // Padding from the top of the view

    // We want: the top of visible area = topOfBubble + topPadding
    // Visible area spans from scrollY (bottom) to scrollY + visibleHeight (top)
    // So: scrollY + visibleHeight = topOfBubble + topPadding
    // Therefore: scrollY = topOfBubble + topPadding - visibleHeight
    CGFloat scrollY = topOfBubble + topPadding - visibleHeight;

    // Clamp to valid range
    CGFloat documentHeight = documentView.bounds.size.height;
    CGFloat maxScrollY = documentHeight - visibleHeight;
    if (scrollY < 0) scrollY = 0;
    if (scrollY > maxScrollY && maxScrollY > 0) scrollY = maxScrollY;

    // Use scrollToPoint on clip view for more reliable scrolling
    [clipView scrollToPoint:NSMakePoint(0, scrollY)];
    [self.chatScrollView reflectScrolledClipView:clipView];
}

- (void)removeBottomSpacer {
    if (self.bottomSpacerView) {
        [self.chatStackView removeArrangedSubview:self.bottomSpacerView];
        [self.bottomSpacerView removeFromSuperview];
        self.bottomSpacerView = nil;
        self.bottomSpacerHeightConstraint = nil;
        self.lastUserBubble = nil;
    }
}

- (void)updateSpacerForCurrentContent {
    // Shrink spacer by the DELTA of response bubble height growth
    if (!self.bottomSpacerView) return;

    [self.window layoutIfNeeded];

    // Get current response bubble height (streaming bubble during generation)
    CGFloat currentResponseHeight = 0;

    if (self.streamingBubbleView) {
        currentResponseHeight = self.streamingBubbleView.fittingSize.height;
    }

    // On first call (lastResponseBubbleHeight == 0), just record the initial height.
    // Don't shrink spacer yet - the spacer was sized to position the prompt correctly.
    if (self.lastResponseBubbleHeight == 0) {
        self.lastResponseBubbleHeight = currentResponseHeight;
        return;
    }

    // Calculate how much the response has grown since last update
    CGFloat heightDelta = currentResponseHeight - self.lastResponseBubbleHeight;
    self.lastResponseBubbleHeight = currentResponseHeight;

    // Only shrink spacer if response grew
    if (heightDelta > 0) {
        CGFloat currentSpacerHeight = self.bottomSpacerHeightConstraint.constant;
        CGFloat newSpacerHeight = currentSpacerHeight - heightDelta;

        if (newSpacerHeight <= 0) {
            // Response has grown to fill the space - remove spacer
            [self removeBottomSpacer];
        } else {
            self.bottomSpacerHeightConstraint.constant = newSpacerHeight;
        }
    }
}

- (void)updateBottomSpacerHeight {
    if (!self.bottomSpacerView || !self.lastUserBubble) return;

    [self.window layoutIfNeeded];

    CGFloat viewHeight = self.chatScrollView.bounds.size.height;
    CGFloat bubbleHeight = self.lastUserBubble.fittingSize.height;
    CGFloat topInset = 16;
    CGFloat bottomInset = 16;
    CGFloat stackSpacing = 12;
    CGFloat spacerHeight = viewHeight - topInset - bubbleHeight - stackSpacing - bottomInset - stackSpacing;

    if (spacerHeight <= 0) {
        [self removeBottomSpacer];
    } else {
        self.bottomSpacerHeightConstraint.constant = spacerHeight;
    }
}

@end
