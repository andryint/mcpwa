// DebugConfigWindowController.m
// Debug Configuration Window Controller

#import "DebugConfigWindowController.h"

NSString *const WADebugLogAccessibilityKey = @"WADebugLogAccessibility";
NSString *const WADebugShowInChatKey = @"WADebugShowInChat";

@interface DebugConfigWindowController ()
@property (nonatomic, strong) NSButton *accessibilityLogsCheckbox;
@property (nonatomic, strong) NSButton *debugInChatCheckbox;
@end

@implementation DebugConfigWindowController

+ (instancetype)sharedController {
    static DebugConfigWindowController *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[DebugConfigWindowController alloc] init];
    });
    return shared;
}

+ (void)initialize {
    if (self == [DebugConfigWindowController class]) {
        // Register defaults - accessibility logs ON by default, debug in chat OFF by default
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{
            WADebugLogAccessibilityKey: @YES,
            WADebugShowInChatKey: @NO
        }];
    }
}

+ (BOOL)logAccessibilityEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:WADebugLogAccessibilityKey];
}

+ (BOOL)showDebugInChatEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:WADebugShowInChatKey];
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
    NSRect frame = NSMakeRect(0, 0, 350, 150);
    NSWindowStyleMask style = NSWindowStyleMaskTitled |
                              NSWindowStyleMaskClosable;

    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:style
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"Debug Configuration";
    [window center];
    window.level = NSFloatingWindowLevel;
    window.releasedWhenClosed = NO;  // Don't release window when closed

    self.window = window;

    [self setupContentView];
}

- (void)setupContentView {
    NSView *contentView = self.window.contentView;

    // Title label
    NSTextField *titleLabel = [NSTextField labelWithString:@"Debug Logging Options"];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [NSFont boldSystemFontOfSize:13];
    [contentView addSubview:titleLabel];

    // Accessibility logs checkbox
    self.accessibilityLogsCheckbox = [NSButton checkboxWithTitle:@"Log Accessibility API calls (WhatsApp window access)"
                                                          target:self
                                                          action:@selector(accessibilityLogsToggled:)];
    self.accessibilityLogsCheckbox.translatesAutoresizingMaskIntoConstraints = NO;
    self.accessibilityLogsCheckbox.state = [[self class] logAccessibilityEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
    [contentView addSubview:self.accessibilityLogsCheckbox];

    // Debug in chat checkbox
    self.debugInChatCheckbox = [NSButton checkboxWithTitle:@"Show debug info in chat view"
                                                    target:self
                                                    action:@selector(debugInChatToggled:)];
    self.debugInChatCheckbox.translatesAutoresizingMaskIntoConstraints = NO;
    self.debugInChatCheckbox.state = [[self class] showDebugInChatEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
    [contentView addSubview:self.debugInChatCheckbox];

    // Info label
    NSTextField *infoLabel = [NSTextField labelWithString:@"Changes take effect immediately."];
    infoLabel.translatesAutoresizingMaskIntoConstraints = NO;
    infoLabel.font = [NSFont systemFontOfSize:11];
    infoLabel.textColor = [NSColor secondaryLabelColor];
    [contentView addSubview:infoLabel];

    // Layout constraints
    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:20],
        [titleLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [titleLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],

        [self.accessibilityLogsCheckbox.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:15],
        [self.accessibilityLogsCheckbox.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [self.accessibilityLogsCheckbox.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],

        [self.debugInChatCheckbox.topAnchor constraintEqualToAnchor:self.accessibilityLogsCheckbox.bottomAnchor constant:10],
        [self.debugInChatCheckbox.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [self.debugInChatCheckbox.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],

        [infoLabel.topAnchor constraintEqualToAnchor:self.debugInChatCheckbox.bottomAnchor constant:15],
        [infoLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [infoLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20]
    ]];
}

#pragma mark - Actions

- (void)accessibilityLogsToggled:(NSButton *)sender {
    BOOL enabled = (sender.state == NSControlStateValueOn);
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:WADebugLogAccessibilityKey];
}

- (void)debugInChatToggled:(NSButton *)sender {
    BOOL enabled = (sender.state == NSControlStateValueOn);
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:WADebugShowInChatKey];
}

#pragma mark - Window Control

- (void)showWindow {
    // Refresh checkbox states from defaults
    self.accessibilityLogsCheckbox.state = [[self class] logAccessibilityEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
    self.debugInChatCheckbox.state = [[self class] showDebugInChatEnabled] ? NSControlStateValueOn : NSControlStateValueOff;

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
