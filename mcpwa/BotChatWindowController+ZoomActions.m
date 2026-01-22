//
//  BotChatWindowController+ZoomActions.m
//  mcpwa
//
//  Cmd+/- zoom support for font sizing
//

#import "BotChatWindowController+ZoomActions.h"
#import "BotChatWindowController+ThemeHandling.h"

// Font size constants
const CGFloat kDefaultFontSize = 14.0;
const CGFloat kMinFontSize = 10.0;
const CGFloat kMaxFontSize = 24.0;
const CGFloat kFontSizeStep = 2.0;

@implementation BotChatWindowController (ZoomActions)

- (void)applyFontSize {
    // Save preference
    [[NSUserDefaults standardUserDefaults] setFloat:self.currentFontSize forKey:@"ChatFontSize"];

    // Update input text view font
    self.inputTextView.font = [NSFont systemFontOfSize:self.currentFontSize];
    self.placeholderLabel.font = [NSFont systemFontOfSize:self.currentFontSize];

    // Rebuild chat messages with new font size
    [self rebuildChatMessages];

    // Update input height
    [self updateInputHeight];
}

@end
