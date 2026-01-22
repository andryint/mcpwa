//
//  BotChatWindowController+ModeManagement.h
//  mcpwa
//
//  Chat mode management: MCP/RAG mode switching, Gemini/RAG client setup, model selection
//

#import "BotChatWindowController.h"

NS_ASSUME_NONNULL_BEGIN

@interface BotChatWindowController (ModeManagement)

#pragma mark - Mode Change Handling

/// Handle chat mode change notification
- (void)chatModeDidChange:(NSNotification *)notification;

#pragma mark - Client Setup

/// Initialize the Gemini client with API key and tool executor
- (void)setupGeminiClient;

/// Initialize the RAG client with service URL
- (void)setupRAGClient;

/// Load MCP tool definitions for WhatsApp integration
- (void)loadMCPTools;

#pragma mark - Model Selection

/// Populate the Gemini model selector dropdown
- (void)populateModelSelector;

/// Select a specific model in the selector
- (void)selectModelInSelector:(NSString *)modelId;

/// Handle Gemini model selection change
- (void)modelChanged:(NSPopUpButton *)sender;

/// Populate the RAG model selector dropdown
- (void)populateRAGModelSelector;

/// Handle RAG model selection change
- (void)ragModelChanged:(NSPopUpButton *)sender;

#pragma mark - Title Generation

/// Generate a title for the chat window based on the first user message
- (void)generateTitleIfNeeded;

@end

NS_ASSUME_NONNULL_END
