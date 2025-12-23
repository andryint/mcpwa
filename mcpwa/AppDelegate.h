#import <Cocoa/Cocoa.h>
#import "MCPServer.h"
#import "MCPTransport.h"

@interface AppDelegate : NSObject <NSApplicationDelegate, MCPServerDelegate>


@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSTextView *logView;
@property (nonatomic, strong) NSTextField *statusLabel;

- (void)appendLog:(NSString *)message;
- (void)appendLog:(NSString *)message color:(NSColor *)color;

#pragma mark - Debug Menu Actions
- (IBAction)debugExplore:(id)sender;
- (IBAction)debugRunTests:(id)sender;
- (IBAction)debugGlobalSearch:(id)sender;
- (IBAction)debugGlobalSearchCustom:(id)sender;
- (IBAction)debugOpenChat:(id)sender;
- (IBAction)debugClearSearch:(id)sender;
- (IBAction)debugClipboardPaste:(id)sender;
- (IBAction)debugCharacterTyping:(id)sender;
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
- (IBAction)debugGetCurrentChat:(id)sender;

#pragma mark - Chat Filter Debug Actions
- (IBAction)debugGetChatFilter:(id)sender;
- (IBAction)debugSetFilterAll:(id)sender;
- (IBAction)debugSetFilterUnread:(id)sender;
- (IBAction)debugSetFilterFavorites:(id)sender;
- (IBAction)debugSetFilterGroups:(id)sender;
- (IBAction)debugListChatsWithFilter:(id)sender;

@end
