//
//  BotChatWindowController.m
//  mcpwa
//
//  Bot Chat Window - Gemini-powered chat with WhatsApp MCP integration
//

#import "BotChatWindowController.h"
#import "WAAccessibility.h"
#import "DebugConfigWindowController.h"
#import "SettingsWindowController.h"
#import "WALogger.h"

// Claude-style light mode colors
// User bubble: warm beige/tan (Claude style)
#define kUserBubbleColorLight [NSColor colorWithRed:0.91 green:0.87 blue:0.82 alpha:1.0]  // #E8DDD2
#define kUserBubbleColorDark [NSColor colorWithRed:0.35 green:0.32 blue:0.28 alpha:1.0]   // Dark mode variant

// Bot bubble: white with subtle appearance (Claude style)
#define kBotBubbleColorLight [NSColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:1.0]      // Pure white
#define kBotBubbleColorDark [NSColor colorWithWhite:0.22 alpha:1.0]                        // Dark gray

// Function bubble color (muted purple)
#define kFunctionBubbleColor [NSColor colorWithRed:0.45 green:0.38 blue:0.55 alpha:1.0]

// Claude-style background colors
#define kBackgroundColorLight [NSColor colorWithRed:0.98 green:0.976 blue:0.969 alpha:1.0]  // #FAF9F7
#define kBackgroundColorDark [NSColor colorWithWhite:0.12 alpha:1.0]

// Input area background
#define kInputBackgroundColorLight [NSColor colorWithRed:0.98 green:0.976 blue:0.969 alpha:1.0]
#define kInputBackgroundColorDark [NSColor colorWithWhite:0.15 alpha:1.0]

// Text colors
#define kTextColorLight [NSColor colorWithRed:0.2 green:0.18 blue:0.16 alpha:1.0]          // Dark brown
#define kTextColorDark [NSColor colorWithWhite:0.92 alpha:1.0]
#define kSecondaryTextColorLight [NSColor colorWithRed:0.45 green:0.42 blue:0.4 alpha:1.0]
#define kSecondaryTextColorDark [NSColor colorWithWhite:0.6 alpha:1.0]

// Helper to check if current appearance is dark
static inline BOOL isDarkMode(void) {
    NSAppearance *appearance = [NSApp effectiveAppearance];
    if (@available(macOS 10.14, *)) {
        NSAppearanceName name = [appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
        return [name isEqualToString:NSAppearanceNameDarkAqua];
    }
    return NO;
}

// Theme-aware color helpers
static inline NSColor *backgroundColor(void) {
    return isDarkMode() ? kBackgroundColorDark : kBackgroundColorLight;
}

static inline NSColor *inputBackgroundColor(void) {
    return isDarkMode() ? kInputBackgroundColorDark : kInputBackgroundColorLight;
}

static inline NSColor *userBubbleColor(void) {
    return isDarkMode() ? kUserBubbleColorDark : kUserBubbleColorLight;
}

static inline NSColor *botBubbleColor(void) {
    return isDarkMode() ? kBotBubbleColorDark : kBotBubbleColorLight;
}

static inline NSColor *primaryTextColor(void) {
    return isDarkMode() ? kTextColorDark : kTextColorLight;
}

static inline NSColor *secondaryTextColor(void) {
    return isDarkMode() ? kSecondaryTextColorDark : kSecondaryTextColorLight;
}

// Message types for display
typedef NS_ENUM(NSInteger, ChatMessageType) {
    ChatMessageTypeUser,
    ChatMessageTypeBot,
    ChatMessageTypeFunction,
    ChatMessageTypeError,
    ChatMessageTypeSystem
};

// Chat message for display
@interface ChatDisplayMessage : NSObject
@property (nonatomic, assign) ChatMessageType type;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy, nullable) NSString *functionName;
@property (nonatomic, assign) BOOL isLoading;
@end

@implementation ChatDisplayMessage
@end

#pragma mark - BotChatWindowController

@interface BotChatWindowController () <NSPopoverDelegate, NSTextViewDelegate>
@property (nonatomic, strong) GeminiClient *geminiClient;
@property (nonatomic, strong) NSMutableArray<ChatDisplayMessage *> *messages;
@property (nonatomic, strong) NSScrollView *chatScrollView;
@property (nonatomic, strong) NSStackView *chatStackView;
@property (nonatomic, strong) NSScrollView *inputScrollView;
@property (nonatomic, strong) NSTextView *inputTextView;
@property (nonatomic, strong) NSTextField *placeholderLabel;
@property (nonatomic, strong) NSLayoutConstraint *inputContainerHeightConstraint;
@property (nonatomic, strong) NSButton *sendButton;
@property (nonatomic, strong) NSButton *stopButton;
@property (nonatomic, strong) NSProgressIndicator *loadingIndicator;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, assign) BOOL isProcessing;
@property (nonatomic, assign) BOOL isCancelled;
@property (nonatomic, strong) NSArray<NSDictionary *> *mcpTools;
@property (nonatomic, strong) NSPopUpButton *modelSelector;
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
        [self setupWindow];
        [self setupGeminiClient];
        [self loadMCPTools];
    }
    return self;
}

- (void)setupWindow {
    // Create window
    NSRect frame = NSMakeRect(0, 0, 500, 600);
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
    window.backgroundColor = backgroundColor();
    [window center];

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

    // Flip the scroll view so content starts at top
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
    self.inputTextView.font = [NSFont systemFontOfSize:14];
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
    self.placeholderLabel.font = [NSFont systemFontOfSize:14];
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
    [self populateModelSelector];
    [inputContainer addSubview:self.modelSelector];

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

    // Add top padding to account for titlebar area with traffic light buttons
    [NSLayoutConstraint activateConstraints:@[
        [self.chatScrollView.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:8],
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
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:inputContainer.leadingAnchor constant:10],
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.inputScrollView.bottomAnchor constant:4],
        [self.statusLabel.bottomAnchor constraintEqualToAnchor:inputContainer.bottomAnchor constant:-10],
        [self.modelSelector.trailingAnchor constraintEqualToAnchor:inputContainer.trailingAnchor constant:-10],
        [self.modelSelector.centerYAnchor constraintEqualToAnchor:self.statusLabel.centerYAnchor],
        [self.statusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.modelSelector.leadingAnchor constant:-10]
    ]];

    // Document view constraints
    [NSLayoutConstraint activateConstraints:@[
        [documentView.leadingAnchor constraintEqualToAnchor:self.chatScrollView.contentView.leadingAnchor],
        [documentView.trailingAnchor constraintEqualToAnchor:self.chatScrollView.contentView.trailingAnchor],
        [documentView.topAnchor constraintEqualToAnchor:self.chatScrollView.contentView.topAnchor],
        [documentView.widthAnchor constraintEqualToAnchor:self.chatScrollView.widthAnchor]
    ]];

    // Stack view constraints
    [NSLayoutConstraint activateConstraints:@[
        [self.chatStackView.leadingAnchor constraintEqualToAnchor:documentView.leadingAnchor],
        [self.chatStackView.trailingAnchor constraintEqualToAnchor:documentView.trailingAnchor],
        [self.chatStackView.topAnchor constraintEqualToAnchor:documentView.topAnchor],
        [self.chatStackView.bottomAnchor constraintEqualToAnchor:documentView.bottomAnchor]
    ]];

    // Add welcome message
    [self addSystemMessage:@"Welcome! I'm your assistant powered by Gemini. I can:\n"
                           "- Read and send WhatsApp messages\n"
                           "- Search the web (Google Search grounding)\n"
                           "- Run shell commands on your Mac\n"
                           "Just ask me anything!"];
}

- (void)setupGeminiClient {
    NSString *apiKey = [GeminiClient loadAPIKey];

    if (!apiKey) {
        [self addSystemMessage:@"No Gemini API key found. Please set GEMINI_API_KEY environment variable "
                               "or add it to ~/Library/Application Support/mcpwa/config.json"];
        self.inputTextView.editable = NO;
        self.sendButton.enabled = NO;
        return;
    }

    self.geminiClient = [[GeminiClient alloc] initWithAPIKey:apiKey];
    self.geminiClient.delegate = self;

    // Set up tool executor for automatic tool call looping
    __weak typeof(self) weakSelf = self;
    self.geminiClient.toolExecutor = ^(GeminiFunctionCall *call, GeminiToolExecutorCompletion completion) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        [strongSelf updateStatus:[NSString stringWithFormat:@"Calling %@...", call.name]];

        [strongSelf executeMCPTool:call.name args:call.args completion:^(NSString *result) {
            // Show function result in chat only if debug mode is enabled
            if ([DebugConfigWindowController showDebugInChatEnabled]) {
                [strongSelf addFunctionMessage:call.name result:result];
            }
            completion(result);
        }];
    };

    // Load saved model preference
    NSString *savedModel = [[NSUserDefaults standardUserDefaults] stringForKey:@"GeminiSelectedModel"];
    if (savedModel.length > 0) {
        self.geminiClient.model = savedModel;
    }

    // Update model selector to reflect the loaded preference
    [self selectModelInSelector:self.geminiClient.model];

    NSString *displayName = [GeminiClient displayNameForModel:self.geminiClient.model];
    [self updateStatus:[NSString stringWithFormat:@"Ready (%@)", displayName]];
}

- (void)loadMCPTools {
    // Define MCP tools that Gemini can call
    self.mcpTools = @[
        @{
            @"name": @"whatsapp_start_session",
            @"description": @"Call this at the START of processing any user prompt that requires WhatsApp access. Initializes WhatsApp by navigating to Chats tab and clearing stale search state.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{},
                @"required": @[]
            }
        },
        @{
            @"name": @"whatsapp_stop_session",
            @"description": @"Call this at the END of processing any user prompt that required WhatsApp access. Cleans up by clearing any active search.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{},
                @"required": @[]
            }
        },
        @{
            @"name": @"whatsapp_status",
            @"description": @"Check WhatsApp accessibility status - whether the app is running and permissions are granted",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{},
                @"required": @[]
            }
        },
        @{
            @"name": @"whatsapp_list_chats",
            @"description": @"Get list of recent visible WhatsApp chats with last message preview. Returns chat names, last messages, timestamps, and whether chats are pinned or group chats.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"filter": @{
                        @"type": @"string",
                        @"description": @"Optional filter: 'all' (default), 'unread', 'favorites', or 'groups'",
                        @"enum": @[@"all", @"unread", @"favorites", @"groups"]
                    }
                },
                @"required": @[]
            }
        },
        @{
            @"name": @"whatsapp_get_current_chat",
            @"description": @"Get the currently open chat's name and all visible messages.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{},
                @"required": @[]
            }
        },
        @{
            @"name": @"whatsapp_open_chat",
            @"description": @"Open a specific chat by name. Use partial matching - e.g., 'John' will match 'John Smith'.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"name": @{
                        @"type": @"string",
                        @"description": @"Name of the chat or contact to open"
                    }
                },
                @"required": @[@"name"]
            }
        },
        @{
            @"name": @"whatsapp_get_messages",
            @"description": @"Get messages from a specific chat. Opens the chat if not already open, then returns all visible messages.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"chat_name": @{
                        @"type": @"string",
                        @"description": @"Name of the chat to get messages from"
                    }
                },
                @"required": @[@"chat_name"]
            }
        },
        @{
            @"name": @"whatsapp_send_message",
            @"description": @"Send a message to the currently open chat. Use whatsapp_open_chat first to select the recipient.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"message": @{
                        @"type": @"string",
                        @"description": @"The message text to send"
                    }
                },
                @"required": @[@"message"]
            }
        },
        @{
            @"name": @"whatsapp_search",
            @"description": @"Global search across all WhatsApp chats. Searches for keywords in chat names and message content.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"query": @{
                        @"type": @"string",
                        @"description": @"Search query - keywords to find in chat names and message content"
                    }
                },
                @"required": @[@"query"]
            }
        },
        // === Local Tools (Gemini can search web and fetch URLs natively) ===
        @{
            @"name": @"run_shell_command",
            @"description": @"Execute a shell command on the local Mac and return the output. Use for file operations, system info, running scripts, etc. Examples: 'ls -la', 'cat file.txt', 'date', 'pwd'.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"command": @{
                        @"type": @"string",
                        @"description": @"The shell command to execute"
                    }
                },
                @"required": @[@"command"]
            }
        }
    ];

    [self.geminiClient configureMCPTools:self.mcpTools];
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

#pragma mark - Model Selection

- (void)populateModelSelector {
    [self.modelSelector removeAllItems];
    for (NSString *modelId in [GeminiClient availableModels]) {
        NSString *displayName = [GeminiClient displayNameForModel:modelId];
        [self.modelSelector addItemWithTitle:displayName];
        self.modelSelector.lastItem.representedObject = modelId;
    }
}

- (void)selectModelInSelector:(NSString *)modelId {
    for (NSMenuItem *item in self.modelSelector.itemArray) {
        if ([item.representedObject isEqualToString:modelId]) {
            [self.modelSelector selectItem:item];
            return;
        }
    }
}

- (void)modelChanged:(NSPopUpButton *)sender {
    NSString *selectedModelId = sender.selectedItem.representedObject;
    if (selectedModelId) {
        self.geminiClient.model = selectedModelId;
        [[NSUserDefaults standardUserDefaults] setObject:selectedModelId forKey:@"GeminiSelectedModel"];

        NSString *displayName = [GeminiClient displayNameForModel:selectedModelId];
        [self updateStatus:[NSString stringWithFormat:@"Model: %@", displayName]];

        // Add system message about model change
        [self addSystemMessage:[NSString stringWithFormat:@"Switched to %@", displayName]];
    }
}


#pragma mark - Message Display

- (void)addUserMessage:(NSString *)text {
    ChatDisplayMessage *msg = [[ChatDisplayMessage alloc] init];
    msg.type = ChatMessageTypeUser;
    msg.text = text;
    [self.messages addObject:msg];
    [self addMessageBubble:msg];
}

- (void)addBotMessage:(NSString *)text {
    ChatDisplayMessage *msg = [[ChatDisplayMessage alloc] init];
    msg.type = ChatMessageTypeBot;
    msg.text = text;
    [self.messages addObject:msg];
    [self addMessageBubble:msg];
}

- (void)addFunctionMessage:(NSString *)functionName result:(NSString *)result {
    ChatDisplayMessage *msg = [[ChatDisplayMessage alloc] init];
    msg.type = ChatMessageTypeFunction;
    msg.functionName = functionName;
    msg.text = result;
    [self.messages addObject:msg];
    [self addMessageBubble:msg];
}

- (void)addSystemMessage:(NSString *)text {
    ChatDisplayMessage *msg = [[ChatDisplayMessage alloc] init];
    msg.type = ChatMessageTypeSystem;
    msg.text = text;
    [self.messages addObject:msg];
    [self addMessageBubble:msg];
}

- (void)addErrorMessage:(NSString *)text {
    ChatDisplayMessage *msg = [[ChatDisplayMessage alloc] init];
    msg.type = ChatMessageTypeError;
    msg.text = text;
    [self.messages addObject:msg];
    [self addMessageBubble:msg];
}

- (NSAttributedString *)attributedStringFromMarkdown:(NSString *)markdown textColor:(NSColor *)textColor {
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];

    NSFont *regularFont = [NSFont systemFontOfSize:14];
    NSFont *boldFont = [NSFont boldSystemFontOfSize:14];
    NSFont *italicFont = [NSFont fontWithDescriptor:[[regularFont fontDescriptor] fontDescriptorWithSymbolicTraits:NSFontDescriptorTraitItalic] size:14];
    if (!italicFont) italicFont = regularFont;
    NSFont *h3Font = [NSFont boldSystemFontOfSize:16];
    NSFont *h2Font = [NSFont boldSystemFontOfSize:18];
    NSFont *h1Font = [NSFont boldSystemFontOfSize:20];

    NSDictionary *defaultAttrs = @{
        NSFontAttributeName: regularFont,
        NSForegroundColorAttributeName: textColor
    };

    NSArray *lines = [markdown componentsSeparatedByString:@"\n"];

    for (NSUInteger lineIdx = 0; lineIdx < lines.count; lineIdx++) {
        NSString *line = lines[lineIdx];

        // Handle headers
        NSFont *lineFont = regularFont;
        if ([line hasPrefix:@"### "]) {
            line = [line substringFromIndex:4];
            lineFont = h3Font;
        } else if ([line hasPrefix:@"## "]) {
            line = [line substringFromIndex:3];
            lineFont = h2Font;
        } else if ([line hasPrefix:@"# "]) {
            line = [line substringFromIndex:2];
            lineFont = h1Font;
        }

        // Handle bullet points
        if ([line hasPrefix:@"* "] || [line hasPrefix:@"- "]) {
            line = [NSString stringWithFormat:@"• %@", [line substringFromIndex:2]];
        }

        // Parse inline formatting character by character
        NSMutableAttributedString *lineAttr = [[NSMutableAttributedString alloc] init];
        NSUInteger i = 0;
        NSUInteger len = line.length;

        while (i < len) {
            unichar c = [line characterAtIndex:i];

            // Check for markdown link [text](url)
            if (c == '[') {
                NSUInteger textStart = i + 1;
                NSUInteger textEnd = textStart;
                // Find closing ]
                while (textEnd < len && [line characterAtIndex:textEnd] != ']') {
                    textEnd++;
                }
                // Check for ( immediately after ]
                if (textEnd < len && textEnd + 1 < len && [line characterAtIndex:textEnd + 1] == '(') {
                    NSUInteger urlStart = textEnd + 2;
                    NSUInteger urlEnd = urlStart;
                    // Find closing )
                    while (urlEnd < len && [line characterAtIndex:urlEnd] != ')') {
                        urlEnd++;
                    }
                    if (urlEnd < len && urlEnd > urlStart && textEnd > textStart) {
                        // Valid markdown link found
                        NSString *linkText = [line substringWithRange:NSMakeRange(textStart, textEnd - textStart)];
                        NSString *urlString = [line substringWithRange:NSMakeRange(urlStart, urlEnd - urlStart)];
                        NSURL *url = [NSURL URLWithString:urlString];
                        if (url) {
                            NSMutableDictionary *linkAttrs = [NSMutableDictionary dictionaryWithDictionary:@{
                                NSFontAttributeName: lineFont,
                                NSForegroundColorAttributeName: [NSColor linkColor],
                                NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
                                NSLinkAttributeName: url
                            }];
                            NSAttributedString *linkAttr = [[NSAttributedString alloc] initWithString:linkText attributes:linkAttrs];
                            [lineAttr appendAttributedString:linkAttr];
                            i = urlEnd + 1;
                            continue;
                        }
                    }
                }
                // Not a valid markdown link, treat [ as regular character
            }

            // Check for bare URL (https:// or http://)
            if (c == 'h' && i + 7 < len) {
                NSString *remaining = [line substringFromIndex:i];
                if ([remaining hasPrefix:@"https://"] || [remaining hasPrefix:@"http://"]) {
                    // Find end of URL (space, newline, or end of string)
                    NSUInteger urlEnd = i;
                    while (urlEnd < len) {
                        unichar uc = [line characterAtIndex:urlEnd];
                        if (uc == ' ' || uc == '\t' || uc == '\n' || uc == ')' || uc == ']' || uc == '>' || uc == '"' || uc == '\'') {
                            break;
                        }
                        urlEnd++;
                    }
                    // Remove trailing punctuation that's likely not part of URL
                    while (urlEnd > i) {
                        unichar lastChar = [line characterAtIndex:urlEnd - 1];
                        if (lastChar == '.' || lastChar == ',' || lastChar == ';' || lastChar == ':' || lastChar == '!' || lastChar == '?') {
                            urlEnd--;
                        } else {
                            break;
                        }
                    }
                    if (urlEnd > i) {
                        NSString *urlString = [line substringWithRange:NSMakeRange(i, urlEnd - i)];
                        NSURL *url = [NSURL URLWithString:urlString];
                        if (url) {
                            NSMutableDictionary *linkAttrs = [NSMutableDictionary dictionaryWithDictionary:@{
                                NSFontAttributeName: lineFont,
                                NSForegroundColorAttributeName: [NSColor linkColor],
                                NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
                                NSLinkAttributeName: url
                            }];
                            NSAttributedString *linkAttr = [[NSAttributedString alloc] initWithString:urlString attributes:linkAttrs];
                            [lineAttr appendAttributedString:linkAttr];
                            i = urlEnd;
                            continue;
                        }
                    }
                }
            }

            // Check for bold (**) or italic (*)
            if (c == '*') {
                // Check for bold **
                if (i + 1 < len && [line characterAtIndex:i + 1] == '*') {
                    // Look for closing **
                    NSUInteger start = i + 2;
                    NSUInteger end = start;
                    BOOL foundClosing = NO;
                    while (end + 1 < len) {
                        if ([line characterAtIndex:end] == '*' && [line characterAtIndex:end + 1] == '*') {
                            foundClosing = YES;
                            break;
                        }
                        end++;
                    }
                    if (foundClosing && end > start) {
                        // Found closing **
                        NSString *boldText = [line substringWithRange:NSMakeRange(start, end - start)];
                        NSFont *font = (lineFont == regularFont) ? boldFont : [NSFont boldSystemFontOfSize:lineFont.pointSize];
                        NSAttributedString *boldAttr = [[NSAttributedString alloc] initWithString:boldText attributes:@{
                            NSFontAttributeName: font,
                            NSForegroundColorAttributeName: textColor
                        }];
                        [lineAttr appendAttributedString:boldAttr];
                        i = end + 2;
                        continue;
                    }
                    // No closing ** found - treat as literal text and advance past both *
                    NSAttributedString *literalAttr = [[NSAttributedString alloc] initWithString:@"**" attributes:@{
                        NSFontAttributeName: lineFont,
                        NSForegroundColorAttributeName: textColor
                    }];
                    [lineAttr appendAttributedString:literalAttr];
                    i += 2;
                    continue;
                }

                // Check for single italic *
                NSUInteger start = i + 1;
                NSUInteger end = start;
                while (end < len && [line characterAtIndex:end] != '*') {
                    end++;
                }
                if (end < len && end > start) {
                    // Found closing *
                    NSString *italicText = [line substringWithRange:NSMakeRange(start, end - start)];
                    NSAttributedString *italicAttr = [[NSAttributedString alloc] initWithString:italicText attributes:@{
                        NSFontAttributeName: italicFont,
                        NSForegroundColorAttributeName: textColor
                    }];
                    [lineAttr appendAttributedString:italicAttr];
                    i = end + 1;
                    continue;
                }

                // No closing * found - treat as literal *
                NSAttributedString *literalAttr = [[NSAttributedString alloc] initWithString:@"*" attributes:@{
                    NSFontAttributeName: lineFont,
                    NSForegroundColorAttributeName: textColor
                }];
                [lineAttr appendAttributedString:literalAttr];
                i++;
                continue;
            }

            // Regular character - collect consecutive regular chars for efficiency
            // Stop at formatting characters: *, [, and h (for potential URLs)
            NSUInteger start = i;
            while (i < len) {
                unichar rc = [line characterAtIndex:i];
                if (rc == '*' || rc == '[') break;
                // Check for potential URL start
                if (rc == 'h' && i + 7 < len) {
                    NSString *potentialUrl = [line substringFromIndex:i];
                    if ([potentialUrl hasPrefix:@"https://"] || [potentialUrl hasPrefix:@"http://"]) {
                        break;
                    }
                }
                i++;
            }
            if (i > start) {
                NSString *regularText = [line substringWithRange:NSMakeRange(start, i - start)];
                NSAttributedString *regularAttr = [[NSAttributedString alloc] initWithString:regularText attributes:@{
                    NSFontAttributeName: lineFont,
                    NSForegroundColorAttributeName: textColor
                }];
                [lineAttr appendAttributedString:regularAttr];
            }
        }

        [result appendAttributedString:lineAttr];

        // Add newline between lines (except last)
        if (lineIdx < lines.count - 1) {
            [result appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:defaultAttrs]];
        }
    }

    return result;
}

- (void)addMessageBubble:(ChatDisplayMessage *)message {
    NSView *bubbleContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    bubbleContainer.translatesAutoresizingMaskIntoConstraints = NO;

    // Create bubble background
    NSView *bubble = [[NSView alloc] initWithFrame:NSZeroRect];
    bubble.translatesAutoresizingMaskIntoConstraints = NO;
    bubble.wantsLayer = YES;

    // Style based on message type
    NSColor *bubbleColor;
    NSColor *textColor;
    BOOL alignRight = NO;
    BOOL useMarkdown = NO;
    BOOL useBubbleStyle = YES;  // Whether to show bubble background
    NSString *displayText = message.text;
    CGFloat cornerRadius = 16;

    // Calculate max width as 3/4 of the chat view width
    CGFloat chatWidth = self.chatScrollView.bounds.size.width;
    if (chatWidth < 100) chatWidth = 500;  // Fallback if not yet laid out
    CGFloat maxBubbleWidth = floor(chatWidth * 0.75);
    CGFloat horizontalPadding = 14;
    CGFloat maxTextWidth = maxBubbleWidth - (horizontalPadding * 2);

    switch (message.type) {
        case ChatMessageTypeUser:
            // Claude-style user bubble: warm beige/tan, right-aligned
            bubbleColor = userBubbleColor();
            textColor = primaryTextColor();
            alignRight = YES;
            useBubbleStyle = YES;
            break;
        case ChatMessageTypeBot:
            // Claude-style: no bubble, just text on the left spanning 3/4 width
            bubbleColor = [NSColor clearColor];
            textColor = primaryTextColor();
            useMarkdown = YES;
            useBubbleStyle = NO;  // No bubble background for bot
            horizontalPadding = 0;
            maxTextWidth = maxBubbleWidth;  // Full 3/4 width for text (no padding)
            break;
        case ChatMessageTypeFunction:
            bubbleColor = kFunctionBubbleColor;
            textColor = [NSColor whiteColor]; // Always white on purple
            if (message.functionName) {
                displayText = [NSString stringWithFormat:@"[%@]\n%@", message.functionName, message.text];
            }
            cornerRadius = 8;
            break;
        case ChatMessageTypeError:
            // Muted red for errors
            if (isDarkMode()) {
                bubbleColor = [NSColor colorWithRed:0.5 green:0.2 blue:0.2 alpha:1.0];
            } else {
                bubbleColor = [NSColor colorWithRed:0.95 green:0.9 blue:0.9 alpha:1.0];
            }
            textColor = isDarkMode() ? [NSColor whiteColor] : [NSColor colorWithRed:0.6 green:0.2 blue:0.2 alpha:1.0];
            cornerRadius = 8;
            break;
        case ChatMessageTypeSystem:
            // System messages: subtle, muted appearance
            if (isDarkMode()) {
                bubbleColor = [NSColor colorWithWhite:0.2 alpha:1.0];
            } else {
                bubbleColor = [NSColor colorWithRed:0.96 green:0.95 blue:0.93 alpha:1.0];
            }
            textColor = secondaryTextColor();
            cornerRadius = 8;
            break;
    }

    bubble.layer.cornerRadius = useBubbleStyle ? cornerRadius : 0;

    // Create text view for selectable text with proper background handling
    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, maxTextWidth, 20)];
    textView.translatesAutoresizingMaskIntoConstraints = NO;
    textView.editable = NO;
    textView.selectable = YES;
    textView.backgroundColor = [NSColor clearColor];
    textView.drawsBackground = NO;
    textView.textContainerInset = NSZeroSize;
    textView.textContainer.lineFragmentPadding = 0;
    textView.textContainer.widthTracksTextView = NO;
    textView.textContainer.containerSize = NSMakeSize(maxTextWidth, CGFLOAT_MAX);
    textView.verticallyResizable = YES;
    textView.horizontallyResizable = NO;
    // Enable clickable links
    textView.automaticLinkDetectionEnabled = NO; // We handle links ourselves in markdown parser
    [textView setLinkTextAttributes:@{
        NSForegroundColorAttributeName: [NSColor linkColor],
        NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
        NSCursorAttributeName: [NSCursor pointingHandCursor]
    }];

    if (useMarkdown) {
        [textView.textStorage setAttributedString:[self attributedStringFromMarkdown:displayText textColor:textColor]];
    } else {
        NSFont *font = (message.type == ChatMessageTypeFunction) ?
            [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular] :
            [NSFont systemFontOfSize:14];
        NSDictionary *attrs = @{
            NSFontAttributeName: font,
            NSForegroundColorAttributeName: textColor
        };
        NSAttributedString *attrStr = [[NSAttributedString alloc] initWithString:displayText attributes:attrs];
        [textView.textStorage setAttributedString:attrStr];
    }

    // Calculate size for text view
    [textView.layoutManager ensureLayoutForTextContainer:textView.textContainer];
    NSRect textRect = [textView.layoutManager usedRectForTextContainer:textView.textContainer];
    CGFloat textHeight = ceil(textRect.size.height);

    bubble.layer.backgroundColor = bubbleColor.CGColor;

    [bubble addSubview:textView];
    [bubbleContainer addSubview:bubble];

    // Padding for text inside bubble
    CGFloat verticalPadding = useBubbleStyle ? 10 : 4;

    // Calculate actual text width for proper bubble sizing
    CGFloat actualTextWidth = MIN(ceil(textRect.size.width), maxTextWidth);

    // Constraints for text view in bubble
    [NSLayoutConstraint activateConstraints:@[
        [textView.leadingAnchor constraintEqualToAnchor:bubble.leadingAnchor constant:horizontalPadding],
        [textView.trailingAnchor constraintEqualToAnchor:bubble.trailingAnchor constant:-horizontalPadding],
        [textView.topAnchor constraintEqualToAnchor:bubble.topAnchor constant:verticalPadding],
        [textView.bottomAnchor constraintEqualToAnchor:bubble.bottomAnchor constant:-verticalPadding],
        [textView.widthAnchor constraintEqualToConstant:actualTextWidth],
        [textView.heightAnchor constraintEqualToConstant:textHeight]
    ]];

    // Constraints for bubble in container
    if (alignRight) {
        // User messages: right-aligned, bubble hugs content
        [NSLayoutConstraint activateConstraints:@[
            [bubble.trailingAnchor constraintEqualToAnchor:bubbleContainer.trailingAnchor]
        ]];
    } else {
        // Bot/other messages: left-aligned
        [NSLayoutConstraint activateConstraints:@[
            [bubble.leadingAnchor constraintEqualToAnchor:bubbleContainer.leadingAnchor]
        ]];
    }

    [NSLayoutConstraint activateConstraints:@[
        [bubble.topAnchor constraintEqualToAnchor:bubbleContainer.topAnchor],
        [bubble.bottomAnchor constraintEqualToAnchor:bubbleContainer.bottomAnchor]
    ]];

    // Add to stack view first, then set width constraint (views must be in same hierarchy)
    [self.chatStackView addArrangedSubview:bubbleContainer];

    // Container spans full width (margins handled by stackView edgeInsets)
    [bubbleContainer.widthAnchor constraintEqualToAnchor:self.chatStackView.widthAnchor constant:-48].active = YES;

    // Scroll to bottom after layout completes
    [self scrollToBottom];
}

- (void)scrollToBottom {
    // Delay scroll to allow layout to complete
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // Force layout
        [self.window layoutIfNeeded];

        // Get the last view in the stack
        NSArray *arrangedSubviews = self.chatStackView.arrangedSubviews;
        if (arrangedSubviews.count > 0) {
            NSView *lastView = arrangedSubviews.lastObject;
            // Scroll to make the last view visible
            [lastView scrollRectToVisible:lastView.bounds];
        }
    });
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

#pragma mark - Actions

- (void)sendMessage:(id)sender {
    NSString *text = [self.inputTextView.string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0 || self.isProcessing) return;

    self.isCancelled = NO;
    self.inputTextView.string = @"";
    [self updatePlaceholder];
    [self updateInputHeight];
    [self addUserMessage:text];
    [self setProcessing:YES];
    [self updateStatus:@"Thinking..."];

    [self.geminiClient sendMessage:text];
}

- (void)stopProcessing:(id)sender {
    // Set cancellation flag first
    self.isCancelled = YES;

    // Cancel the current Gemini request
    [self.geminiClient cancelRequest];

    // Clear conversation history to prevent stale function call chains
    [self.geminiClient clearHistory];

    // Reset processing state
    [self setProcessing:NO];
    [self updateStatus:@"Stopped"];

    // Add a system message indicating the request was cancelled
    [self addSystemMessage:@"Request cancelled."];
}

#pragma mark - MCP Tool Execution

- (void)executeMCPTool:(NSString *)name args:(NSDictionary *)args completion:(void(^)(NSString *result))completion {
    // Check if already cancelled before starting
    if (self.isCancelled) {
        return;
    }

    WAAccessibility *wa = [WAAccessibility shared];

    // Log tool execution start
    [WALogger info:@"[MCP] Tool call: %@", name];
    if (args.count > 0) {
        [WALogger debug:@"[MCP]   Args: %@", args];
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Check cancellation at start of background task
        if (self.isCancelled) {
            [WALogger debug:@"[MCP] Tool %@ cancelled before execution", name];
            return;
        }

        NSString *result = nil;
        NSDate *startTime = [NSDate date];

        @try {
            if ([name isEqualToString:@"whatsapp_start_session"]) {
                result = [self executeStartSession:wa];
            }
            else if ([name isEqualToString:@"whatsapp_stop_session"]) {
                result = [self executeStopSession:wa];
            }
            else if ([name isEqualToString:@"whatsapp_status"]) {
                result = [self executeStatus:wa];
            }
            else if ([name isEqualToString:@"whatsapp_list_chats"]) {
                result = [self executeListChats:wa filter:args[@"filter"]];
            }
            else if ([name isEqualToString:@"whatsapp_get_current_chat"]) {
                result = [self executeGetCurrentChat:wa];
            }
            else if ([name isEqualToString:@"whatsapp_open_chat"]) {
                result = [self executeOpenChat:wa name:args[@"name"]];
            }
            else if ([name isEqualToString:@"whatsapp_get_messages"]) {
                result = [self executeGetMessages:wa chatName:args[@"chat_name"]];
            }
            else if ([name isEqualToString:@"whatsapp_send_message"]) {
                result = [self executeSendMessage:wa message:args[@"message"]];
            }
            else if ([name isEqualToString:@"whatsapp_search"]) {
                result = [self executeSearch:wa query:args[@"query"]];
            }
            // Local tools (Gemini handles web search/fetch natively)
            else if ([name isEqualToString:@"run_shell_command"]) {
                result = [self executeShellCommand:args[@"command"]];
            }
            else {
                result = [NSString stringWithFormat:@"Unknown tool: %@", name];
            }
        } @catch (NSException *exception) {
            result = [NSString stringWithFormat:@"Error: %@", exception.reason];
            [WALogger error:@"[MCP] Tool %@ exception: %@", name, exception.reason];
        }

        NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:startTime];
        [WALogger info:@"[MCP] Tool %@ completed (%.2fs)", name, elapsed];

        // Log full result for debugging (split into lines for readability)
        [WALogger debug:@"[MCP]   Result:"];
        // Split result into lines and log each
        NSArray *lines = [result componentsSeparatedByString:@"\n"];
        for (NSString *line in lines) {
            if (line.length > 0) {
                [WALogger debug:@"[MCP]     %@", line];
            }
        }

        // Only call completion if not cancelled
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!self.isCancelled) {
                completion(result);
            } else {
                [WALogger debug:@"[MCP] Tool %@ cancelled, skipping completion", name];
            }
        });
    });
}

- (NSString *)executeStartSession:(WAAccessibility *)wa {
    if (![wa isWhatsAppAvailable]) {
        return @"WhatsApp is not available. Please launch WhatsApp Desktop and grant accessibility permissions.";
    }

    [wa ensureWhatsAppVisible];
    [wa navigateToChats];
    [NSThread sleepForTimeInterval:0.3];

    if ([wa isInSearchMode]) {
        [wa clearSearch];
        [NSThread sleepForTimeInterval:0.3];
    }

    [wa selectChatFilter:WAChatFilterAll];

    return @"Session started. WhatsApp is ready.";
}

- (NSString *)executeStopSession:(WAAccessibility *)wa {
    if ([wa isInSearchMode]) {
        [wa clearSearch];
    }
    return @"Session stopped.";
}

- (NSString *)executeStatus:(WAAccessibility *)wa {
    BOOL available = [wa isWhatsAppAvailable];
    return [NSString stringWithFormat:@"WhatsApp is %@", available ? @"available and accessible" : @"not available"];
}

- (NSString *)executeListChats:(WAAccessibility *)wa filter:(NSString *)filterString {
    if (![wa isWhatsAppAvailable]) {
        return @"WhatsApp is not available";
    }

    WAChatFilter filter = WAChatFilterAll;
    if (filterString) {
        filter = [WAAccessibility chatFilterFromString:filterString];
    }

    NSArray<WAChat *> *chats = [wa getRecentChatsWithFilter:filter];

    NSMutableString *result = [NSMutableString stringWithFormat:@"Found %lu chats:\n", (unsigned long)chats.count];
    for (WAChat *chat in chats) {
        [result appendFormat:@"- %@: %@\n", chat.name, chat.lastMessage ?: @"(no message)"];
    }

    return result;
}

- (NSString *)executeGetCurrentChat:(WAAccessibility *)wa {
    WACurrentChat *current = [wa getCurrentChat];
    if (!current) {
        return @"No chat is currently open";
    }

    NSMutableString *result = [NSMutableString stringWithFormat:@"Chat: %@\n", current.name];
    if (current.lastSeen.length > 0) {
        [result appendFormat:@"Last seen: %@\n", current.lastSeen];
    }
    [result appendFormat:@"\nMessages (%lu):\n", (unsigned long)current.messages.count];

    for (WAMessage *msg in current.messages) {
        NSString *direction = msg.direction == WAMessageDirectionIncoming ? @"<" : @">";
        if (msg.sender) {
            [result appendFormat:@"%@ [%@]: %@\n", direction, msg.sender, msg.text];
        } else {
            [result appendFormat:@"%@ %@\n", direction, msg.text];
        }
    }

    return result;
}

- (NSString *)executeOpenChat:(WAAccessibility *)wa name:(NSString *)name {
    if (!name) return @"Chat name is required";

    BOOL success = [wa openChatWithName:name];
    if (success) {
        [NSThread sleepForTimeInterval:0.3];
        WACurrentChat *current = [wa getCurrentChat];
        return [NSString stringWithFormat:@"Opened chat: %@", current.name ?: name];
    } else {
        return [NSString stringWithFormat:@"Could not find chat matching: %@", name];
    }
}

- (NSString *)executeGetMessages:(WAAccessibility *)wa chatName:(NSString *)chatName {
    if (!chatName) return @"Chat name is required";

    WACurrentChat *current = [wa getCurrentChat];
    BOOL needsSwitch = !current || ![current.name.lowercaseString containsString:chatName.lowercaseString];

    if (needsSwitch) {
        if (![wa openChatWithName:chatName]) {
            return [NSString stringWithFormat:@"Could not find chat: %@", chatName];
        }
        [NSThread sleepForTimeInterval:0.5];
    }

    return [self executeGetCurrentChat:wa];
}

- (NSString *)executeSendMessage:(WAAccessibility *)wa message:(NSString *)message {
    if (!message) return @"Message is required";

    WACurrentChat *current = [wa getCurrentChat];
    if (!current) {
        return @"No chat is currently open. Use whatsapp_open_chat first.";
    }

    [wa activateWhatsApp];
    [NSThread sleepForTimeInterval:0.2];

    BOOL success = [wa sendMessage:message];
    if (success) {
        return [NSString stringWithFormat:@"Message sent to %@", current.name];
    } else {
        return @"Failed to send message";
    }
}

- (NSString *)executeSearch:(WAAccessibility *)wa query:(NSString *)query {
    if (!query) return @"Search query is required";

    WASearchResults *results = [wa globalSearch:query];
    if (!results) {
        return @"Search failed";
    }

    NSMutableString *result = [NSMutableString stringWithFormat:@"Search results for '%@':\n", query];

    if (results.chatMatches.count > 0) {
        [result appendString:@"\nChat matches:\n"];
        for (WASearchChatResult *chat in results.chatMatches) {
            [result appendFormat:@"- %@\n", chat.chatName];
        }
    }

    if (results.messageMatches.count > 0) {
        [result appendString:@"\nMessage matches:\n"];
        for (WASearchMessageResult *msg in results.messageMatches) {
            [result appendFormat:@"- %@: %@\n", msg.chatName, msg.messagePreview];
        }
    }

    if (results.chatMatches.count == 0 && results.messageMatches.count == 0) {
        [result appendString:@"No results found"];
    }

    return result;
}

#pragma mark - Local Tool Implementations

- (NSString *)executeShellCommand:(NSString *)command {
    if (!command) return @"Command is required";

    // Basic safety check - block dangerous commands
    NSArray *blockedPatterns = @[@"rm ", @"rm\t", @"rmdir", @"sudo", @"chmod", @"chown",
                                  @"mkfs", @"dd ", @"format", @"> /", @">> /",
                                  @"curl.*|.*sh", @"wget.*|.*sh", @"mv /", @"cp.*/ "];
    NSString *lowerCmd = command.lowercaseString;
    for (NSString *pattern in blockedPatterns) {
        if ([lowerCmd containsString:pattern]) {
            return [NSString stringWithFormat:@"Command blocked for safety: contains '%@'", pattern];
        }
    }

    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/zsh";
    task.arguments = @[@"-c", command];

    NSPipe *outputPipe = [NSPipe pipe];
    NSPipe *errorPipe = [NSPipe pipe];
    task.standardOutput = outputPipe;
    task.standardError = errorPipe;

    @try {
        [task launch];
        [task waitUntilExit];

        NSData *outputData = [[outputPipe fileHandleForReading] readDataToEndOfFile];
        NSData *errorData = [[errorPipe fileHandleForReading] readDataToEndOfFile];

        NSString *output = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
        NSString *errorOutput = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding];

        NSMutableString *result = [NSMutableString string];

        if (output.length > 0) {
            [result appendString:output];
        }
        if (errorOutput.length > 0) {
            if (result.length > 0) [result appendString:@"\n"];
            [result appendFormat:@"stderr: %@", errorOutput];
        }

        if (result.length == 0) {
            result = [NSMutableString stringWithFormat:@"Command completed with exit code %d", task.terminationStatus];
        }

        // Truncate if too long
        if (result.length > 5000) {
            return [NSString stringWithFormat:@"%@\n\n[Output truncated...]", [result substringToIndex:5000]];
        }

        return result;
    } @catch (NSException *exception) {
        return [NSString stringWithFormat:@"Failed to execute command: %@", exception.reason];
    }
}

#pragma mark - GeminiClientDelegate

- (void)geminiClient:(GeminiClient *)client didCompleteSendWithResponse:(GeminiChatResponse *)response {
    NSLog(@"[Gemini] didCompleteSendWithResponse - error: %@, text: %@, functionCalls: %lu",
          response.error ?: @"none",
          response.text ? @"yes" : @"no",
          (unsigned long)response.functionCalls.count);

    if (response.error) {
        [self addErrorMessage:response.error];
        [self setProcessing:NO];
        [self updateStatus:@"Error"];
        return;
    }

    // When toolExecutor is set, GeminiClient handles the tool loop internally.
    // This delegate is called for intermediate responses during the loop.
    if (client.toolExecutor) {
        // Show intermediate text alongside function calls if present
        if (response.text) {
            [self addBotMessage:response.text];
        }
        // Function calls are handled by the toolExecutor, no action needed here
        return;
    }

    // Legacy path: when toolExecutor is not set, handle function calls here
    if (response.hasFunctionCalls) {
        NSLog(@"[Gemini] Processing %lu function calls (legacy path)", (unsigned long)response.functionCalls.count);
        if (response.text) {
            [self addBotMessage:response.text];
        }
        [self handleFunctionCalls:response.functionCalls];
        return;
    }

    // No function calls - show text response and finish
    if (response.text) {
        [self addBotMessage:response.text];
    }
    [self setProcessing:NO];
    [self updateStatus:@"Ready"];
}

- (void)geminiClient:(GeminiClient *)client didCompleteToolLoopWithResponse:(GeminiChatResponse *)response {
    NSLog(@"[Gemini] didCompleteToolLoopWithResponse - error: %@, text: %@",
          response.error ?: @"none",
          response.text ? @"yes" : @"no");

    if (response.error) {
        [self addErrorMessage:response.error];
        [self setProcessing:NO];
        [self updateStatus:@"Error"];
        return;
    }

    // Tool loop completed - show final text response
    if (response.text) {
        [self addBotMessage:response.text];
    }
    [self setProcessing:NO];
    [self updateStatus:@"Ready"];
}

- (void)geminiClient:(GeminiClient *)client didFailWithError:(NSError *)error {
    [self addErrorMessage:error.localizedDescription];
    [self setProcessing:NO];
    [self updateStatus:@"Error"];
}

- (void)handleFunctionCalls:(NSArray<GeminiFunctionCall *> *)calls {
    if (calls.count == 0) return;

    // Process function calls sequentially
    [self processFunctionCallAtIndex:0 calls:calls];
}

- (void)processFunctionCallAtIndex:(NSUInteger)index calls:(NSArray<GeminiFunctionCall *> *)calls {
    if (index >= calls.count) {
        NSLog(@"[Gemini] All function calls processed");
        return;
    }

    GeminiFunctionCall *call = calls[index];
    NSLog(@"[Gemini] Processing function call %lu/%lu: %@", (unsigned long)(index + 1), (unsigned long)calls.count, call.name);
    [self updateStatus:[NSString stringWithFormat:@"Calling %@...", call.name]];

    [self executeMCPTool:call.name args:call.args completion:^(NSString *result) {
        NSLog(@"[Gemini] Function %@ returned, sending result to Gemini", call.name);

        // Show function result in chat only if debug mode is enabled
        if ([DebugConfigWindowController showDebugInChatEnabled]) {
            [self addFunctionMessage:call.name result:result];
        }

        // Send result back to Gemini
        [self.geminiClient sendFunctionResult:call.name result:result];
        NSLog(@"[Gemini] sendFunctionResult called for %@", call.name);
    }];
}

#pragma mark - NSTextViewDelegate

- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    if (commandSelector == @selector(insertNewline:)) {
        // Shift+Enter or Option+Enter inserts a newline, plain Enter sends
        NSEvent *event = [NSApp currentEvent];
        if (event.modifierFlags & (NSEventModifierFlagShift | NSEventModifierFlagOption)) {
            return NO; // Let the text view handle it (insert newline)
        }
        [self sendMessage:nil];
        return YES;
    }
    return NO;
}

- (void)textDidChange:(NSNotification *)notification {
    [self updatePlaceholder];
    [self updateInputHeight];
}

- (void)updatePlaceholder {
    // Show/hide placeholder based on text content
    self.placeholderLabel.hidden = (self.inputTextView.string.length > 0);
}

- (void)updateInputHeight {
    // Calculate required height for the text
    NSLayoutManager *layoutManager = self.inputTextView.layoutManager;
    NSTextContainer *textContainer = self.inputTextView.textContainer;

    [layoutManager ensureLayoutForTextContainer:textContainer];
    NSRect usedRect = [layoutManager usedRectForTextContainer:textContainer];

    // Account for text container insets
    CGFloat textHeight = ceil(usedRect.size.height) + self.inputTextView.textContainerInset.height * 2;

    // Minimum height of one line (~28), maximum of ~150 (about 6 lines)
    CGFloat minTextHeight = 28;
    CGFloat maxTextHeight = 150;
    CGFloat clampedTextHeight = MAX(minTextHeight, MIN(maxTextHeight, textHeight));

    // Calculate total input container height (text area + bottom row for status/model)
    CGFloat bottomRowHeight = 30; // status label + padding
    CGFloat padding = 20; // top and bottom padding
    CGFloat newContainerHeight = clampedTextHeight + bottomRowHeight + padding;

    // Only animate if height changed
    if (fabs(self.inputContainerHeightConstraint.constant - newContainerHeight) > 1) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.15;
            context.allowsImplicitAnimation = YES;
            self.inputContainerHeightConstraint.constant = newContainerHeight;
            [self.window layoutIfNeeded];
        } completionHandler:nil];
    }
}

@end
