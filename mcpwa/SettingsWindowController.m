// SettingsWindowController.m
// User Preferences Window Controller

#import "SettingsWindowController.h"

NSString *const WAThemeModeKey = @"WAThemeMode";
NSString *const WAChatModeKey = @"WAChatMode";
NSString *const WARAGServiceURLKey = @"RAGServiceURL";
NSString *const WARAGEnvironmentKey = @"RAGEnvironment";
NSString *const WAThemeDidChangeNotification = @"WAThemeDidChangeNotification";
NSString *const WAChatModeDidChangeNotification = @"WAChatModeDidChangeNotification";

static NSString *const kProductionRAGURL = @"http://localhost:8000";
static NSString *const kDevelopmentRAGURL = @"http://localhost:8001";

@interface SettingsWindowController () <NSTextFieldDelegate>
@property (nonatomic, strong) NSPopUpButton *themeSelector;
@property (nonatomic, strong) NSPopUpButton *modeSelector;
@property (nonatomic, strong) NSPopUpButton *environmentSelector;
@property (nonatomic, strong) NSTextField *ragURLField;
@property (nonatomic, strong) NSButton *testConnectionButton;
@property (nonatomic, strong) NSTextField *connectionStatusLabel;
@property (nonatomic, strong) NSView *ragSettingsContainer;
@end

@implementation SettingsWindowController

+ (instancetype)sharedController {
    static SettingsWindowController *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[SettingsWindowController alloc] init];
    });
    return shared;
}

+ (void)initialize {
    if (self == [SettingsWindowController class]) {
        // Register defaults
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{
            WAThemeModeKey: @(WAThemeModeAuto),
            WAChatModeKey: @(WAChatModeMCP),
            WARAGEnvironmentKey: @(WARAGEnvironmentProduction),
            WARAGServiceURLKey: kProductionRAGURL
        }];
    }
}

+ (WAThemeMode)currentThemeMode {
    return [[NSUserDefaults standardUserDefaults] integerForKey:WAThemeModeKey];
}

+ (WAChatMode)currentChatMode {
    return [[NSUserDefaults standardUserDefaults] integerForKey:WAChatModeKey];
}

+ (NSString *)ragServiceURL {
    NSString *url = [[NSUserDefaults standardUserDefaults] stringForKey:WARAGServiceURLKey];
    if (url.length > 0) {
        return url;
    }
    // Return URL based on environment
    return [self ragEnvironment] == WARAGEnvironmentDevelopment ? kDevelopmentRAGURL : kProductionRAGURL;
}

+ (WARAGEnvironment)ragEnvironment {
    return [[NSUserDefaults standardUserDefaults] integerForKey:WARAGEnvironmentKey];
}

+ (void)setChatMode:(WAChatMode)mode {
    [[NSUserDefaults standardUserDefaults] setInteger:mode forKey:WAChatModeKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:WAChatModeDidChangeNotification
                                                        object:nil
                                                      userInfo:@{@"mode": @(mode)}];
}

+ (void)setRAGServiceURL:(NSString *)url {
    [[NSUserDefaults standardUserDefaults] setObject:url forKey:WARAGServiceURLKey];
}

+ (void)setRAGEnvironment:(WARAGEnvironment)environment {
    [[NSUserDefaults standardUserDefaults] setInteger:environment forKey:WARAGEnvironmentKey];
    // Update URL based on environment
    NSString *url = environment == WARAGEnvironmentDevelopment ? kDevelopmentRAGURL : kProductionRAGURL;
    [[NSUserDefaults standardUserDefaults] setObject:url forKey:WARAGServiceURLKey];
}

+ (NSAppearance *)effectiveAppearance {
    WAThemeMode mode = [self currentThemeMode];

    switch (mode) {
        case WAThemeModeLight:
            return [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        case WAThemeModeDark:
            return [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        case WAThemeModeAuto:
        default:
            // Return nil to use system appearance
            return nil;
    }
}

+ (void)applyThemeToAllWindows {
    NSAppearance *appearance = [self effectiveAppearance];

    // Apply to all windows
    for (NSWindow *window in [NSApp windows]) {
        window.appearance = appearance;
    }

    // Post notification for any custom handling
    [[NSNotificationCenter defaultCenter] postNotificationName:WAThemeDidChangeNotification
                                                        object:nil
                                                      userInfo:@{@"mode": @([self currentThemeMode])}];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self setupWindow];
    }
    return self;
}

- (void)setupWindow {
    // Create window - larger to accommodate mode and environment settings
    NSRect frame = NSMakeRect(0, 0, 400, 320);
    NSWindowStyleMask style = NSWindowStyleMaskTitled |
                              NSWindowStyleMaskClosable;

    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:style
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"Settings";
    [window center];
    window.level = NSFloatingWindowLevel;
    window.releasedWhenClosed = NO;

    self.window = window;

    [self setupContentView];

    // Apply current theme to this window
    window.appearance = [[self class] effectiveAppearance];
}

- (void)setupContentView {
    NSView *contentView = self.window.contentView;
    CGFloat labelWidth = 80;

    // ===== Appearance Section =====
    NSTextField *appearanceTitle = [NSTextField labelWithString:@"Appearance"];
    appearanceTitle.translatesAutoresizingMaskIntoConstraints = NO;
    appearanceTitle.font = [NSFont boldSystemFontOfSize:13];
    [contentView addSubview:appearanceTitle];

    // Theme label
    NSTextField *themeLabel = [NSTextField labelWithString:@"Theme:"];
    themeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    themeLabel.font = [NSFont systemFontOfSize:13];
    [contentView addSubview:themeLabel];

    // Theme selector popup
    self.themeSelector = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.themeSelector.translatesAutoresizingMaskIntoConstraints = NO;
    self.themeSelector.target = self;
    self.themeSelector.action = @selector(themeChanged:);

    [self.themeSelector addItemWithTitle:@"Light"];
    self.themeSelector.lastItem.tag = WAThemeModeLight;

    [self.themeSelector addItemWithTitle:@"Dark"];
    self.themeSelector.lastItem.tag = WAThemeModeDark;

    [self.themeSelector addItemWithTitle:@"Auto (System)"];
    self.themeSelector.lastItem.tag = WAThemeModeAuto;

    // Select current theme
    WAThemeMode currentTheme = [[self class] currentThemeMode];
    [self.themeSelector selectItemWithTag:currentTheme];

    [contentView addSubview:self.themeSelector];

    // ===== Chat Mode Section =====
    NSTextField *modeTitle = [NSTextField labelWithString:@"Chat Mode"];
    modeTitle.translatesAutoresizingMaskIntoConstraints = NO;
    modeTitle.font = [NSFont boldSystemFontOfSize:13];
    [contentView addSubview:modeTitle];

    // Mode label
    NSTextField *modeLabel = [NSTextField labelWithString:@"Mode:"];
    modeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    modeLabel.font = [NSFont systemFontOfSize:13];
    [contentView addSubview:modeLabel];

    // Mode selector popup
    self.modeSelector = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.modeSelector.translatesAutoresizingMaskIntoConstraints = NO;
    self.modeSelector.target = self;
    self.modeSelector.action = @selector(modeChanged:);

    [self.modeSelector addItemWithTitle:@"MCP (WhatsApp)"];
    self.modeSelector.lastItem.tag = WAChatModeMCP;

    [self.modeSelector addItemWithTitle:@"RAG (Knowledge Base)"];
    self.modeSelector.lastItem.tag = WAChatModeRAG;

    // Select current mode
    WAChatMode currentMode = [[self class] currentChatMode];
    [self.modeSelector selectItemWithTag:currentMode];

    [contentView addSubview:self.modeSelector];

    // ===== RAG Settings Container =====
    self.ragSettingsContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    self.ragSettingsContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:self.ragSettingsContainer];

    // Environment label
    NSTextField *envLabel = [NSTextField labelWithString:@"Environment:"];
    envLabel.translatesAutoresizingMaskIntoConstraints = NO;
    envLabel.font = [NSFont systemFontOfSize:13];
    envLabel.identifier = @"envLabel";
    [self.ragSettingsContainer addSubview:envLabel];

    // Environment selector popup
    self.environmentSelector = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.environmentSelector.translatesAutoresizingMaskIntoConstraints = NO;
    self.environmentSelector.target = self;
    self.environmentSelector.action = @selector(environmentChanged:);

    [self.environmentSelector addItemWithTitle:@"Production (:8000)"];
    self.environmentSelector.lastItem.tag = WARAGEnvironmentProduction;

    [self.environmentSelector addItemWithTitle:@"Development (:8001)"];
    self.environmentSelector.lastItem.tag = WARAGEnvironmentDevelopment;

    // Select current environment
    WARAGEnvironment currentEnv = [[self class] ragEnvironment];
    [self.environmentSelector selectItemWithTag:currentEnv];

    [self.ragSettingsContainer addSubview:self.environmentSelector];

    // RAG URL label
    NSTextField *ragURLLabel = [NSTextField labelWithString:@"URL:"];
    ragURLLabel.translatesAutoresizingMaskIntoConstraints = NO;
    ragURLLabel.font = [NSFont systemFontOfSize:13];
    [self.ragSettingsContainer addSubview:ragURLLabel];

    // RAG URL field
    self.ragURLField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.ragURLField.translatesAutoresizingMaskIntoConstraints = NO;
    self.ragURLField.placeholderString = @"http://localhost:8000";
    self.ragURLField.stringValue = [[self class] ragServiceURL];
    self.ragURLField.delegate = self;
    self.ragURLField.font = [NSFont systemFontOfSize:12];
    [self.ragSettingsContainer addSubview:self.ragURLField];

    // Test connection button
    self.testConnectionButton = [NSButton buttonWithTitle:@"Test" target:self action:@selector(testConnection:)];
    self.testConnectionButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.testConnectionButton.bezelStyle = NSBezelStyleRounded;
    self.testConnectionButton.controlSize = NSControlSizeSmall;
    [self.ragSettingsContainer addSubview:self.testConnectionButton];

    // Connection status label
    self.connectionStatusLabel = [NSTextField labelWithString:@""];
    self.connectionStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.connectionStatusLabel.font = [NSFont systemFontOfSize:11];
    self.connectionStatusLabel.textColor = [NSColor secondaryLabelColor];
    [self.ragSettingsContainer addSubview:self.connectionStatusLabel];

    // Update RAG settings visibility
    [self updateRAGSettingsVisibility];

    // ===== Layout Constraints =====
    [NSLayoutConstraint activateConstraints:@[
        // Appearance section
        [appearanceTitle.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:20],
        [appearanceTitle.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [appearanceTitle.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],

        [themeLabel.topAnchor constraintEqualToAnchor:appearanceTitle.bottomAnchor constant:12],
        [themeLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [themeLabel.widthAnchor constraintEqualToConstant:labelWidth],

        [self.themeSelector.centerYAnchor constraintEqualToAnchor:themeLabel.centerYAnchor],
        [self.themeSelector.leadingAnchor constraintEqualToAnchor:themeLabel.trailingAnchor constant:10],
        [self.themeSelector.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],

        // Chat Mode section
        [modeTitle.topAnchor constraintEqualToAnchor:themeLabel.bottomAnchor constant:24],
        [modeTitle.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [modeTitle.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],

        [modeLabel.topAnchor constraintEqualToAnchor:modeTitle.bottomAnchor constant:12],
        [modeLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [modeLabel.widthAnchor constraintEqualToConstant:labelWidth],

        [self.modeSelector.centerYAnchor constraintEqualToAnchor:modeLabel.centerYAnchor],
        [self.modeSelector.leadingAnchor constraintEqualToAnchor:modeLabel.trailingAnchor constant:10],
        [self.modeSelector.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],

        // RAG settings container
        [self.ragSettingsContainer.topAnchor constraintEqualToAnchor:modeLabel.bottomAnchor constant:12],
        [self.ragSettingsContainer.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [self.ragSettingsContainer.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [self.ragSettingsContainer.heightAnchor constraintEqualToConstant:90],

        // Environment selector
        [envLabel.topAnchor constraintEqualToAnchor:self.ragSettingsContainer.topAnchor],
        [envLabel.leadingAnchor constraintEqualToAnchor:self.ragSettingsContainer.leadingAnchor],
        [envLabel.widthAnchor constraintEqualToConstant:labelWidth],

        [self.environmentSelector.centerYAnchor constraintEqualToAnchor:envLabel.centerYAnchor],
        [self.environmentSelector.leadingAnchor constraintEqualToAnchor:envLabel.trailingAnchor constant:10],
        [self.environmentSelector.trailingAnchor constraintEqualToAnchor:self.ragSettingsContainer.trailingAnchor],

        // RAG URL label and field
        [ragURLLabel.topAnchor constraintEqualToAnchor:envLabel.bottomAnchor constant:10],
        [ragURLLabel.leadingAnchor constraintEqualToAnchor:self.ragSettingsContainer.leadingAnchor],
        [ragURLLabel.widthAnchor constraintEqualToConstant:labelWidth],

        [self.ragURLField.centerYAnchor constraintEqualToAnchor:ragURLLabel.centerYAnchor],
        [self.ragURLField.leadingAnchor constraintEqualToAnchor:ragURLLabel.trailingAnchor constant:10],
        [self.ragURLField.trailingAnchor constraintEqualToAnchor:self.testConnectionButton.leadingAnchor constant:-8],

        [self.testConnectionButton.centerYAnchor constraintEqualToAnchor:ragURLLabel.centerYAnchor],
        [self.testConnectionButton.trailingAnchor constraintEqualToAnchor:self.ragSettingsContainer.trailingAnchor],
        [self.testConnectionButton.widthAnchor constraintEqualToConstant:50],

        [self.connectionStatusLabel.topAnchor constraintEqualToAnchor:ragURLLabel.bottomAnchor constant:6],
        [self.connectionStatusLabel.leadingAnchor constraintEqualToAnchor:self.ragURLField.leadingAnchor],
        [self.connectionStatusLabel.trailingAnchor constraintEqualToAnchor:self.ragSettingsContainer.trailingAnchor]
    ]];
}

- (void)updateRAGSettingsVisibility {
    BOOL isRAGMode = ([[self class] currentChatMode] == WAChatModeRAG);
    self.ragSettingsContainer.hidden = !isRAGMode;
    self.ragSettingsContainer.alphaValue = isRAGMode ? 1.0 : 0.0;
}

#pragma mark - Actions

- (void)themeChanged:(NSPopUpButton *)sender {
    WAThemeMode selectedMode = sender.selectedItem.tag;
    [[NSUserDefaults standardUserDefaults] setInteger:selectedMode forKey:WAThemeModeKey];

    // Apply theme immediately
    [[self class] applyThemeToAllWindows];
}

- (void)modeChanged:(NSPopUpButton *)sender {
    WAChatMode selectedMode = sender.selectedItem.tag;
    [[self class] setChatMode:selectedMode];

    // Update RAG settings visibility with animation
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.2;
        context.allowsImplicitAnimation = YES;
        [self updateRAGSettingsVisibility];
        [self.window layoutIfNeeded];
    }];
}

- (void)environmentChanged:(NSPopUpButton *)sender {
    WARAGEnvironment selectedEnv = sender.selectedItem.tag;
    [[self class] setRAGEnvironment:selectedEnv];

    // Update URL field to reflect the new environment
    self.ragURLField.stringValue = [[self class] ragServiceURL];
    self.connectionStatusLabel.stringValue = @"";
}

- (void)testConnection:(id)sender {
    NSString *url = self.ragURLField.stringValue;
    if (url.length == 0) {
        url = kProductionRAGURL;
    }

    // Save the URL
    [[self class] setRAGServiceURL:url];

    self.testConnectionButton.enabled = NO;
    self.connectionStatusLabel.stringValue = @"Testing...";
    self.connectionStatusLabel.textColor = [NSColor secondaryLabelColor];

    // Test connection using RAGClient
    // We need to import RAGClient, but for now let's do a simple HTTP check
    NSString *healthURL = [NSString stringWithFormat:@"%@/health", url];
    NSURL *requestURL = [NSURL URLWithString:healthURL];

    if (!requestURL) {
        self.connectionStatusLabel.stringValue = @"Invalid URL";
        self.connectionStatusLabel.textColor = [NSColor systemRedColor];
        self.testConnectionButton.enabled = YES;
        return;
    }

    NSURLRequest *request = [NSURLRequest requestWithURL:requestURL
                                             cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                         timeoutInterval:5.0];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.testConnectionButton.enabled = YES;

            if (error) {
                self.connectionStatusLabel.stringValue = @"Connection failed";
                self.connectionStatusLabel.textColor = [NSColor systemRedColor];
                return;
            }

            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if (httpResponse.statusCode == 200) {
                self.connectionStatusLabel.stringValue = @"Connected successfully";
                self.connectionStatusLabel.textColor = [NSColor systemGreenColor];
            } else {
                self.connectionStatusLabel.stringValue = [NSString stringWithFormat:@"HTTP %ld", (long)httpResponse.statusCode];
                self.connectionStatusLabel.textColor = [NSColor systemOrangeColor];
            }
        });
    }];
    [task resume];
}

#pragma mark - NSTextFieldDelegate

- (void)controlTextDidEndEditing:(NSNotification *)obj {
    if (obj.object == self.ragURLField) {
        // Save URL when editing ends
        [[self class] setRAGServiceURL:self.ragURLField.stringValue];
        self.connectionStatusLabel.stringValue = @"";
    }
}

#pragma mark - Window Control

- (void)showWindow {
    // Refresh selector states from defaults
    WAThemeMode currentTheme = [[self class] currentThemeMode];
    [self.themeSelector selectItemWithTag:currentTheme];

    WAChatMode currentMode = [[self class] currentChatMode];
    [self.modeSelector selectItemWithTag:currentMode];

    WARAGEnvironment currentEnv = [[self class] ragEnvironment];
    [self.environmentSelector selectItemWithTag:currentEnv];

    self.ragURLField.stringValue = [[self class] ragServiceURL];
    self.connectionStatusLabel.stringValue = @"";

    [self updateRAGSettingsVisibility];

    [self.window makeKeyAndOrderFront:nil];
}

- (void)toggleWindow {
    if (self.window.isVisible) {
        [self.window orderOut:nil];
    } else {
        [self showWindow];
    }
}

@end
