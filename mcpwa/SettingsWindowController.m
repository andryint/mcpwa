// SettingsWindowController.m
// User Preferences Window Controller

#import "SettingsWindowController.h"

NSString *const WAThemeModeKey = @"WAThemeMode";
NSString *const WAThemeDidChangeNotification = @"WAThemeDidChangeNotification";

@interface SettingsWindowController ()
@property (nonatomic, strong) NSPopUpButton *themeSelector;
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
        // Register defaults - Auto theme by default
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{
            WAThemeModeKey: @(WAThemeModeAuto)
        }];
    }
}

+ (WAThemeMode)currentThemeMode {
    return [[NSUserDefaults standardUserDefaults] integerForKey:WAThemeModeKey];
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
    // Create window
    NSRect frame = NSMakeRect(0, 0, 350, 120);
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

    // Title label
    NSTextField *titleLabel = [NSTextField labelWithString:@"Appearance"];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [NSFont boldSystemFontOfSize:13];
    [contentView addSubview:titleLabel];

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
    WAThemeMode currentMode = [[self class] currentThemeMode];
    [self.themeSelector selectItemWithTag:currentMode];

    [contentView addSubview:self.themeSelector];

    // Info label
    NSTextField *infoLabel = [NSTextField labelWithString:@"Changes apply immediately to all windows."];
    infoLabel.translatesAutoresizingMaskIntoConstraints = NO;
    infoLabel.font = [NSFont systemFontOfSize:11];
    infoLabel.textColor = [NSColor secondaryLabelColor];
    [contentView addSubview:infoLabel];

    // Layout constraints
    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:20],
        [titleLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [titleLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],

        [themeLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:15],
        [themeLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [themeLabel.widthAnchor constraintEqualToConstant:60],

        [self.themeSelector.centerYAnchor constraintEqualToAnchor:themeLabel.centerYAnchor],
        [self.themeSelector.leadingAnchor constraintEqualToAnchor:themeLabel.trailingAnchor constant:10],
        [self.themeSelector.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],

        [infoLabel.topAnchor constraintEqualToAnchor:themeLabel.bottomAnchor constant:15],
        [infoLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [infoLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20]
    ]];
}

#pragma mark - Actions

- (void)themeChanged:(NSPopUpButton *)sender {
    WAThemeMode selectedMode = sender.selectedItem.tag;
    [[NSUserDefaults standardUserDefaults] setInteger:selectedMode forKey:WAThemeModeKey];

    // Apply theme immediately
    [[self class] applyThemeToAllWindows];
}

#pragma mark - Window Control

- (void)showWindow {
    // Refresh selector state from defaults
    WAThemeMode currentMode = [[self class] currentThemeMode];
    [self.themeSelector selectItemWithTag:currentMode];

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
