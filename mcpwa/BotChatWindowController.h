//
//  BotChatWindowController.h
//  mcpwa
//
//  Bot Chat Window - Gemini-powered chat with WhatsApp MCP integration
//

#import <Cocoa/Cocoa.h>
#import "GeminiClient.h"

NS_ASSUME_NONNULL_BEGIN

@interface BotChatWindowController : NSWindowController <GeminiClientDelegate, NSTextFieldDelegate>

/// Shared instance (singleton pattern for easy access)
+ (instancetype)sharedController;

/// Show the bot chat window
- (void)showWindow;

/// Hide the bot chat window
- (void)hideWindow;

/// Toggle window visibility
- (void)toggleWindow;

/// Check if window is currently visible
@property (nonatomic, readonly) BOOL isVisible;

/// Zoom actions (responds to View menu items)
- (IBAction)zoomIn:(id)sender;
- (IBAction)zoomOut:(id)sender;
- (IBAction)zoomToActualSize:(id)sender;

@end

NS_ASSUME_NONNULL_END
