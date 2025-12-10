//
//  AppDelegate.m
//  mcpwa
//
//  MCP Server for WhatsApp Desktop - Cocoa App with logging UI
//

#import "AppDelegate.h"
#import "MCPServer.h"
#import "WAAccessibility.h"
#import "WAAccessibilityExplorer.h"
#import "WAAccessibilityTest.h"

@interface AppDelegate ()
@property (nonatomic, strong) MCPServer *server;
@property (nonatomic, assign) BOOL serverRunning;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self setupWindow];
    [self checkInitialStatus];
}

- (void)setupWindow {
    // Create main window
    NSRect frame = NSMakeRect(100, 100, 800, 500);
    NSWindowStyleMask style = NSWindowStyleMaskTitled | 
                              NSWindowStyleMaskClosable | 
                              NSWindowStyleMaskMiniaturizable | 
                              NSWindowStyleMaskResizable;
    
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:style
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.title = @"WhatsAppMCP Server";
    self.window.minSize = NSMakeSize(600, 400);
    
    // Create content view with padding
    NSView *contentView = self.window.contentView;
    
    // === Top toolbar area ===
    NSView *toolbar = [[NSView alloc] initWithFrame:NSMakeRect(0, 450, 800, 50)];
    toolbar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [contentView addSubview:toolbar];
    
    // Status indicator
    self.statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 10, 400, 30)];
    self.statusLabel.bezeled = NO;
    self.statusLabel.editable = NO;
    self.statusLabel.selectable = NO;
    self.statusLabel.backgroundColor = NSColor.clearColor;
    self.statusLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
    self.statusLabel.stringValue = @"● Checking status...";
    self.statusLabel.autoresizingMask = NSViewWidthSizable;
    [toolbar addSubview:self.statusLabel];
    
    // Start/Stop button
    self.startStopButton = [[NSButton alloc] initWithFrame:NSMakeRect(680, 10, 100, 30)];
    self.startStopButton.bezelStyle = NSBezelStyleRounded;
    self.startStopButton.title = @"Start Server";
    self.startStopButton.target = self;
    self.startStopButton.action = @selector(toggleServer:);
    self.startStopButton.autoresizingMask = NSViewMinXMargin;
    [toolbar addSubview:self.startStopButton];
    
    // Check Permissions button
    NSButton *permButton = [[NSButton alloc] initWithFrame:NSMakeRect(550, 10, 120, 30)];
    permButton.bezelStyle = NSBezelStyleRounded;
    permButton.title = @"Check Status";
    permButton.target = self;
    permButton.action = @selector(checkPermissions:);
    permButton.autoresizingMask = NSViewMinXMargin;
    [toolbar addSubview:permButton];
    
    // === Log area ===
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(10, 60, 780, 380)];
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
    
    // === Bottom info area ===
    NSTextField *infoLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 10, 780, 40)];
    infoLabel.bezeled = NO;
    infoLabel.editable = NO;
    infoLabel.selectable = YES;
    infoLabel.backgroundColor = NSColor.clearColor;
    infoLabel.font = [NSFont systemFontOfSize:11];
    infoLabel.textColor = NSColor.secondaryLabelColor;
    infoLabel.stringValue = @"Configure in Claude Desktop: ~/Library/Application Support/Claude/claude_desktop_config.json\nAdd: { \"mcpServers\": { \"whatsapp\": { \"command\": \"/path/to/mcpwa.app/Contents/MacOS/mcpwa\" } } }";
    infoLabel.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [contentView addSubview:infoLabel];
    
    // Show window
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    
    // Welcome message
    [self appendLog:@"╔══════════════════════════════════════════════════════════════╗" color:NSColor.cyanColor];
    [self appendLog:@"║           WhatsAppMCP Server v1.0                            ║" color:NSColor.cyanColor];
    [self appendLog:@"║   MCP Server for WhatsApp Desktop via Accessibility API      ║" color:NSColor.cyanColor];
    [self appendLog:@"╚══════════════════════════════════════════════════════════════╝" color:NSColor.cyanColor];
    [self appendLog:@""];
}

- (void)checkInitialStatus {
    WAAccessibility *wa = [WAAccessibility shared];
    
    // Check if accessibility is trusted
    BOOL hasPermission = AXIsProcessTrusted();
    BOOL isAvailable = [wa isWhatsAppAvailable];
    
    [self appendLog:@"Startup checks:"];
    [self appendLog:[NSString stringWithFormat:@"  • Accessibility permission: %@", 
                     hasPermission ? @"✅ Granted" : @"❌ Not granted"]
              color:hasPermission ? NSColor.greenColor : NSColor.redColor];
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
        [self appendLog:@""];
    }
}

- (void)updateStatusLabel {
    BOOL hasPermission = AXIsProcessTrusted();
    BOOL isAvailable = [[WAAccessibility shared] isWhatsAppAvailable];
    
    NSString *status;
    NSColor *color;
    
    if (!hasPermission) {
        status = @"🔴 Accessibility permission required";
        color = NSColor.redColor;
    } else if (!isAvailable) {
        status = @"🟡 WhatsApp not running or not accessible";
        color = NSColor.orangeColor;
    } else if (self.serverRunning) {
        status = @"🟢 Server running - Ready for Claude Desktop";
        color = NSColor.greenColor;
    } else {
        status = @"🟢 Ready - Click 'Start Server' to begin";
        color = NSColor.greenColor;
    }
    
    self.statusLabel.stringValue = status;
    self.statusLabel.textColor = color;
}

#pragma mark - Actions

- (void)toggleServer:(id)sender {
    if (self.serverRunning) {
        [self stopServer];
    } else {
        [self startServer];
    }
}

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
    
    self.server = [[MCPServer alloc] initWithDelegate:self];
    [self.server start];
    
    self.serverRunning = YES;
    self.startStopButton.title = @"Stop Server";
    [self updateStatusLabel];
    
    [self appendLog:@"✅ Server started - listening on stdio" color:NSColor.greenColor];
    [self appendLog:@"   Waiting for Claude Desktop connection..." color:NSColor.systemGrayColor];
    [self appendLog:@""];
}

- (void)stopServer {
    [self appendLog:@"Stopping MCP server..." color:NSColor.yellowColor];
    
    [self.server stop];
    self.server = nil;
    
    self.serverRunning = NO;
    self.startStopButton.title = @"Start Server";
    [self updateStatusLabel];
    
    [self appendLog:@"Server stopped" color:NSColor.yellowColor];
    [self appendLog:@""];
}

- (void)checkPermissions:(id)sender {
    [self appendLog:@"Checking status..." color:NSColor.cyanColor];
    
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
        NSArray<WAChat *> *chats = [wa getChats];
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

#pragma mark - Application Lifecycle

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    if (self.serverRunning) {
        [self stopServer];
    }
}

#pragma mark - Debug Actions (connect to menu items if desired)

- (IBAction)explore:(id)sender {
    [self appendLog:@"Running AX Explorer..." color:NSColor.cyanColor];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [WAAccessibilityExplorer exploreToFile:@"~/Adhoc/whatsapp_ax.txt"];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self appendLog:@"Explorer complete - saved to ~/Adhoc/whatsapp_ax.txt" color:NSColor.greenColor];
            [[NSWorkspace sharedWorkspace] openFile:@"~/Adhoc/whatsapp_ax.txt"];
        });
    });
}

- (IBAction)runTests:(id)sender {
    [self appendLog:@"Running WAAccessibility tests..." color:NSColor.cyanColor];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [WAAccessibilityTest runAllTests];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self appendLog:@"Tests complete - see Console for output" color:NSColor.greenColor];
        });
    });
}

@end
