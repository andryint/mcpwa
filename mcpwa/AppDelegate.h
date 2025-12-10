#import <Cocoa/Cocoa.h>
#import "MCPServer.h"

@interface AppDelegate : NSObject <NSApplicationDelegate, MCPServerDelegate>


@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSTextView *logView;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSButton *startStopButton;

- (void)appendLog:(NSString *)message;
- (void)appendLog:(NSString *)message color:(NSColor *)color;
- (IBAction) explore:(id)sender;
- (IBAction) runTests:(id)sender;

@end
