#import <Cocoa/Cocoa.h>
#import "MCPServer.h"
#import "MCPTransport.h"

@interface AppDelegate : NSObject <NSApplicationDelegate, MCPServerDelegate>


@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSTextView *logView;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSButton *startStopButton;

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


@end
