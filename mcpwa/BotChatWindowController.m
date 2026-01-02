//
//  BotChatWindowController.m
//  mcpwa
//
//  Bot Chat Window - Gemini-powered chat with WhatsApp MCP integration
//

#import "BotChatWindowController.h"
#import "WAAccessibility.h"

// Chat bubble colors
#define kUserBubbleColor [NSColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0]
#define kBotBubbleColor [NSColor colorWithWhite:0.25 alpha:1.0]
#define kFunctionBubbleColor [NSColor colorWithRed:0.4 green:0.3 blue:0.6 alpha:1.0]
#define kBackgroundColor [NSColor colorWithWhite:0.12 alpha:1.0]
#define kInputBackgroundColor [NSColor colorWithWhite:0.18 alpha:1.0]

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

@interface BotChatWindowController () <NSPopoverDelegate>
@property (nonatomic, strong) GeminiClient *geminiClient;
@property (nonatomic, strong) NSMutableArray<ChatDisplayMessage *> *messages;
@property (nonatomic, strong) NSScrollView *chatScrollView;
@property (nonatomic, strong) NSStackView *chatStackView;
@property (nonatomic, strong) NSTextField *inputField;
@property (nonatomic, strong) NSButton *sendButton;
@property (nonatomic, strong) NSButton *stopButton;
@property (nonatomic, strong) NSButton *settingsButton;
@property (nonatomic, strong) NSProgressIndicator *loadingIndicator;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, assign) BOOL isProcessing;
@property (nonatomic, assign) BOOL isCancelled;
@property (nonatomic, strong) NSArray<NSDictionary *> *mcpTools;
@property (nonatomic, assign) BOOL showDebugInfo;
@property (nonatomic, strong) NSPopover *settingsPopover;
@property (nonatomic, strong) NSPopUpButton *modelSelector;
@property (nonatomic, strong) NSButton *debugToggle;
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
        _showDebugInfo = [[NSUserDefaults standardUserDefaults] boolForKey:@"GeminiShowDebugInfo"];
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
                              NSWindowStyleMaskResizable;

    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:style
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"WhatsApp Bot Chat";
    window.minSize = NSMakeSize(400, 400);
    window.backgroundColor = kBackgroundColor;
    [window center];

    // Main window - normal level (not floating)
    window.level = NSNormalWindowLevel;

    self.window = window;

    // Setup content
    [self setupContentView];
}

- (void)setupContentView {
    NSView *contentView = self.window.contentView;
    contentView.wantsLayer = YES;
    contentView.layer.backgroundColor = kBackgroundColor.CGColor;

    // Chat scroll view (takes most of the space)
    self.chatScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    self.chatScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.chatScrollView.hasVerticalScroller = YES;
    self.chatScrollView.hasHorizontalScroller = NO;
    self.chatScrollView.autohidesScrollers = YES;
    self.chatScrollView.borderType = NSNoBorder;
    self.chatScrollView.backgroundColor = kBackgroundColor;
    self.chatScrollView.drawsBackground = YES;

    // Stack view for chat messages
    self.chatStackView = [[NSStackView alloc] initWithFrame:NSZeroRect];
    self.chatStackView.translatesAutoresizingMaskIntoConstraints = NO;
    self.chatStackView.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.chatStackView.alignment = NSLayoutAttributeLeading;
    self.chatStackView.spacing = 8;
    self.chatStackView.edgeInsets = NSEdgeInsetsMake(10, 10, 10, 10);

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
    inputContainer.layer.backgroundColor = kInputBackgroundColor.CGColor;
    [contentView addSubview:inputContainer];

    // Input field
    self.inputField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.inputField.translatesAutoresizingMaskIntoConstraints = NO;
    self.inputField.placeholderString = @"Type a message...";
    self.inputField.font = [NSFont systemFontOfSize:14];
    self.inputField.bezeled = YES;
    self.inputField.bezelStyle = NSTextFieldRoundedBezel;
    self.inputField.delegate = self;
    self.inputField.focusRingType = NSFocusRingTypeNone;
    [inputContainer addSubview:self.inputField];

    // Send button (arrow up icon)
    NSImage *sendImage = [NSImage imageWithSystemSymbolName:@"arrow.up" accessibilityDescription:@"Send"];
    NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:14 weight:NSFontWeightBold];
    sendImage = [sendImage imageWithSymbolConfiguration:config];
    self.sendButton = [NSButton buttonWithImage:sendImage target:self action:@selector(sendMessage:)];
    self.sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.sendButton.bezelStyle = NSBezelStyleCircular;
    self.sendButton.bordered = NO;
    self.sendButton.keyEquivalent = @"\r"; // Enter key
    self.sendButton.wantsLayer = YES;
    self.sendButton.layer.backgroundColor = [NSColor colorWithRed:0.0 green:0.4 blue:0.8 alpha:1.0].CGColor;
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
    self.stopButton.layer.backgroundColor = [NSColor colorWithRed:0.0 green:0.4 blue:0.8 alpha:1.0].CGColor;
    self.stopButton.layer.cornerRadius = 14;
    self.stopButton.contentTintColor = [NSColor whiteColor];
    [inputContainer addSubview:self.stopButton];

    // Settings button (gear icon)
    self.settingsButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"gearshape" accessibilityDescription:@"Settings"]
                                             target:self
                                             action:@selector(showSettings:)];
    self.settingsButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.settingsButton.bezelStyle = NSBezelStyleRounded;
    self.settingsButton.bordered = NO;
    self.settingsButton.contentTintColor = [NSColor colorWithWhite:0.6 alpha:1.0];
    [inputContainer addSubview:self.settingsButton];

    // Loading indicator
    self.loadingIndicator = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    self.loadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.loadingIndicator.style = NSProgressIndicatorStyleSpinning;
    self.loadingIndicator.controlSize = NSControlSizeRegular;
    self.loadingIndicator.displayedWhenStopped = NO;
    self.loadingIndicator.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantLight];
    [inputContainer addSubview:self.loadingIndicator];

    // Status label
    self.statusLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.stringValue = @"";
    self.statusLabel.font = [NSFont systemFontOfSize:11];
    self.statusLabel.textColor = [NSColor colorWithWhite:0.6 alpha:1.0];
    self.statusLabel.bezeled = NO;
    self.statusLabel.editable = NO;
    self.statusLabel.selectable = NO;
    self.statusLabel.backgroundColor = [NSColor clearColor];
    [inputContainer addSubview:self.statusLabel];

    // Layout constraints
    NSDictionary *views = @{
        @"chat": self.chatScrollView,
        @"input": inputContainer,
        @"field": self.inputField,
        @"send": self.sendButton,
        @"stop": self.stopButton,
        @"settings": self.settingsButton,
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
    [NSLayoutConstraint activateConstraints:
     [NSLayoutConstraint constraintsWithVisualFormat:@"V:|[chat][input(==80)]|"
                                             options:0 metrics:nil views:views]];

    // Input container layout
    [NSLayoutConstraint activateConstraints:
     [NSLayoutConstraint constraintsWithVisualFormat:@"H:|-10-[field]-8-[loading(20)]-8-[send(28)]-8-[settings(24)]-10-|"
                                             options:NSLayoutFormatAlignAllCenterY
                                             metrics:nil views:views]];
    // Send and stop button size (circular)
    [NSLayoutConstraint activateConstraints:@[
        [self.sendButton.heightAnchor constraintEqualToConstant:28],
        [self.stopButton.widthAnchor constraintEqualToConstant:28],
        [self.stopButton.heightAnchor constraintEqualToConstant:28]
    ]];
    // Stop button overlays the send button position
    [NSLayoutConstraint activateConstraints:@[
        [self.stopButton.centerXAnchor constraintEqualToAnchor:self.sendButton.centerXAnchor],
        [self.stopButton.centerYAnchor constraintEqualToAnchor:self.sendButton.centerYAnchor]
    ]];
    [NSLayoutConstraint activateConstraints:@[
        [self.settingsButton.heightAnchor constraintEqualToConstant:24]
    ]];
    [NSLayoutConstraint activateConstraints:
     [NSLayoutConstraint constraintsWithVisualFormat:@"H:|-10-[status]-10-|"
                                             options:0 metrics:nil views:views]];
    [NSLayoutConstraint activateConstraints:
     [NSLayoutConstraint constraintsWithVisualFormat:@"V:|-10-[field(28)]-4-[status]-10-|"
                                             options:0 metrics:nil views:views]];
    [NSLayoutConstraint activateConstraints:@[
        [self.loadingIndicator.heightAnchor constraintEqualToConstant:20],
        [self.loadingIndicator.widthAnchor constraintEqualToConstant:20]
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
        self.inputField.enabled = NO;
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
            if (strongSelf.showDebugInfo) {
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
    [self.window makeFirstResponder:self.inputField];
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

#pragma mark - Settings

- (void)showSettings:(id)sender {
    if (self.settingsPopover.isShown) {
        [self.settingsPopover close];
        return;
    }

    // Create popover if needed
    if (!self.settingsPopover) {
        self.settingsPopover = [[NSPopover alloc] init];
        self.settingsPopover.behavior = NSPopoverBehaviorTransient;
        self.settingsPopover.delegate = self;
    }

    // Create settings view
    NSView *settingsView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 250, 100)];

    // Model selection label
    NSTextField *modelLabel = [NSTextField labelWithString:@"Model:"];
    modelLabel.translatesAutoresizingMaskIntoConstraints = NO;
    modelLabel.font = [NSFont systemFontOfSize:12];
    [settingsView addSubview:modelLabel];

    // Model popup button
    self.modelSelector = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.modelSelector.translatesAutoresizingMaskIntoConstraints = NO;
    self.modelSelector.target = self;
    self.modelSelector.action = @selector(modelChanged:);

    // Populate models
    [self.modelSelector removeAllItems];
    for (NSString *modelId in [GeminiClient availableModels]) {
        NSString *displayName = [GeminiClient displayNameForModel:modelId];
        [self.modelSelector addItemWithTitle:displayName];
        self.modelSelector.lastItem.representedObject = modelId;

        // Select current model
        if ([modelId isEqualToString:self.geminiClient.model]) {
            [self.modelSelector selectItem:self.modelSelector.lastItem];
        }
    }
    [settingsView addSubview:self.modelSelector];

    // Debug toggle label
    NSTextField *debugLabel = [NSTextField labelWithString:@"Show debug info:"];
    debugLabel.translatesAutoresizingMaskIntoConstraints = NO;
    debugLabel.font = [NSFont systemFontOfSize:12];
    [settingsView addSubview:debugLabel];

    // Debug toggle switch
    self.debugToggle = [NSButton checkboxWithTitle:@"" target:self action:@selector(debugToggled:)];
    self.debugToggle.translatesAutoresizingMaskIntoConstraints = NO;
    self.debugToggle.state = self.showDebugInfo ? NSControlStateValueOn : NSControlStateValueOff;
    [settingsView addSubview:self.debugToggle];

    // Layout
    [NSLayoutConstraint activateConstraints:@[
        [modelLabel.leadingAnchor constraintEqualToAnchor:settingsView.leadingAnchor constant:15],
        [modelLabel.topAnchor constraintEqualToAnchor:settingsView.topAnchor constant:15],

        [self.modelSelector.leadingAnchor constraintEqualToAnchor:modelLabel.trailingAnchor constant:10],
        [self.modelSelector.trailingAnchor constraintEqualToAnchor:settingsView.trailingAnchor constant:-15],
        [self.modelSelector.centerYAnchor constraintEqualToAnchor:modelLabel.centerYAnchor],

        [debugLabel.leadingAnchor constraintEqualToAnchor:settingsView.leadingAnchor constant:15],
        [debugLabel.topAnchor constraintEqualToAnchor:modelLabel.bottomAnchor constant:20],

        [self.debugToggle.leadingAnchor constraintEqualToAnchor:debugLabel.trailingAnchor constant:10],
        [self.debugToggle.centerYAnchor constraintEqualToAnchor:debugLabel.centerYAnchor]
    ]];

    // Create view controller for popover
    NSViewController *vc = [[NSViewController alloc] init];
    vc.view = settingsView;
    self.settingsPopover.contentViewController = vc;

    // Show popover
    [self.settingsPopover showRelativeToRect:self.settingsButton.bounds
                                      ofView:self.settingsButton
                               preferredEdge:NSRectEdgeMaxY];
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

- (void)debugToggled:(NSButton *)sender {
    self.showDebugInfo = (sender.state == NSControlStateValueOn);
    [[NSUserDefaults standardUserDefaults] setBool:self.showDebugInfo forKey:@"GeminiShowDebugInfo"];

    NSString *status = self.showDebugInfo ? @"Debug info enabled" : @"Debug info disabled";
    [self updateStatus:status];
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

    NSFont *regularFont = [NSFont systemFontOfSize:13];
    NSFont *boldFont = [NSFont boldSystemFontOfSize:13];
    NSFont *italicFont = [NSFont fontWithDescriptor:[[regularFont fontDescriptor] fontDescriptorWithSymbolicTraits:NSFontDescriptorTraitItalic] size:13];
    if (!italicFont) italicFont = regularFont;
    NSFont *h3Font = [NSFont boldSystemFontOfSize:15];
    NSFont *h2Font = [NSFont boldSystemFontOfSize:17];
    NSFont *h1Font = [NSFont boldSystemFontOfSize:19];

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
            NSUInteger start = i;
            while (i < len && [line characterAtIndex:i] != '*') {
                i++;
            }
            NSString *regularText = [line substringWithRange:NSMakeRange(start, i - start)];
            NSAttributedString *regularAttr = [[NSAttributedString alloc] initWithString:regularText attributes:@{
                NSFontAttributeName: lineFont,
                NSForegroundColorAttributeName: textColor
            }];
            [lineAttr appendAttributedString:regularAttr];
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
    bubble.layer.cornerRadius = 12;

    // Style based on message type
    NSColor *bubbleColor;
    NSColor *textColor = [NSColor whiteColor];
    BOOL alignRight = NO;
    BOOL useMarkdown = NO;
    NSString *displayText = message.text;

    switch (message.type) {
        case ChatMessageTypeUser:
            bubbleColor = kUserBubbleColor;
            alignRight = YES;
            break;
        case ChatMessageTypeBot:
            bubbleColor = kBotBubbleColor;
            useMarkdown = YES;
            break;
        case ChatMessageTypeFunction:
            bubbleColor = kFunctionBubbleColor;
            if (message.functionName) {
                displayText = [NSString stringWithFormat:@"[%@]\n%@", message.functionName, message.text];
            }
            break;
        case ChatMessageTypeError:
            bubbleColor = [NSColor systemRedColor];
            break;
        case ChatMessageTypeSystem:
            bubbleColor = [NSColor colorWithWhite:0.3 alpha:1.0];
            textColor = [NSColor secondaryLabelColor];
            break;
    }

    // Create text view for selectable text with proper background handling
    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 326, 20)];
    textView.translatesAutoresizingMaskIntoConstraints = NO;
    textView.editable = NO;
    textView.selectable = YES;
    textView.backgroundColor = [NSColor clearColor];
    textView.drawsBackground = NO;
    textView.textContainerInset = NSZeroSize;
    textView.textContainer.lineFragmentPadding = 0;
    textView.textContainer.widthTracksTextView = NO;
    textView.textContainer.containerSize = NSMakeSize(326, CGFLOAT_MAX);
    textView.verticallyResizable = YES;
    textView.horizontallyResizable = NO;

    if (useMarkdown) {
        [textView.textStorage setAttributedString:[self attributedStringFromMarkdown:displayText textColor:textColor]];
    } else {
        NSFont *font = (message.type == ChatMessageTypeFunction) ?
            [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular] :
            [NSFont systemFontOfSize:13];
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

    // Constraints for text view in bubble - use fixed height based on content
    [NSLayoutConstraint activateConstraints:@[
        [textView.leadingAnchor constraintEqualToAnchor:bubble.leadingAnchor constant:12],
        [textView.trailingAnchor constraintEqualToAnchor:bubble.trailingAnchor constant:-12],
        [textView.topAnchor constraintEqualToAnchor:bubble.topAnchor constant:8],
        [textView.bottomAnchor constraintEqualToAnchor:bubble.bottomAnchor constant:-8],
        [textView.widthAnchor constraintLessThanOrEqualToConstant:326],
        [textView.heightAnchor constraintEqualToConstant:textHeight]
    ]];

    // Constraints for bubble in container
    CGFloat maxWidth = 350;
    if (alignRight) {
        [NSLayoutConstraint activateConstraints:@[
            [bubble.trailingAnchor constraintEqualToAnchor:bubbleContainer.trailingAnchor],
            [bubble.leadingAnchor constraintGreaterThanOrEqualToAnchor:bubbleContainer.leadingAnchor],
            [bubble.widthAnchor constraintLessThanOrEqualToConstant:maxWidth]
        ]];
    } else {
        [NSLayoutConstraint activateConstraints:@[
            [bubble.leadingAnchor constraintEqualToAnchor:bubbleContainer.leadingAnchor],
            [bubble.trailingAnchor constraintLessThanOrEqualToAnchor:bubbleContainer.trailingAnchor],
            [bubble.widthAnchor constraintLessThanOrEqualToConstant:maxWidth]
        ]];
    }

    [NSLayoutConstraint activateConstraints:@[
        [bubble.topAnchor constraintEqualToAnchor:bubbleContainer.topAnchor],
        [bubble.bottomAnchor constraintEqualToAnchor:bubbleContainer.bottomAnchor]
    ]];

    // Add to stack view first, then set width constraint (views must be in same hierarchy)
    [self.chatStackView addArrangedSubview:bubbleContainer];

    // Now that bubbleContainer is in the hierarchy, we can constrain to stack view width
    [bubbleContainer.widthAnchor constraintEqualToAnchor:self.chatStackView.widthAnchor constant:-20].active = YES;

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
    self.inputField.enabled = !processing;

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
    NSString *text = self.inputField.stringValue;
    if (text.length == 0 || self.isProcessing) return;

    self.isCancelled = NO;
    self.inputField.stringValue = @"";
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
    NSLog(@"[MCP] Starting tool: %@", name);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Check cancellation at start of background task
        if (self.isCancelled) {
            NSLog(@"[MCP] Tool %@ cancelled before execution", name);
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
            NSLog(@"[MCP] Tool %@ exception: %@", name, exception.reason);
        }

        NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:startTime];
        NSLog(@"[MCP] Tool %@ completed in %.2fs, result length: %lu", name, elapsed, (unsigned long)result.length);

        // Only call completion if not cancelled
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!self.isCancelled) {
                NSLog(@"[MCP] Calling completion for %@", name);
                completion(result);
                NSLog(@"[MCP] Completion called for %@", name);
            } else {
                NSLog(@"[MCP] Tool %@ cancelled, skipping completion", name);
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
        if (self.showDebugInfo) {
            [self addFunctionMessage:call.name result:result];
        }

        // Send result back to Gemini
        [self.geminiClient sendFunctionResult:call.name result:result];
        NSLog(@"[Gemini] sendFunctionResult called for %@", call.name);
    }];
}

#pragma mark - NSTextFieldDelegate

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    if (commandSelector == @selector(insertNewline:)) {
        [self sendMessage:nil];
        return YES;
    }
    return NO;
}

@end
