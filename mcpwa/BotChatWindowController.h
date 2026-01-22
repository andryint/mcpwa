//
//  BotChatWindowController.h
//  mcpwa
//
//  Bot Chat Window - Gemini-powered chat with WhatsApp MCP integration
//  Supports both MCP mode (WhatsApp) and RAG mode (Knowledge Base)
//

#import <Cocoa/Cocoa.h>
#import "GeminiClient.h"
#import "RAGClient.h"
#import "SettingsWindowController.h"

NS_ASSUME_NONNULL_BEGIN

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

@interface BotChatWindowController : NSWindowController <GeminiClientDelegate, RAGClientDelegate, NSTextFieldDelegate>

/// Shared instance (singleton pattern for easy access)
+ (instancetype)sharedController;

/// Show the bot chat window
- (void)showWindow;

/// Hide the bot chat window
- (void)hideWindow;

/// Toggle window visibility
- (void)toggleWindow;

/// Check if window is currently visible
@property (nonatomic, readonly) BOOL isVisible;

/// Zoom actions (responds to View menu items)
- (IBAction)zoomIn:(id)sender;
- (IBAction)zoomOut:(id)sender;
- (IBAction)zoomToActualSize:(id)sender;

#pragma mark - Properties for Category Access

// API Clients
@property (nonatomic, strong) GeminiClient *geminiClient;
@property (nonatomic, strong) RAGClient *ragClient;

// Messages
@property (nonatomic, strong) NSMutableArray<ChatDisplayMessage *> *messages;

// UI Components - Title Bar
@property (nonatomic, strong) NSView *titleBarView;
@property (nonatomic, strong) NSTextField *titleLabel;

// UI Components - Chat Area
@property (nonatomic, strong) NSScrollView *chatScrollView;
@property (nonatomic, strong) NSStackView *chatStackView;

// UI Components - Input Area
@property (nonatomic, strong) NSScrollView *inputScrollView;
@property (nonatomic, strong) NSTextView *inputTextView;
@property (nonatomic, strong) NSTextField *placeholderLabel;
@property (nonatomic, strong) NSLayoutConstraint *inputContainerHeightConstraint;
@property (nonatomic, strong) NSView *inputContainer;
@property (nonatomic, strong) NSButton *sendButton;
@property (nonatomic, strong) NSButton *stopButton;

// UI Components - Status Bar
@property (nonatomic, strong) NSProgressIndicator *loadingIndicator;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextField *modeIndicator;
@property (nonatomic, strong) NSPopUpButton *modelSelector;
@property (nonatomic, strong) NSPopUpButton *ragModelSelector;
@property (nonatomic, strong) NSArray<RAGModelItem *> *ragModels;
@property (nonatomic, copy, nullable) NSString *selectedRAGModelId;

// State
@property (nonatomic, assign) BOOL isProcessing;
@property (nonatomic, assign) BOOL isCancelled;
@property (nonatomic, assign) BOOL hasTitleBeenGenerated;
@property (nonatomic, copy, nullable) NSString *firstUserMessage;
@property (nonatomic, assign) WAChatMode currentChatMode;
@property (nonatomic, assign) CGFloat currentFontSize;

// MCP Tools
@property (nonatomic, strong, nullable) NSArray<NSDictionary *> *mcpTools;

// Streaming Support
@property (nonatomic, strong, nullable) NSMutableString *streamingResponse;
@property (nonatomic, strong, nullable) NSTextView *streamingTextView;
@property (nonatomic, strong, nullable) NSView *streamingBubbleView;
@property (nonatomic, assign) CGFloat streamingMaxWidth;

// Scroll Management
@property (nonatomic, strong, nullable) NSView *bottomSpacerView;
@property (nonatomic, strong, nullable) NSLayoutConstraint *bottomSpacerHeightConstraint;
@property (nonatomic, weak, nullable) NSView *lastUserBubble;
@property (nonatomic, assign) CGFloat lastResponseBubbleHeight;

#pragma mark - Internal Methods for Category Access

/// Add a message bubble to the chat (used by MessageRendering and ThemeHandling)
- (void)addMessageBubble:(ChatDisplayMessage *)message;

/// Create attributed string from markdown (used by MessageRendering and StreamingSupport)
- (NSAttributedString *)attributedStringFromMarkdown:(NSString *)markdown textColor:(NSColor *)textColor;

/// Update input text view height based on content
- (void)updateInputHeight;

/// Scroll chat to bottom
- (void)scrollToBottom;

/// Update status label text
- (void)updateStatus:(NSString *)status;

/// Set processing state (show/hide loading indicator, enable/disable input)
- (void)setProcessing:(BOOL)processing;

@end

NS_ASSUME_NONNULL_END
