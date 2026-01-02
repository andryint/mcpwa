//
//  AppDelegate.m
//  mcpwa
//
//  MCP Server for WhatsApp Desktop - Cocoa App with logging UI
//

#import "AppDelegate.h"
#import "MCPServer.h"
#import "MCPSocketTransport.h"
#import "MCPStdioTransport.h"
#import "WAAccessibility.h"
#import "WAAccessibilityExplorer.h"
#import "WAAccessibilityTest.h"
#import "WALogger.h"
#import "BotChatWindowController.h"
#import "DebugConfigWindowController.h"
#import "SettingsWindowController.h"

@interface AppDelegate ()
@property (nonatomic, strong) MCPServer *server;
@property (nonatomic, assign) BOOL serverRunning;
@property (nonatomic, assign) MCPTransportType transportType;
@property (nonatomic, strong) NSString *customSocketPath;
@property (nonatomic, strong) BotChatWindowController *botChatController;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self parseCommandLineArguments];
    [self setupLogWindow];
    [self checkInitialStatus];

    // Apply saved theme preference
    [SettingsWindowController applyThemeToAllWindows];

    // Subscribe to WALogger notifications
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleLogNotification:)
                                                 name:WALogNotification
                                               object:nil];

    // Auto-start server on launch
    [self startServer];

    // Show Bot Chat as main window
    self.botChatController = [BotChatWindowController sharedController];
    [self.botChatController showWindow];
}

- (void)parseCommandLineArguments {
    NSArray *args = [[NSProcessInfo processInfo] arguments];
    
    // Default to socket transport
    self.transportType = MCPTransportTypeSocket;
    self.customSocketPath = nil;
    
    for (NSUInteger i = 1; i < args.count; i++) {
        NSString *arg = args[i];
        
        if ([arg isEqualToString:@"--stdio"]) {
            self.transportType = MCPTransportTypeStdio;
        }
        else if ([arg isEqualToString:@"--socket"]) {
            self.transportType = MCPTransportTypeSocket;
            // Check for optional path argument
            if (i + 1 < args.count && ![args[i + 1] hasPrefix:@"--"]) {
                self.customSocketPath = args[i + 1];
                i++;
            }
        }
    }
}

- (void)setupLogWindow {
    // Create log window (secondary, shown on demand with Cmd+B)
    NSRect frame = NSMakeRect(100, 100, 800, 500);
    NSWindowStyleMask style = NSWindowStyleMaskTitled |
    NSWindowStyleMaskClosable |
    NSWindowStyleMaskMiniaturizable |
    NSWindowStyleMaskResizable;

    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:style
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.title = @"WhatsApp Connector - Log";
    self.window.minSize = NSMakeSize(600, 400);

    // Enable title bar accessory view
    self.window.titleVisibility = NSWindowTitleHidden;

    // Create container view to center the label vertically
    NSView *statusContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 350, 28)];

    // Create status label for title bar
    self.statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 4, 350, 18)];
    self.statusLabel.bezeled = NO;
    self.statusLabel.editable = NO;
    self.statusLabel.selectable = NO;
    self.statusLabel.backgroundColor = NSColor.clearColor;
    self.statusLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    self.statusLabel.stringValue = @"● Checking status...";
    self.statusLabel.alignment = NSTextAlignmentCenter;
    [statusContainer addSubview:self.statusLabel];

    // Create accessory view controller for title bar
    NSTitlebarAccessoryViewController *accessoryVC = [[NSTitlebarAccessoryViewController alloc] init];
    accessoryVC.view = statusContainer;
    accessoryVC.layoutAttribute = NSLayoutAttributeRight;
    [self.window addTitlebarAccessoryViewController:accessoryVC];

    // Create content view with padding
    NSView *contentView = self.window.contentView;

    // === Log area ===
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(10, 10, 780, 490)];
    scrollView.hasVerticalScroller = YES;
    scrollView.hasHorizontalScroller = NO;
    scrollView.autohidesScrollers = YES;
    scrollView.borderType = NSBezelBorder;
    scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    self.logView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 780, 380)];
    self.logView.editable = NO;
    self.logView.selectable = YES;
    self.logView.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    self.logView.backgroundColor = [NSColor colorWithWhite:0.1 alpha:1.0];
    self.logView.textColor = [NSColor colorWithWhite:0.9 alpha:1.0];
    self.logView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.logView setMaxSize:NSMakeSize(FLT_MAX, FLT_MAX)];
    [self.logView setVerticallyResizable:YES];
    [self.logView setHorizontallyResizable:NO];
    self.logView.textContainer.widthTracksTextView = YES;

    scrollView.documentView = self.logView;
    [contentView addSubview:scrollView];

    // Do NOT show log window on startup - it opens on demand with Cmd+B

    // Welcome message
    [self appendLog:@"╔══════════════════════════════════════════════════════════════╗" color:NSColor.cyanColor];
    [self appendLog:@"║           WhatsApp Connector v1.0                            ║" color:NSColor.cyanColor];
    [self appendLog:@"║   MCP Server for WhatsApp Desktop via Accessibility API      ║" color:NSColor.cyanColor];
    [self appendLog:@"╚══════════════════════════════════════════════════════════════╝" color:NSColor.cyanColor];
    [self appendLog:@""];
}

- (void)checkInitialStatus {
    WAAccessibility *wa = [WAAccessibility shared];

    // Check if accessibility is trusted
    BOOL hasPermission = AXIsProcessTrusted();

    // Check screen recording permission (required on macOS Sonoma+ for some AX operations)
    BOOL hasScreenRecording = CGPreflightScreenCaptureAccess();

    BOOL isAvailable = [wa isWhatsAppAvailable];

    // If not available on first check, try to ensure WhatsApp is visible
    if (hasPermission && !isAvailable) {
        [self appendLog:@"WhatsApp not immediately available, trying to make visible..."];
        if ([wa ensureWhatsAppVisible]) {
            isAvailable = [wa isWhatsAppAvailable];
        }
    }

    [self appendLog:@"Startup checks:"];
    [self appendLog:[NSString stringWithFormat:@"  • Accessibility permission: %@",
                     hasPermission ? @"✅ Granted" : @"❌ Not granted"]
              color:hasPermission ? NSColor.greenColor : NSColor.redColor];
    [self appendLog:[NSString stringWithFormat:@"  • Screen Recording permission: %@",
                     hasScreenRecording ? @"✅ Granted" : @"⚠️ Not granted (may be needed)"]
              color:hasScreenRecording ? NSColor.greenColor : NSColor.yellowColor];
    [self appendLog:[NSString stringWithFormat:@"  • WhatsApp accessible: %@",
                     isAvailable ? @"✅ Yes" : @"⚠️ No"]
              color:isAvailable ? NSColor.greenColor : NSColor.yellowColor];
    [self appendLog:@""];

    [self updateStatusLabel];

    if (!hasPermission) {
        [self appendLog:@"⚠️  Please grant Accessibility permission:" color:NSColor.yellowColor];
        [self appendLog:@"   System Settings → Privacy & Security → Accessibility" color:NSColor.yellowColor];
        [self appendLog:@"   Add and enable this app, then click 'Check Status'" color:NSColor.yellowColor];
        [self appendLog:@""];
    }

    if (hasPermission && !isAvailable) {
        [self appendLog:@"ℹ️  Launch WhatsApp Desktop to enable message reading" color:NSColor.systemBlueColor];
        if (!hasScreenRecording) {
            [self appendLog:@"   If WhatsApp is running, try granting Screen Recording permission:" color:NSColor.systemBlueColor];
            [self appendLog:@"   System Settings → Privacy & Security → Screen Recording" color:NSColor.systemBlueColor];
        }
        [self appendLog:@""];
    }
}

- (void)updateStatusLabel {
    BOOL hasPermission = AXIsProcessTrusted();
    BOOL isAvailable = [[WAAccessibility shared] isWhatsAppAvailable];

    NSString *icon;
    NSString *text;

    if (!hasPermission) {
        icon = @"🔴";
        text = @" Accessibility permission required";
    } else if (!isAvailable) {
        icon = @"🟡";
        text = @" WhatsApp not running or not accessible";
    } else if (self.serverRunning) {
        if (self.server.isConnected) {
            icon = @"🟢";
            text = @" Server running - Client connected";
        } else {
            icon = @"🟡";
            text = @" Server running - Waiting for client...";
        }
    } else {
        icon = @"🟢";
        text = @" Ready";
    }

    // Create attributed string with colored emoji and dark text
    NSMutableAttributedString *attrStr = [[NSMutableAttributedString alloc] initWithString:icon];
    NSDictionary *textAttrs = @{
        NSForegroundColorAttributeName: NSColor.labelColor,
        NSFontAttributeName: self.statusLabel.font
    };
    NSAttributedString *textPart = [[NSAttributedString alloc] initWithString:text attributes:textAttrs];
    [attrStr appendAttributedString:textPart];

    self.statusLabel.attributedStringValue = attrStr;
}

#pragma mark - Actions

- (void)startServer {
    BOOL hasPermission = AXIsProcessTrusted();
    
    if (!hasPermission) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Accessibility Permission Required";
        alert.informativeText = @"Please grant Accessibility permission in System Settings → Privacy & Security → Accessibility, then try again.";
        alert.alertStyle = NSAlertStyleWarning;
        [alert addButtonWithTitle:@"Open System Settings"];
        [alert addButtonWithTitle:@"Cancel"];
        
        if ([alert runModal] == NSAlertFirstButtonReturn) {
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]];
        }
        return;
    }
    
    [self appendLog:@"Starting MCP server..." color:NSColor.cyanColor];
    
    // Create transport based on configuration
    id<MCPTransport> transport;
    NSString *transportDesc;
    
    if (self.transportType == MCPTransportTypeStdio) {
        transport = [[MCPStdioTransport alloc] init];
        transportDesc = @"stdio";
    } else {
        if (self.customSocketPath) {
            transport = [[MCPSocketTransport alloc] initWithSocketPath:self.customSocketPath];
            transportDesc = [NSString stringWithFormat:@"socket: %@", self.customSocketPath];
        } else {
            transport = [[MCPSocketTransport alloc] init];
            transportDesc = [NSString stringWithFormat:@"socket: %@", kMCPDefaultSocketPath];
        }
    }
    
    self.server = [[MCPServer alloc] initWithTransport:transport delegate:self];
    
    NSError *error = nil;
    if (![self.server start:&error]) {
        [self appendLog:[NSString stringWithFormat:@"❌ Failed to start server: %@", error.localizedDescription]
                  color:NSColor.redColor];
        self.server = nil;
        return;
    }
    
    self.serverRunning = YES;
    [self updateStatusLabel];
    
    [self appendLog:[NSString stringWithFormat:@"✅ Server started - listening on %@", transportDesc]
              color:NSColor.greenColor];
    [self appendLog:@"   Waiting for client connection..." color:NSColor.systemGrayColor];
    [self appendLog:@""];
}

- (void)stopServer {
    [self appendLog:@"Stopping MCP server..." color:NSColor.yellowColor];
    
    [self.server stop];
    self.server = nil;
    
    self.serverRunning = NO;
    [self updateStatusLabel];
    
    [self appendLog:@"Server stopped" color:NSColor.yellowColor];
    [self appendLog:@""];
}

#pragma mark - MCPServerDelegate (connection events)

- (void)serverDidConnect {
    [self updateStatusLabel];
}

- (void)serverDidDisconnect {
    [self updateStatusLabel];
}

- (void)checkPermissions:(id)sender {
    [self appendLog:@"Checking status..." color:NSColor.cyanColor];

    // MCP Server status
    if (self.serverRunning) {
        [self appendLog:@"  • MCP Server: ✅ Running" color:NSColor.greenColor];
        if (self.server.isConnected) {
            [self appendLog:@"  • MCP Client: ✅ Connected" color:NSColor.greenColor];
        } else {
            [self appendLog:@"  • MCP Client: ⏳ Waiting for connection..." color:NSColor.yellowColor];
        }
    } else {
        [self appendLog:@"  • MCP Server: ⚠️ Not running" color:NSColor.yellowColor];
    }

    BOOL hasPermission = AXIsProcessTrusted();
    WAAccessibility *wa = [WAAccessibility shared];
    BOOL isAvailable = [wa isWhatsAppAvailable];

    [self appendLog:[NSString stringWithFormat:@"  • Accessibility: %@",
                     hasPermission ? @"✅ Granted" : @"❌ Not granted"]
              color:hasPermission ? NSColor.greenColor : NSColor.redColor];
    [self appendLog:[NSString stringWithFormat:@"  • WhatsApp: %@",
                     isAvailable ? @"✅ Available" : @"⚠️ Not available"]
              color:isAvailable ? NSColor.greenColor : NSColor.yellowColor];

    if (hasPermission && isAvailable) {
        // Quick test - get chats
        NSArray<WAChat *> *chats = [wa getRecentChats];
        [self appendLog:[NSString stringWithFormat:@"  • Chat access: ✅ Found %lu chats", (unsigned long)chats.count]
                  color:NSColor.greenColor];

        // Show first few chat names
        for (NSInteger i = 0; i < MIN(3, chats.count); i++) {
            [self appendLog:[NSString stringWithFormat:@"      → %@", chats[i].name]
                      color:NSColor.systemGrayColor];
        }
        if (chats.count > 3) {
            [self appendLog:[NSString stringWithFormat:@"      ... and %lu more", (unsigned long)(chats.count - 3)]
                      color:NSColor.systemGrayColor];
        }
    }

    [self appendLog:@""];
    [self updateStatusLabel];
}

#pragma mark - Logging

- (void)appendLog:(NSString *)message {
    [self appendLog:message color:nil];
}

- (void)appendLog:(NSString *)message color:(NSColor *)color {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *timestamp = [self currentTimestamp];
        NSString *line = message.length > 0 ?
        [NSString stringWithFormat:@"[%@] %@\n", timestamp, message] :
        @"\n";
        
        NSColor *textColor = color ?: [NSColor colorWithWhite:0.85 alpha:1.0];
        NSDictionary *attrs = @{
            NSForegroundColorAttributeName: textColor,
            NSFontAttributeName: [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular]
        };
        
        NSAttributedString *attrString = [[NSAttributedString alloc] initWithString:line attributes:attrs];
        
        [self.logView.textStorage appendAttributedString:attrString];
        [self.logView scrollToEndOfDocument:nil];
    });
}

- (NSString *)currentTimestamp {
    static NSDateFormatter *formatter = nil;
    if (!formatter) {
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"HH:mm:ss";
    }
    return [formatter stringFromDate:[NSDate date]];
}

#pragma mark - UI Helpers

- (NSString *)showInputDialogWithTitle:(NSString *)title
                               message:(NSString *)message
                           placeholder:(NSString *)placeholder
                          defaultValue:(NSString *)defaultValue {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = message;
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
    input.stringValue = defaultValue ?: @"";
    input.placeholderString = placeholder;
    alert.accessoryView = input;
    [alert.window setInitialFirstResponder:input];

    if ([alert runModal] == NSAlertFirstButtonReturn && input.stringValue.length > 0) {
        return input.stringValue;
    }
    return nil;
}

#pragma mark - WALogger Integration

- (void)handleLogNotification:(NSNotification *)notification {
    NSString *message = notification.userInfo[@"message"];
    NSString *level = notification.userInfo[@"level"];
    
    NSColor *color;
    if ([level isEqualToString:@"ERROR"]) {
        color = NSColor.redColor;
    } else if ([level isEqualToString:@"WARN"]) {
        color = NSColor.yellowColor;
    } else if ([level isEqualToString:@"INFO"]) {
        color = NSColor.cyanColor;
    } else {
        color = [NSColor colorWithWhite:0.6 alpha:1.0];  // DEBUG - dimmer
    }
    
    NSString *logMessage = [NSString stringWithFormat:@"[%@] %@", level, message];
    [self appendLog:logMessage color:color];
}

#pragma mark - Application Lifecycle

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    if (self.serverRunning) {
        [self stopServer];
    }
}

#pragma mark - Menu Actions

- (IBAction)uninstallApp:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Uninstall mcpwa?";
    alert.informativeText = @"This will remove mcpwa from Claude Desktop and quit the app. You can then drag mcpwa to Trash.";
    [alert addButtonWithTitle:@"Uninstall"];
    [alert addButtonWithTitle:@"Cancel"];

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [self removeFromClaudeConfig];

        NSAlert *done = [[NSAlert alloc] init];
        done.messageText = @"mcpwa unregistered";
        done.informativeText = @"You can now drag mcpwa from Applications to Trash.";
        [done runModal];

        [NSApp terminate:nil];
    }
}

- (void)removeFromClaudeConfig {
    NSString *configPath = [NSHomeDirectory() stringByAppendingPathComponent:
        @"Library/Application Support/Claude/claude_desktop_config.json"];

    NSData *data = [NSData dataWithContentsOfFile:configPath];
    if (!data) return;

    NSError *error;
    NSMutableDictionary *config = [NSJSONSerialization JSONObjectWithData:data
        options:NSJSONReadingMutableContainers error:&error];
    if (!config) return;

    NSMutableDictionary *servers = config[@"mcpServers"];
    if (servers && servers[@"mcpwa"]) {
        [servers removeObjectForKey:@"mcpwa"];

        NSData *newData = [NSJSONSerialization dataWithJSONObject:config
            options:NSJSONWritingPrettyPrinted error:&error];
        [newData writeToFile:configPath atomically:YES];
    }
}

#pragma mark - Debug Menu Actions

- (IBAction)debugExplore:(id)sender {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *path = [@"~/Desktop/whatsapp_ax.txt" stringByExpandingTildeInPath];
        [WAAccessibilityExplorer exploreToFile:path];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:path]];
        });
    });
}

- (IBAction)debugRunTests:(id)sender {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [WAAccessibilityTest runAllTests];
    });
}

- (IBAction)debugGlobalSearch:(id)sender {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [WAAccessibilityTest testGlobalSearch:@"SCB"];
    });
}

- (IBAction)debugGlobalSearchCustom:(id)sender {
    // Create alert with two fields: search query and filter
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Global Search Test";
    alert.informativeText = @"Enter search query and optional filter:";
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    // Create container view for both fields
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 250, 70)];

    // Search query field
    NSTextField *queryLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 46, 60, 20)];
    queryLabel.stringValue = @"Query:";
    queryLabel.bezeled = NO;
    queryLabel.editable = NO;
    queryLabel.drawsBackground = NO;
    [container addSubview:queryLabel];

    NSTextField *queryInput = [[NSTextField alloc] initWithFrame:NSMakeRect(60, 44, 185, 24)];
    queryInput.placeholderString = @"Enter search term...";
    [container addSubview:queryInput];

    // Filter popup button
    NSTextField *filterLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 10, 60, 20)];
    filterLabel.stringValue = @"Filter:";
    filterLabel.bezeled = NO;
    filterLabel.editable = NO;
    filterLabel.drawsBackground = NO;
    [container addSubview:filterLabel];

    NSPopUpButton *filterPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(60, 8, 185, 26) pullsDown:NO];
    [filterPopup addItemWithTitle:@"All"];
    [filterPopup addItemWithTitle:@"Unread"];
    [filterPopup addItemWithTitle:@"Favorites"];
    [filterPopup addItemWithTitle:@"Groups"];
    [container addSubview:filterPopup];

    alert.accessoryView = container;
    [alert.window setInitialFirstResponder:queryInput];

    if ([alert runModal] == NSAlertFirstButtonReturn && queryInput.stringValue.length > 0) {
        NSString *query = queryInput.stringValue;
        NSString *filter = [[filterPopup.titleOfSelectedItem lowercaseString] copy];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [WAAccessibilityTest testGlobalSearchWithFilter:query filter:filter];
        });
    }
}

- (IBAction)debugOpenChat:(id)sender {
    NSString *name = [self showInputDialogWithTitle:@"Open Chat"
                                            message:@"Enter chat name:"
                                        placeholder:@"Enter chat name..."
                                       defaultValue:@""];
    if (name) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [WAAccessibilityTest testOpenChat:name];
        });
    }
}

- (IBAction)debugClearSearch:(id)sender {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [WAAccessibilityTest testClearSearch];
    });
}

- (IBAction)debugClipboardPaste:(id)sender {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [WAAccessibilityTest testClipboardPaste:@"SCB"];
    });
}

- (IBAction)debugCharacterTyping:(id)sender {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [WAAccessibilityTest testCharacterTyping:@"SCB"];
    });
}

- (IBAction)debugGetSearchResults:(id)sender {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [WAAccessibilityTest testGetSearchResults];
    });
}

- (IBAction)debugSearchAndParse:(id)sender {
    NSString *query = [self showInputDialogWithTitle:@"Search Query"
                                             message:@"Enter search term:"
                                         placeholder:@"Enter search term..."
                                        defaultValue:@"ChatGPT"];
    if (query) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [WAAccessibilityTest testSearchAndParseResults:query];
        });
    }
}

- (IBAction)debugClickResult0:(id)sender {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [WAAccessibilityTest testClickSearchResult:0];
    });
}

- (IBAction)debugClickResult1:(id)sender {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [WAAccessibilityTest testClickSearchResult:1];
    });
}

- (IBAction)debugClickResult2:(id)sender {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [WAAccessibilityTest testClickSearchResult:2];
    });
}

- (IBAction)debugTestParsing:(id)sender {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [WAAccessibilityTest testParsingUnitTests];
    });
}

- (IBAction)debugClickEsc:(id)sender {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [WAAccessibilityTest testPressEsc];
    });
}

- (IBAction)debugClickCmdF:(id)sender {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [WAAccessibilityTest testPressCmdF];
    });
}

- (IBAction)debugClickA:(id)sender {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [WAAccessibilityTest testPressA];
    });
}

- (IBAction)debugClickX:(id)sender {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [WAAccessibilityTest testPressX];
    });
}

- (IBAction)debugTypeInABC:(id)sender {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [WAAccessibilityTest testTypeInABC];
    });
}

- (IBAction)debugReadChatList:(id)sender {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [WAAccessibilityTest testReadChatList];
    });
}

- (IBAction)debugGetCurrentChat:(id)sender {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [WAAccessibilityTest testGetCurrentChat];
    });
}

#pragma mark - Chat Filter Debug Actions

- (IBAction)debugGetChatFilter:(id)sender {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [WAAccessibilityTest testGetChatFilter];
    });
}

- (IBAction)debugSetFilterAll:(id)sender {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [WAAccessibilityTest testSetChatFilter:@"all"];
    });
}

- (IBAction)debugSetFilterUnread:(id)sender {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [WAAccessibilityTest testSetChatFilter:@"unread"];
    });
}

- (IBAction)debugSetFilterFavorites:(id)sender {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [WAAccessibilityTest testSetChatFilter:@"favorites"];
    });
}

- (IBAction)debugSetFilterGroups:(id)sender {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [WAAccessibilityTest testSetChatFilter:@"groups"];
    });
}

- (IBAction)debugListChatsWithFilter:(id)sender {
    NSString *filter = [self showInputDialogWithTitle:@"List Chats With Filter"
                                              message:@"Enter filter (all, unread, favorites, groups):"
                                          placeholder:@"all"
                                         defaultValue:@"unread"];
    if (filter) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [WAAccessibilityTest testListChatsWithFilter:filter];
        });
    }
}

#pragma mark - Scroll Debug Actions

- (IBAction)debugScrollChatsDown:(id)sender {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [WAAccessibilityTest testScrollChatsDown];
    });
}

- (IBAction)debugScrollChatsUp:(id)sender {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [WAAccessibilityTest testScrollChatsUp];
    });
}

#pragma mark - Debug Configuration

- (IBAction)showDebugConfig:(id)sender {
    [[DebugConfigWindowController sharedController] toggleWindow];
}

#pragma mark - Log Window Actions

- (IBAction)toggleLogWindow:(id)sender {
    if (self.window.isVisible) {
        [self.window orderOut:nil];
    } else {
        [self.window makeKeyAndOrderFront:nil];
    }
}

#pragma mark - Settings Actions

- (IBAction)showSettings:(id)sender {
    // Open the Settings window for user preferences
    [[SettingsWindowController sharedController] showWindow];
}

@end
