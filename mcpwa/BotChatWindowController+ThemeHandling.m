//
//  BotChatWindowController+ThemeHandling.m
//  mcpwa
//
//  Theme colors and appearance update methods
//

#import "BotChatWindowController+ThemeHandling.h"

// Claude-style light mode colors
// User bubble: warm beige/tan (Claude style)
#define kUserBubbleColorLight [NSColor colorWithRed:0.91 green:0.87 blue:0.82 alpha:1.0]  // #E8DDD2
#define kUserBubbleColorDark [NSColor colorWithWhite:0.22 alpha:1.0]                       // Dark charcoal (matches reference)

// Bot bubble: white with subtle appearance (Claude style)
#define kBotBubbleColorLight [NSColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:1.0]      // Pure white
#define kBotBubbleColorDark [NSColor colorWithWhite:0.22 alpha:1.0]                        // Dark gray

// Function bubble color (muted purple)
#define kFunctionBubbleColor [NSColor colorWithRed:0.45 green:0.38 blue:0.55 alpha:1.0]

// Claude-style background colors
#define kBackgroundColorLight [NSColor colorWithRed:0.98 green:0.976 blue:0.969 alpha:1.0]  // #FAF9F7
#define kBackgroundColorDark [NSColor colorWithWhite:0.12 alpha:1.0]

// Input area background
#define kInputBackgroundColorLight [NSColor colorWithRed:0.98 green:0.976 blue:0.969 alpha:1.0]
#define kInputBackgroundColorDark [NSColor colorWithWhite:0.15 alpha:1.0]

// Text colors
#define kTextColorLight [NSColor colorWithRed:0.2 green:0.18 blue:0.16 alpha:1.0]          // Dark brown
#define kTextColorDark [NSColor colorWithWhite:0.92 alpha:1.0]
#define kSecondaryTextColorLight [NSColor colorWithRed:0.45 green:0.42 blue:0.4 alpha:1.0]
#define kSecondaryTextColorDark [NSColor colorWithWhite:0.6 alpha:1.0]

// Global reference for color helpers (set when window is created)
static NSWindow *_colorReferenceWindow = nil;

void setColorReferenceWindow(NSWindow *window) {
    _colorReferenceWindow = window;
}

// Helper to check if current appearance is dark (based on app's theme setting)
BOOL isDarkMode(void) {
    NSAppearance *appearance = _colorReferenceWindow ? _colorReferenceWindow.effectiveAppearance : [NSApp effectiveAppearance];
    if (@available(macOS 10.14, *)) {
        NSAppearanceName name = [appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
        return [name isEqualToString:NSAppearanceNameDarkAqua];
    }
    return NO;
}

// Theme-aware color helpers
NSColor *backgroundColor(void) {
    return isDarkMode() ? kBackgroundColorDark : kBackgroundColorLight;
}

NSColor *inputBackgroundColor(void) {
    return isDarkMode() ? kInputBackgroundColorDark : kInputBackgroundColorLight;
}

NSColor *userBubbleColor(void) {
    return isDarkMode() ? kUserBubbleColorDark : kUserBubbleColorLight;
}

NSColor *botBubbleColor(void) {
    return isDarkMode() ? kBotBubbleColorDark : kBotBubbleColorLight;
}

NSColor *functionBubbleColor(void) {
    return kFunctionBubbleColor;
}

NSColor *primaryTextColor(void) {
    return isDarkMode() ? kTextColorDark : kTextColorLight;
}

NSColor *secondaryTextColor(void) {
    return isDarkMode() ? kSecondaryTextColorDark : kSecondaryTextColorLight;
}

#pragma mark - BotChatWindowController (ThemeHandling)

@implementation BotChatWindowController (ThemeHandling)

- (void)updateColorsForAppearance {
    // Update window background
    self.window.backgroundColor = backgroundColor();

    // Update content view
    NSView *contentView = self.window.contentView;
    contentView.layer.backgroundColor = backgroundColor().CGColor;

    // Update title bar
    self.titleBarView.layer.backgroundColor = backgroundColor().CGColor;
    self.titleLabel.textColor = primaryTextColor();

    // Update chat scroll view
    self.chatScrollView.backgroundColor = backgroundColor();

    // Update input container
    self.inputContainer.layer.backgroundColor = inputBackgroundColor().CGColor;

    // Update status label
    self.statusLabel.textColor = secondaryTextColor();

    // Update placeholder
    self.placeholderLabel.textColor = secondaryTextColor();

    // Update input text view - background, text color, and border
    self.inputTextView.textColor = primaryTextColor();
    self.inputTextView.insertionPointColor = primaryTextColor();
    if (isDarkMode()) {
        self.inputTextView.backgroundColor = [NSColor colorWithWhite:0.18 alpha:1.0];
        self.inputTextView.layer.borderWidth = 0;
        self.inputTextView.layer.borderColor = nil;
    } else {
        self.inputTextView.backgroundColor = [NSColor whiteColor];
        self.inputTextView.layer.borderWidth = 1.0;
        self.inputTextView.layer.borderColor = [NSColor colorWithWhite:0.85 alpha:1.0].CGColor;
    }

    // Update send/stop button colors
    NSColor *accentColor = isDarkMode() ?
        [NSColor colorWithRed:0.85 green:0.75 blue:0.65 alpha:1.0] :
        [NSColor colorWithRed:0.45 green:0.38 blue:0.32 alpha:1.0];
    self.sendButton.layer.backgroundColor = accentColor.CGColor;
    self.stopButton.layer.backgroundColor = accentColor.CGColor;

    // Update mode indicator
    [self updateModeIndicator];

    // Rebuild all chat messages to update bubble colors
    [self rebuildChatMessages];

    // Force redraw
    [self.window.contentView setNeedsDisplay:YES];
}

- (void)rebuildChatMessages {
    // Remove all existing bubble views
    for (NSView *view in [self.chatStackView.arrangedSubviews copy]) {
        [self.chatStackView removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    // Re-add all messages with updated colors
    for (ChatDisplayMessage *message in self.messages) {
        [self addMessageBubble:message];
    }
}

- (void)updateModeIndicator {
    if (self.currentChatMode == WAChatModeRAG) {
        self.modeIndicator.stringValue = @"RAG";
        // Blue color for RAG mode
        if (isDarkMode()) {
            self.modeIndicator.backgroundColor = [NSColor colorWithRed:0.2 green:0.4 blue:0.7 alpha:1.0];
            self.modeIndicator.textColor = [NSColor whiteColor];
        } else {
            self.modeIndicator.backgroundColor = [NSColor colorWithRed:0.85 green:0.9 blue:1.0 alpha:1.0];
            self.modeIndicator.textColor = [NSColor colorWithRed:0.2 green:0.4 blue:0.7 alpha:1.0];
        }
        // Show RAG model selector, hide MCP model selector
        self.modelSelector.hidden = YES;
        self.ragModelSelector.hidden = NO;
    } else {
        self.modeIndicator.stringValue = @"MCP";
        // Green color for MCP mode
        if (isDarkMode()) {
            self.modeIndicator.backgroundColor = [NSColor colorWithRed:0.2 green:0.5 blue:0.3 alpha:1.0];
            self.modeIndicator.textColor = [NSColor whiteColor];
        } else {
            self.modeIndicator.backgroundColor = [NSColor colorWithRed:0.85 green:0.95 blue:0.88 alpha:1.0];
            self.modeIndicator.textColor = [NSColor colorWithRed:0.2 green:0.5 blue:0.3 alpha:1.0];
        }
        // Show MCP model selector, hide RAG model selector
        self.modelSelector.hidden = NO;
        self.ragModelSelector.hidden = YES;
    }
}

@end
