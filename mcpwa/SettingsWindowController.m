// SettingsWindowController.m
// User Preferences Window Controller

#import "SettingsWindowController.h"

NSString *const WAThemeModeKey = @"WAThemeMode";
NSString *const WARAGServiceURLKey = @"RAGServiceURL";
NSString *const WARAGEnvironmentKey = @"RAGEnvironment";
NSString *const WAThemeDidChangeNotification = @"WAThemeDidChangeNotification";

static NSString *const kProductionRAGURL = @"http://localhost:8000";
static NSString *const kDevelopmentRAGURL = @"http://localhost:8001";

@interface SettingsWindowController () <NSTextFieldDelegate>
@property (nonatomic, strong) NSPopUpButton *themeSelector;
@property (nonatomic, strong) NSPopUpButton *environmentSelector;
@property (nonatomic, strong) NSTextField *ragURLField;
@property (nonatomic, strong) NSButton *testConnectionButton;
@property (nonatomic, strong) NSTextField *connectionStatusLabel;
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
            WARAGEnvironmentKey: @(WARAGEnvironmentProduction),
            WARAGServiceURLKey: kProductionRAGURL
        }];
    }
}

+ (WAThemeMode)currentThemeMode {
    return [[NSUserDefaults standardUserDefaults] integerForKey:WAThemeModeKey];
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
    // Create window - simpler layout without mode selector
    NSRect frame = NSMakeRect(0, 0, 400, 240);
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

    // ===== Backend Settings Section =====
    NSTextField *backendTitle = [NSTextField labelWithString:@"Backend Connection"];
    backendTitle.translatesAutoresizingMaskIntoConstraints = NO;
    backendTitle.font = [NSFont boldSystemFontOfSize:13];
    [contentView addSubview:backendTitle];

    // Environment label
    NSTextField *envLabel = [NSTextField labelWithString:@"Environment:"];
    envLabel.translatesAutoresizingMaskIntoConstraints = NO;
    envLabel.font = [NSFont systemFontOfSize:13];
    [contentView addSubview:envLabel];

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

    [contentView addSubview:self.environmentSelector];

    // URL label
    NSTextField *urlLabel = [NSTextField labelWithString:@"URL:"];
    urlLabel.translatesAutoresizingMaskIntoConstraints = NO;
    urlLabel.font = [NSFont systemFontOfSize:13];
    [contentView addSubview:urlLabel];

    // URL field
    self.ragURLField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.ragURLField.translatesAutoresizingMaskIntoConstraints = NO;
    self.ragURLField.placeholderString = @"http://localhost:8000";
    self.ragURLField.stringValue = [[self class] ragServiceURL];
    self.ragURLField.delegate = self;
    self.ragURLField.font = [NSFont systemFontOfSize:12];
    [contentView addSubview:self.ragURLField];

    // Test connection button
    self.testConnectionButton = [NSButton buttonWithTitle:@"Test" target:self action:@selector(testConnection:)];
    self.testConnectionButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.testConnectionButton.bezelStyle = NSBezelStyleRounded;
    self.testConnectionButton.controlSize = NSControlSizeSmall;
    [contentView addSubview:self.testConnectionButton];

    // Connection status label
    self.connectionStatusLabel = [NSTextField labelWithString:@""];
    self.connectionStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.connectionStatusLabel.font = [NSFont systemFontOfSize:11];
    self.connectionStatusLabel.textColor = [NSColor secondaryLabelColor];
    [contentView addSubview:self.connectionStatusLabel];

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

        // Backend section
        [backendTitle.topAnchor constraintEqualToAnchor:themeLabel.bottomAnchor constant:24],
        [backendTitle.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [backendTitle.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],

        [envLabel.topAnchor constraintEqualToAnchor:backendTitle.bottomAnchor constant:12],
        [envLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [envLabel.widthAnchor constraintEqualToConstant:labelWidth],

        [self.environmentSelector.centerYAnchor constraintEqualToAnchor:envLabel.centerYAnchor],
        [self.environmentSelector.leadingAnchor constraintEqualToAnchor:envLabel.trailingAnchor constant:10],
        [self.environmentSelector.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],

        // URL label and field
        [urlLabel.topAnchor constraintEqualToAnchor:envLabel.bottomAnchor constant:10],
        [urlLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [urlLabel.widthAnchor constraintEqualToConstant:labelWidth],

        [self.ragURLField.centerYAnchor constraintEqualToAnchor:urlLabel.centerYAnchor],
        [self.ragURLField.leadingAnchor constraintEqualToAnchor:urlLabel.trailingAnchor constant:10],
        [self.ragURLField.trailingAnchor constraintEqualToAnchor:self.testConnectionButton.leadingAnchor constant:-8],

        [self.testConnectionButton.centerYAnchor constraintEqualToAnchor:urlLabel.centerYAnchor],
        [self.testConnectionButton.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [self.testConnectionButton.widthAnchor constraintEqualToConstant:50],

        [self.connectionStatusLabel.topAnchor constraintEqualToAnchor:urlLabel.bottomAnchor constant:6],
        [self.connectionStatusLabel.leadingAnchor constraintEqualToAnchor:self.ragURLField.leadingAnchor],
        [self.connectionStatusLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20]
    ]];
}

#pragma mark - Actions

- (void)themeChanged:(NSPopUpButton *)sender {
    WAThemeMode selectedMode = sender.selectedItem.tag;
    [[NSUserDefaults standardUserDefaults] setInteger:selectedMode forKey:WAThemeModeKey];

    // Apply theme immediately
    [[self class] applyThemeToAllWindows];
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

    // Test connection using health endpoint
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

    WARAGEnvironment currentEnv = [[self class] ragEnvironment];
    [self.environmentSelector selectItemWithTag:currentEnv];

    self.ragURLField.stringValue = [[self class] ragServiceURL];
    self.connectionStatusLabel.stringValue = @"";

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
