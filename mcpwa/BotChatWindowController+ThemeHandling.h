//
//  BotChatWindowController+ThemeHandling.h
//  mcpwa
//
//  Theme colors and appearance update methods
//

#import "BotChatWindowController.h"

NS_ASSUME_NONNULL_BEGIN

// Theme-aware color helpers
BOOL isDarkMode(void);
NSColor *backgroundColor(void);
NSColor *inputBackgroundColor(void);
NSColor *userBubbleColor(void);
NSColor *botBubbleColor(void);
NSColor *functionBubbleColor(void);
NSColor *primaryTextColor(void);
NSColor *secondaryTextColor(void);

// Set reference window for color helpers
void setColorReferenceWindow(NSWindow * _Nullable window);

@interface BotChatWindowController (ThemeHandling)

/// Update all UI colors for the current appearance
- (void)updateColorsForAppearance;

/// Rebuild chat messages with updated colors
- (void)rebuildChatMessages;

@end

NS_ASSUME_NONNULL_END
