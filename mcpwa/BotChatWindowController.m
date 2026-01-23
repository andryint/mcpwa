//
//  BotChatWindowController.m
//  mcpwa
//
//  Bot Chat Window - Backend-powered chat with WhatsApp integration
//

#import "BotChatWindowController.h"
#import "BotChatWindowController+ThemeHandling.h"
#import "BotChatWindowController+ZoomActions.h"
#import "BotChatWindowController+MarkdownParser.h"
#import "BotChatWindowController+ScrollManagement.h"
#import "BotChatWindowController+StreamingSupport.h"
#import "BotChatWindowController+MessageRendering.h"
#import "BotChatWindowController+InputHandling.h"
#import "BotChatWindowController+DelegateHandlers.h"
#import "WAAccessibility.h"
#import "DebugConfigWindowController.h"
#import "SettingsWindowController.h"
#import "WALogger.h"
#import <QuartzCore/QuartzCore.h>

// ChatDisplayMessage implementation (interface is in header)
@implementation ChatDisplayMessage
@end

#pragma mark - BotChatWindowController

@interface BotChatWindowController () <NSPopoverDelegate>
// Note: NSTextViewDelegate is declared in BotChatWindowController+InputHandling.h
@end

@implementation BotChatWindowController

+ (instancetype)sharedController {
    static BotChatWindowController *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[BotChatWindowController alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _messages = [NSMutableArray array];
        _streamingResponse = [NSMutableString string];

        // Load saved font size or use default
        CGFloat savedFontSize = [[NSUserDefaults standardUserDefaults] floatForKey:@"ChatFontSize"];
        _currentFontSize = (savedFontSize >= kMinFontSize && savedFontSize <= kMaxFontSize) ? savedFontSize : kDefaultFontSize;

        [self setupWindow];
        [self setupRAGClient];

        // Listen to theme change notification from Settings
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(themeDidChange:)
                                                     name:WAThemeDidChangeNotification
                                                   object:nil];

        // Listen to window resize to keep scroll at bottom
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowDidResize:)
                                                     name:NSWindowDidResizeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)themeDidChange:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateColorsForAppearance];
    });
}

- (void)windowDidResize:(NSNotification *)notification {
    // Only handle resize for our window
    if (notification.object != self.window) return;

    // Update bottom spacer height if present (ChatGPT-style scrolling)
    if (self.bottomSpacerView) {
        [self updateBottomSpacerHeight];
    } else {
        // Scroll to bottom after resize to keep content visible
        [self scrollToBottom];
    }
}

#pragma mark - Zoom Actions

- (IBAction)zoomIn:(id)sender {
    if (self.currentFontSize < kMaxFontSize) {
        self.currentFontSize += kFontSizeStep;
        [self applyFontSize];
    }
}

- (IBAction)zoomOut:(id)sender {
    if (self.currentFontSize > kMinFontSize) {
        self.currentFontSize -= kFontSizeStep;
        [self applyFontSize];
    }
}

- (IBAction)zoomToActualSize:(id)sender {
    self.currentFontSize = kDefaultFontSize;
    [self applyFontSize];
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
    SEL action = item.action;
    if (action == @selector(zoomIn:)) {
        return self.currentFontSize < kMaxFontSize;
    } else if (action == @selector(zoomOut:)) {
        return self.currentFontSize > kMinFontSize;
    }
    return YES;
}

- (void)setupWindow {
    // Create window - 50% larger default size (750x900 vs 500x600)
    NSRect frame = NSMakeRect(0, 0, 750, 900);
    NSWindowStyleMask style = NSWindowStyleMaskTitled |
                              NSWindowStyleMaskClosable |
                              NSWindowStyleMaskMiniaturizable |
                              NSWindowStyleMaskResizable |
                              NSWindowStyleMaskFullSizeContentView;

    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:style
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"WhatsApp Bot Chat";
    window.minSize = NSMakeSize(400, 400);

    // Enable automatic save/restore of window position and size
    window.frameAutosaveName = @"BotChatWindow";

    // Apply current theme appearance from Settings
    window.appearance = [SettingsWindowController effectiveAppearance];
    setColorReferenceWindow(window);

    window.backgroundColor = backgroundColor();

    // Only center if no saved position (frameAutosaveName will restore if available)
    if (![[NSUserDefaults standardUserDefaults] objectForKey:@"NSWindow Frame BotChatWindow"]) {
        [window center];
    }

    // Use smaller traffic light buttons (like Claude app)
    window.titlebarAppearsTransparent = YES;
    window.titleVisibility = NSWindowTitleHidden;

    // Create a toolbar to enable compact titlebar style
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"MainToolbar"];
    toolbar.showsBaselineSeparator = NO;
    toolbar.visible = NO;  // Hide toolbar but keep compact style
    window.toolbar = toolbar;

    // Use unified compact style for smaller traffic lights
    if (@available(macOS 11.0, *)) {
        window.toolbarStyle = NSWindowToolbarStyleUnifiedCompact;
    }

    // Main window - normal level (not floating)
    window.level = NSNormalWindowLevel;

    self.window = window;

    // Setup content
    [self setupContentView];
}

- (void)setupContentView {
    NSView *contentView = self.window.contentView;
    contentView.wantsLayer = YES;
    contentView.layer.backgroundColor = backgroundColor().CGColor;

    // Title bar view (non-transparent bar at the top, aligned with traffic lights)
    NSView *titleBarView = [[NSView alloc] initWithFrame:NSZeroRect];
    titleBarView.translatesAutoresizingMaskIntoConstraints = NO;
    titleBarView.wantsLayer = YES;
    titleBarView.layer.backgroundColor = backgroundColor().CGColor;
    [contentView addSubview:titleBarView];
    self.titleBarView = titleBarView;

    // Title label - centered, aligned with traffic light buttons
    NSTextField *titleLabel = [NSTextField labelWithString:@"WhatsApp Assistant"];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    titleLabel.textColor = primaryTextColor();
    titleLabel.alignment = NSTextAlignmentCenter;
    [titleBarView addSubview:titleLabel];
    self.titleLabel = titleLabel;

    // Title bar constraints - narrow height to align with traffic lights (~28px)
    [NSLayoutConstraint activateConstraints:@[
        [titleBarView.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [titleBarView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [titleBarView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [titleBarView.heightAnchor constraintEqualToConstant:28]
    ]];

    // Title label centered in title bar
    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.centerXAnchor constraintEqualToAnchor:titleBarView.centerXAnchor],
        [titleLabel.centerYAnchor constraintEqualToAnchor:titleBarView.centerYAnchor]
    ]];

    // Chat scroll view (takes most of the space)
    self.chatScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    self.chatScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.chatScrollView.hasVerticalScroller = YES;
    self.chatScrollView.hasHorizontalScroller = NO;
    self.chatScrollView.autohidesScrollers = YES;
    self.chatScrollView.borderType = NSNoBorder;
    self.chatScrollView.backgroundColor = backgroundColor();
    self.chatScrollView.drawsBackground = YES;

    // Stack view for chat messages
    self.chatStackView = [[NSStackView alloc] initWithFrame:NSZeroRect];
    self.chatStackView.translatesAutoresizingMaskIntoConstraints = NO;
    self.chatStackView.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.chatStackView.alignment = NSLayoutAttributeLeading;
    self.chatStackView.spacing = 12;  // Slightly more spacing between messages
    self.chatStackView.edgeInsets = NSEdgeInsetsMake(16, 24, 16, 24);  // More left/right margin

    // Document view for scroll content
    NSView *documentView = [[NSView alloc] initWithFrame:NSZeroRect];
    documentView.translatesAutoresizingMaskIntoConstraints = NO;
    [documentView addSubview:self.chatStackView];
    self.chatScrollView.documentView = documentView;

    [contentView addSubview:self.chatScrollView];

    // Input container
    NSView *inputContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    inputContainer.translatesAutoresizingMaskIntoConstraints = NO;
    inputContainer.wantsLayer = YES;
    inputContainer.layer.backgroundColor = inputBackgroundColor().CGColor;
    [contentView addSubview:inputContainer];
    self.inputContainer = inputContainer;

    // Input scroll view (wraps the text view for multi-line input)
    self.inputScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    self.inputScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.inputScrollView.hasVerticalScroller = YES;
    self.inputScrollView.hasHorizontalScroller = NO;
    self.inputScrollView.autohidesScrollers = YES;
    self.inputScrollView.borderType = NSNoBorder;
    self.inputScrollView.drawsBackground = NO;

    // Input text view (multi-line, expands vertically)
    self.inputTextView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 300, 28)];
    self.inputTextView.delegate = self;
    self.inputTextView.font = [NSFont systemFontOfSize:self.currentFontSize];
    self.inputTextView.textColor = primaryTextColor();
    self.inputTextView.insertionPointColor = primaryTextColor();
    // Light mode: white input field with subtle border; Dark mode: dark background
    if (isDarkMode()) {
        self.inputTextView.backgroundColor = [NSColor colorWithWhite:0.18 alpha:1.0];
    } else {
        self.inputTextView.backgroundColor = [NSColor whiteColor];
    }
    self.inputTextView.drawsBackground = YES;
    self.inputTextView.wantsLayer = YES;
    self.inputTextView.layer.cornerRadius = 12;
    // Add subtle border in light mode
    if (!isDarkMode()) {
        self.inputTextView.layer.borderWidth = 1.0;
        self.inputTextView.layer.borderColor = [NSColor colorWithWhite:0.85 alpha:1.0].CGColor;
    }
    self.inputTextView.richText = NO;
    self.inputTextView.allowsUndo = YES;
    self.inputTextView.textContainerInset = NSMakeSize(10, 8);
    self.inputTextView.textContainer.widthTracksTextView = YES;
    self.inputTextView.verticallyResizable = YES;
    self.inputTextView.horizontallyResizable = NO;
    self.inputTextView.autoresizingMask = NSViewWidthSizable;

    self.inputScrollView.documentView = self.inputTextView;
    [inputContainer addSubview:self.inputScrollView];

    // Placeholder label (overlays the text view when empty)
    self.placeholderLabel = [NSTextField labelWithString:@"Type a message..."];
    self.placeholderLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.placeholderLabel.font = [NSFont systemFontOfSize:self.currentFontSize];
    self.placeholderLabel.textColor = secondaryTextColor();
    self.placeholderLabel.backgroundColor = [NSColor clearColor];
    self.placeholderLabel.bezeled = NO;
    self.placeholderLabel.editable = NO;
    self.placeholderLabel.selectable = NO;
    [inputContainer addSubview:self.placeholderLabel];

    // Send button (arrow up icon) - Claude uses warm brown/tan accent
    NSImage *sendImage = [NSImage imageWithSystemSymbolName:@"arrow.up" accessibilityDescription:@"Send"];
    NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:14 weight:NSFontWeightBold];
    sendImage = [sendImage imageWithSymbolConfiguration:config];
    self.sendButton = [NSButton buttonWithImage:sendImage target:self action:@selector(sendMessage:)];
    self.sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.sendButton.bezelStyle = NSBezelStyleCircular;
    self.sendButton.bordered = NO;
    self.sendButton.keyEquivalent = @"\r"; // Enter key
    self.sendButton.wantsLayer = YES;
    // Claude-style warm accent color
    NSColor *accentColor = isDarkMode() ?
        [NSColor colorWithRed:0.85 green:0.75 blue:0.65 alpha:1.0] :
        [NSColor colorWithRed:0.45 green:0.38 blue:0.32 alpha:1.0];
    self.sendButton.layer.backgroundColor = accentColor.CGColor;
    self.sendButton.layer.cornerRadius = 14;
    self.sendButton.contentTintColor = [NSColor whiteColor];
    [inputContainer addSubview:self.sendButton];

    // Stop button (stop icon - hidden by default, shown during processing)
    NSImage *stopImage = [NSImage imageWithSystemSymbolName:@"stop.fill" accessibilityDescription:@"Stop"];
    stopImage = [stopImage imageWithSymbolConfiguration:config];
    self.stopButton = [NSButton buttonWithImage:stopImage target:self action:@selector(stopProcessing:)];
    self.stopButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.stopButton.bezelStyle = NSBezelStyleCircular;
    self.stopButton.bordered = NO;
    self.stopButton.hidden = YES;
    self.stopButton.wantsLayer = YES;
    self.stopButton.layer.backgroundColor = accentColor.CGColor;
    self.stopButton.layer.cornerRadius = 14;
    self.stopButton.contentTintColor = [NSColor whiteColor];
    [inputContainer addSubview:self.stopButton];

    // Model selector dropdown
    self.modelSelector = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.modelSelector.translatesAutoresizingMaskIntoConstraints = NO;
    self.modelSelector.target = self;
    self.modelSelector.action = @selector(modelChanged:);
    self.modelSelector.font = [NSFont systemFontOfSize:11];
    self.modelSelector.controlSize = NSControlSizeSmall;
    self.modelSelector.bordered = NO;
    self.modelSelector.contentTintColor = secondaryTextColor();
    [[self.modelSelector cell] setArrowPosition:NSPopUpArrowAtBottom];
    [inputContainer addSubview:self.modelSelector];

    // Populate model selector
    [self populateModelSelector];

    // Loading indicator
    self.loadingIndicator = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    self.loadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.loadingIndicator.style = NSProgressIndicatorStyleSpinning;
    self.loadingIndicator.controlSize = NSControlSizeRegular;
    self.loadingIndicator.displayedWhenStopped = NO;
    // Use system appearance for loading indicator
    [inputContainer addSubview:self.loadingIndicator];

    // Status label
    self.statusLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.stringValue = @"";
    self.statusLabel.font = [NSFont systemFontOfSize:11];
    self.statusLabel.textColor = secondaryTextColor();
    self.statusLabel.bezeled = NO;
    self.statusLabel.editable = NO;
    self.statusLabel.selectable = NO;
    self.statusLabel.backgroundColor = [NSColor clearColor];
    [inputContainer addSubview:self.statusLabel];

    // Layout constraints
    NSDictionary *views = @{
        @"chat": self.chatScrollView,
        @"input": inputContainer,
        @"inputScroll": self.inputScrollView,
        @"send": self.sendButton,
        @"stop": self.stopButton,
        @"model": self.modelSelector,
        @"loading": self.loadingIndicator,
        @"status": self.statusLabel,
        @"stack": self.chatStackView,
        @"doc": documentView
    };

    // Main layout
    [NSLayoutConstraint activateConstraints:
     [NSLayoutConstraint constraintsWithVisualFormat:@"H:|[chat]|"
                                             options:0 metrics:nil views:views]];
    [NSLayoutConstraint activateConstraints:
     [NSLayoutConstraint constraintsWithVisualFormat:@"H:|[input]|"
                                             options:0 metrics:nil views:views]];

    // Input container height constraint (dynamic, starts at 80)
    self.inputContainerHeightConstraint = [inputContainer.heightAnchor constraintEqualToConstant:80];
    self.inputContainerHeightConstraint.active = YES;

    // Chat scroll view starts below the title bar
    [NSLayoutConstraint activateConstraints:@[
        [self.chatScrollView.topAnchor constraintEqualToAnchor:self.titleBarView.bottomAnchor],
        [self.chatScrollView.bottomAnchor constraintEqualToAnchor:inputContainer.topAnchor],
        [inputContainer.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor]
    ]];

    // Input scroll view layout - takes most of the top area
    [NSLayoutConstraint activateConstraints:@[
        [self.inputScrollView.leadingAnchor constraintEqualToAnchor:inputContainer.leadingAnchor constant:10],
        [self.inputScrollView.topAnchor constraintEqualToAnchor:inputContainer.topAnchor constant:10],
        [self.inputScrollView.trailingAnchor constraintEqualToAnchor:self.loadingIndicator.leadingAnchor constant:-8]
    ]];

    // Placeholder label positioned inside the text view area (match textContainerInset)
    [NSLayoutConstraint activateConstraints:@[
        [self.placeholderLabel.leadingAnchor constraintEqualToAnchor:self.inputScrollView.leadingAnchor constant:14],
        [self.placeholderLabel.topAnchor constraintEqualToAnchor:self.inputScrollView.topAnchor constant:8]
    ]];

    // Loading indicator and send button on the right, vertically centered with input
    [NSLayoutConstraint activateConstraints:@[
        [self.loadingIndicator.trailingAnchor constraintEqualToAnchor:self.sendButton.leadingAnchor constant:-8],
        [self.loadingIndicator.centerYAnchor constraintEqualToAnchor:self.inputScrollView.centerYAnchor],
        [self.loadingIndicator.heightAnchor constraintEqualToConstant:20],
        [self.loadingIndicator.widthAnchor constraintEqualToConstant:20]
    ]];

    [NSLayoutConstraint activateConstraints:@[
        [self.sendButton.trailingAnchor constraintEqualToAnchor:inputContainer.trailingAnchor constant:-10],
        [self.sendButton.centerYAnchor constraintEqualToAnchor:self.inputScrollView.centerYAnchor],
        [self.sendButton.widthAnchor constraintEqualToConstant:28],
        [self.sendButton.heightAnchor constraintEqualToConstant:28]
    ]];

    // Stop button overlays the send button position
    [NSLayoutConstraint activateConstraints:@[
        [self.stopButton.widthAnchor constraintEqualToConstant:28],
        [self.stopButton.heightAnchor constraintEqualToConstant:28],
        [self.stopButton.centerXAnchor constraintEqualToAnchor:self.sendButton.centerXAnchor],
        [self.stopButton.centerYAnchor constraintEqualToAnchor:self.sendButton.centerYAnchor]
    ]];

    // Bottom row: status on left, model selector on right
    [NSLayoutConstraint activateConstraints:@[
        // Model selector (right side)
        [self.modelSelector.trailingAnchor constraintEqualToAnchor:inputContainer.trailingAnchor constant:-10],
        [self.modelSelector.centerYAnchor constraintEqualToAnchor:self.statusLabel.centerYAnchor],

        // Status label
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:inputContainer.leadingAnchor constant:20],
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.inputScrollView.bottomAnchor constant:4],
        [self.statusLabel.bottomAnchor constraintEqualToAnchor:inputContainer.bottomAnchor constant:-10],

        [self.statusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.modelSelector.leadingAnchor constant:-10]
    ]];

    // Document view constraints
    [NSLayoutConstraint activateConstraints:@[
        [documentView.leadingAnchor constraintEqualToAnchor:self.chatScrollView.contentView.leadingAnchor],
        [documentView.trailingAnchor constraintEqualToAnchor:self.chatScrollView.contentView.trailingAnchor],
        [documentView.topAnchor constraintEqualToAnchor:self.chatScrollView.contentView.topAnchor],
        [documentView.widthAnchor constraintEqualToAnchor:self.chatScrollView.widthAnchor]
    ]];

    // Stack view constraints - pin to bottom so content sits at bottom of scroll view
    [NSLayoutConstraint activateConstraints:@[
        [self.chatStackView.leadingAnchor constraintEqualToAnchor:documentView.leadingAnchor],
        [self.chatStackView.trailingAnchor constraintEqualToAnchor:documentView.trailingAnchor],
        [self.chatStackView.bottomAnchor constraintEqualToAnchor:documentView.bottomAnchor],
        // Top constraint with low priority - allows stack to grow upward
        [self.chatStackView.topAnchor constraintGreaterThanOrEqualToAnchor:documentView.topAnchor]
    ]];

    // Document view must be at least as tall as the visible area
    [NSLayoutConstraint activateConstraints:@[
        [documentView.heightAnchor constraintGreaterThanOrEqualToAnchor:self.chatScrollView.heightAnchor]
    ]];
}

#pragma mark - Client Setup

- (void)setupRAGClient {
    NSString *ragURL = [SettingsWindowController ragServiceURL];
    self.ragClient = [[RAGClient alloc] initWithBaseURL:ragURL];
    self.ragClient.delegate = self;

    // Fetch available models from the server
    [self populateModelSelector];
    [self updateStatus:@"Ready"];
}

- (void)populateModelSelector {
    [WALogger info:@"[RAG UI] populateModelSelector called"];
    [self.modelSelector removeAllItems];

    // Add placeholder while loading
    [self.modelSelector addItemWithTitle:@"Loading models..."];
    self.modelSelector.enabled = NO;

    // Fetch models from server
    [self.ragClient listModelsWithCompletion:^(NSArray<RAGModelItem *> *models, NSString *error) {
        [WALogger info:@"[RAG UI] listModelsWithCompletion returned - models: %lu, error: %@",
            (unsigned long)models.count, error];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.modelSelector removeAllItems];

            if (error) {
                [WALogger error:@"[RAG] Failed to fetch models: %@", error];
                [self.modelSelector addItemWithTitle:@"Error loading models"];
                // Show connection error message
                [self addErrorMessage:@"Could not connect to backend. Check your connection."];
                return;
            }

            if (models.count == 0) {
                [self.modelSelector addItemWithTitle:@"No models available"];
                [self addErrorMessage:@"No models available. Check your connection."];
                return;
            }

            self.ragModels = models;
            self.modelSelector.enabled = YES;

            // Group models by provider for better organization
            NSMutableDictionary<NSString *, NSMutableArray<RAGModelItem *> *> *byProvider = [NSMutableDictionary dictionary];
            for (RAGModelItem *model in models) {
                NSString *provider = model.provider ?: @"other";
                if (!byProvider[provider]) {
                    byProvider[provider] = [NSMutableArray array];
                }
                [byProvider[provider] addObject:model];
            }

            // Add models to selector, grouped by provider
            NSArray *providerOrder = @[@"gemini", @"anthropic", @"openai", @"other"];
            NSString *defaultModelId = @"gemini-3-pro";

            for (NSString *provider in providerOrder) {
                NSArray<RAGModelItem *> *providerModels = byProvider[provider];
                if (!providerModels || providerModels.count == 0) continue;

                // Add separator with provider name if we have multiple providers
                if (byProvider.count > 1 && self.modelSelector.numberOfItems > 0) {
                    [self.modelSelector.menu addItem:[NSMenuItem separatorItem]];
                }

                for (RAGModelItem *model in providerModels) {
                    // Add provider emoji prefix
                    NSString *prefix = @"";
                    if ([model.provider isEqualToString:@"gemini"]) {
                        prefix = @"\u2728 ";  // sparkles for Gemini
                    } else if ([model.provider isEqualToString:@"anthropic"]) {
                        prefix = @"\U0001F9E0 ";  // brain for Anthropic
                    } else if ([model.provider isEqualToString:@"openai"]) {
                        prefix = @"\U0001F916 ";  // robot for OpenAI
                    }

                    NSString *displayName = [NSString stringWithFormat:@"%@%@", prefix, model.name];
                    [self.modelSelector addItemWithTitle:displayName];
                    self.modelSelector.lastItem.representedObject = model.modelId;
                }
            }

            // Select saved model or default
            NSString *savedModelId = [[NSUserDefaults standardUserDefaults] stringForKey:@"RAGSelectedModel"];
            NSString *modelToSelect = savedModelId.length > 0 ? savedModelId : defaultModelId;

            // Find and select the model
            BOOL selected = NO;
            NSString *selectedModelDisplayName = nil;
            for (NSMenuItem *item in self.modelSelector.itemArray) {
                if ([item.representedObject isEqualToString:modelToSelect]) {
                    [self.modelSelector selectItem:item];
                    self.selectedRAGModelId = modelToSelect;
                    selectedModelDisplayName = item.title;
                    selected = YES;
                    break;
                }
            }

            // If not found, select first non-separator item
            if (!selected && self.modelSelector.numberOfItems > 0) {
                for (NSMenuItem *item in self.modelSelector.itemArray) {
                    if (!item.isSeparatorItem && item.representedObject) {
                        [self.modelSelector selectItem:item];
                        self.selectedRAGModelId = item.representedObject;
                        selectedModelDisplayName = item.title;
                        break;
                    }
                }
            }

            // Show welcome message with current model
            NSString *welcomeMessage = [NSString stringWithFormat:
                @"I'm your WhatsApp Assistant powered by %@.\n"
                "I can search your chats, read messages, and answer questions.\n"
                "Just ask me anything!",
                selectedModelDisplayName ?: @"AI"];
            [self addSystemMessage:welcomeMessage];
        });
    }];
}

- (void)modelChanged:(NSPopUpButton *)sender {
    NSString *selectedModelId = sender.selectedItem.representedObject;
    if (selectedModelId) {
        self.selectedRAGModelId = selectedModelId;
        [[NSUserDefaults standardUserDefaults] setObject:selectedModelId forKey:@"RAGSelectedModel"];

        NSString *displayName = sender.selectedItem.title;
        [self updateStatus:@"Ready"];

        // Add system message about model change
        [self addSystemMessage:[NSString stringWithFormat:@"Switched to %@", displayName]];
    }
}

#pragma mark - Title Generation

- (void)generateTitleIfNeeded {
    if (self.hasTitleBeenGenerated || !self.firstUserMessage) {
        return;
    }
    self.hasTitleBeenGenerated = YES;

    // Request title generation from backend
    NSString *ragURL = [SettingsWindowController ragServiceURL];
    NSString *urlString = [NSString stringWithFormat:@"%@/generate-title", ragURL];
    NSURL *url = [NSURL URLWithString:urlString];

    if (!url) return;

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSDictionary *body = @{
        @"message": self.firstUserMessage
    };

    NSError *jsonError;
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
    if (jsonError) return;

    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) return;

        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *title = json[@"title"];

        if (title.length > 0) {
            // Clean up the title - remove quotes and trim
            title = [title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            title = [title stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\"'"]];

            // Limit title length
            if (title.length > 40) {
                title = [[title substringToIndex:37] stringByAppendingString:@"..."];
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                self.titleLabel.stringValue = title;
            });
        }
    }];
    [task resume];
}

#pragma mark - Window Control

- (void)showWindow {
    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:self.inputTextView];
}

- (void)hideWindow {
    [self.window orderOut:nil];
}

- (void)toggleWindow {
    if (self.window.isVisible) {
        [self hideWindow];
    } else {
        [self showWindow];
    }
}

- (BOOL)isVisible {
    return self.window.isVisible;
}

- (void)updateStatus:(NSString *)status {
    self.statusLabel.stringValue = status;
}

- (void)setProcessing:(BOOL)processing {
    self.isProcessing = processing;
    self.inputTextView.editable = !processing;

    // Toggle between send and stop buttons
    self.sendButton.hidden = processing;
    self.stopButton.hidden = !processing;

    if (processing) {
        [self.loadingIndicator startAnimation:nil];
    } else {
        [self.loadingIndicator stopAnimation:nil];
    }
}

@end
