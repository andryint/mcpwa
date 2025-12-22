#import <Cocoa/Cocoa.h>
#import "MCPServer.h"
#import "MCPTransport.h"

@interface AppDelegate : NSObject <NSApplicationDelegate, MCPServerDelegate>


@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSTextView *logView;
@property (nonatomic, strong) NSTextField *statusLabel;

- (void)appendLog:(NSString *)message;
- (void)appendLog:(NSString *)message color:(NSColor *)color;

#pragma mark - Debug Actions
- (IBAction)explore:(id)sender;
- (IBAction)runTests:(id)sender;
- (IBAction)testGlobalSearch:(id)sender;
- (IBAction)testGlobalSearchCustom:(id)sender;
- (IBAction)testClearSearch:(id)sender;
- (IBAction)debugGetSearchResults:(id)sender;
- (IBAction)debugSearchAndParse:(id)sender;
- (IBAction)debugClickResult0:(id)sender;
- (IBAction)debugClickResult1:(id)sender;
- (IBAction)debugClickResult2:(id)sender;
- (IBAction)debugTestParsing:(id)sender;
- (IBAction)debugClickEsc:(id)sender;
- (IBAction)debugClickCmdF:(id)sender;
- (IBAction)debugClickA:(id)sender;
- (IBAction)debugClickX:(id)sender;
- (IBAction)debugTypeInABC:(id)sender;
- (IBAction)debugReadChatList:(id)sender;


@end
