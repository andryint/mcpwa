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

@interface BotChatWindowController ()
@property (nonatomic, strong) GeminiClient *geminiClient;
@property (nonatomic, strong) NSMutableArray<ChatDisplayMessage *> *messages;
@property (nonatomic, strong) NSScrollView *chatScrollView;
@property (nonatomic, strong) NSStackView *chatStackView;
@property (nonatomic, strong) NSTextField *inputField;
@property (nonatomic, strong) NSButton *sendButton;
@property (nonatomic, strong) NSProgressIndicator *loadingIndicator;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, assign) BOOL isProcessing;
@property (nonatomic, strong) NSArray<NSDictionary *> *mcpTools;
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
                              NSWindowStyleMaskResizable;

    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:style
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"WhatsApp Bot Chat";
    window.minSize = NSMakeSize(400, 400);
    window.backgroundColor = kBackgroundColor;
    [window center];

    // Make window floating (stays on top)
    window.level = NSFloatingWindowLevel;

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

    // Send button
    self.sendButton = [NSButton buttonWithTitle:@"Send" target:self action:@selector(sendMessage:)];
    self.sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.sendButton.bezelStyle = NSBezelStyleRounded;
    self.sendButton.keyEquivalent = @"\r"; // Enter key
    [inputContainer addSubview:self.sendButton];

    // Loading indicator
    self.loadingIndicator = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    self.loadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.loadingIndicator.style = NSProgressIndicatorStyleSpinning;
    self.loadingIndicator.controlSize = NSControlSizeSmall;
    self.loadingIndicator.hidden = YES;
    [inputContainer addSubview:self.loadingIndicator];

    // Status label
    self.statusLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.stringValue = @"";
    self.statusLabel.font = [NSFont systemFontOfSize:11];
    self.statusLabel.textColor = [NSColor secondaryLabelColor];
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
     [NSLayoutConstraint constraintsWithVisualFormat:@"H:|-10-[field]-8-[loading(16)]-8-[send]-10-|"
                                             options:NSLayoutFormatAlignAllCenterY
                                             metrics:nil views:views]];
    [NSLayoutConstraint activateConstraints:
     [NSLayoutConstraint constraintsWithVisualFormat:@"H:|-10-[status]-10-|"
                                             options:0 metrics:nil views:views]];
    [NSLayoutConstraint activateConstraints:
     [NSLayoutConstraint constraintsWithVisualFormat:@"V:|-10-[field(28)]-4-[status]-10-|"
                                             options:0 metrics:nil views:views]];
    [NSLayoutConstraint activateConstraints:@[
        [self.loadingIndicator.heightAnchor constraintEqualToConstant:16]
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
    [self addSystemMessage:@"Welcome! I'm your WhatsApp assistant powered by Gemini. "
                           "I can help you read messages, search chats, and send messages through WhatsApp."];
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

    [self updateStatus:@"Ready"];
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

- (void)addMessageBubble:(ChatDisplayMessage *)message {
    NSView *bubbleContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    bubbleContainer.translatesAutoresizingMaskIntoConstraints = NO;

    // Create bubble background
    NSView *bubble = [[NSView alloc] initWithFrame:NSZeroRect];
    bubble.translatesAutoresizingMaskIntoConstraints = NO;
    bubble.wantsLayer = YES;
    bubble.layer.cornerRadius = 12;

    // Create text field
    NSTextField *textField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    textField.translatesAutoresizingMaskIntoConstraints = NO;
    textField.stringValue = message.text;
    textField.font = [NSFont systemFontOfSize:13];
    textField.bezeled = NO;
    textField.editable = NO;
    textField.selectable = YES;
    textField.backgroundColor = [NSColor clearColor];
    textField.lineBreakMode = NSLineBreakByWordWrapping;
    textField.maximumNumberOfLines = 0;
    textField.preferredMaxLayoutWidth = 350;

    // Style based on message type
    NSColor *bubbleColor;
    NSColor *textColor = [NSColor whiteColor];
    BOOL alignRight = NO;

    switch (message.type) {
        case ChatMessageTypeUser:
            bubbleColor = kUserBubbleColor;
            alignRight = YES;
            break;
        case ChatMessageTypeBot:
            bubbleColor = kBotBubbleColor;
            break;
        case ChatMessageTypeFunction:
            bubbleColor = kFunctionBubbleColor;
            textField.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
            if (message.functionName) {
                textField.stringValue = [NSString stringWithFormat:@"[%@]\n%@", message.functionName, message.text];
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

    bubble.layer.backgroundColor = bubbleColor.CGColor;
    textField.textColor = textColor;

    [bubble addSubview:textField];
    [bubbleContainer addSubview:bubble];

    // Constraints for text in bubble
    [NSLayoutConstraint activateConstraints:@[
        [textField.leadingAnchor constraintEqualToAnchor:bubble.leadingAnchor constant:12],
        [textField.trailingAnchor constraintEqualToAnchor:bubble.trailingAnchor constant:-12],
        [textField.topAnchor constraintEqualToAnchor:bubble.topAnchor constant:8],
        [textField.bottomAnchor constraintEqualToAnchor:bubble.bottomAnchor constant:-8]
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
        [bubble.bottomAnchor constraintEqualToAnchor:bubbleContainer.bottomAnchor],
        [bubbleContainer.widthAnchor constraintEqualToAnchor:self.chatStackView.widthAnchor constant:-20]
    ]];

    [self.chatStackView addArrangedSubview:bubbleContainer];

    // Scroll to bottom
    dispatch_async(dispatch_get_main_queue(), ^{
        NSPoint newScrollOrigin = NSMakePoint(0.0, NSMaxY(self.chatScrollView.documentView.frame));
        [self.chatScrollView.documentView scrollPoint:newScrollOrigin];
    });
}

- (void)updateStatus:(NSString *)status {
    self.statusLabel.stringValue = status;
}

- (void)setProcessing:(BOOL)processing {
    self.isProcessing = processing;
    self.inputField.enabled = !processing;
    self.sendButton.enabled = !processing;
    self.loadingIndicator.hidden = !processing;

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

    self.inputField.stringValue = @"";
    [self addUserMessage:text];
    [self setProcessing:YES];
    [self updateStatus:@"Thinking..."];

    [self.geminiClient sendMessage:text];
}

#pragma mark - MCP Tool Execution

- (void)executeMCPTool:(NSString *)name args:(NSDictionary *)args completion:(void(^)(NSString *result))completion {
    WAAccessibility *wa = [WAAccessibility shared];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *result = nil;

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
            else {
                result = [NSString stringWithFormat:@"Unknown tool: %@", name];
            }
        } @catch (NSException *exception) {
            result = [NSString stringWithFormat:@"Error: %@", exception.reason];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(result);
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

#pragma mark - GeminiClientDelegate

- (void)geminiClient:(GeminiClient *)client didCompleteSendWithResponse:(GeminiChatResponse *)response {
    if (response.error) {
        [self addErrorMessage:response.error];
        [self setProcessing:NO];
        [self updateStatus:@"Error"];
        return;
    }

    // If there's a text response, show it
    if (response.text && !response.hasFunctionCalls) {
        [self addBotMessage:response.text];
        [self setProcessing:NO];
        [self updateStatus:@"Ready"];
    }

    // Handle function calls
    if (response.hasFunctionCalls) {
        [self handleFunctionCalls:response.functionCalls];
    }
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
        return;
    }

    GeminiFunctionCall *call = calls[index];
    [self updateStatus:[NSString stringWithFormat:@"Calling %@...", call.name]];

    [self executeMCPTool:call.name args:call.args completion:^(NSString *result) {
        // Show function result in chat
        [self addFunctionMessage:call.name result:result];

        // Send result back to Gemini
        [self.geminiClient sendFunctionResult:call.name result:result];
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
