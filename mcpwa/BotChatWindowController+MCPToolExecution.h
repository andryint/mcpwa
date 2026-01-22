//
//  BotChatWindowController+MCPToolExecution.h
//  mcpwa
//
//  WhatsApp MCP tool execution
//

#import "BotChatWindowController.h"
#import "WAAccessibility.h"

NS_ASSUME_NONNULL_BEGIN

@interface BotChatWindowController (MCPToolExecution)

/// Execute an MCP tool with the given name and arguments
- (void)executeMCPTool:(NSString *)name args:(NSDictionary *)args completion:(void(^)(NSString *result))completion;

/// Start WhatsApp session
- (NSString *)executeStartSession:(WAAccessibility *)wa;

/// Stop WhatsApp session
- (NSString *)executeStopSession:(WAAccessibility *)wa;

/// Get WhatsApp status
- (NSString *)executeStatus:(WAAccessibility *)wa;

/// List chats with optional filter
- (NSString *)executeListChats:(WAAccessibility *)wa filter:(nullable NSString *)filterString;

/// Get current chat info
- (NSString *)executeGetCurrentChat:(WAAccessibility *)wa;

/// Open a chat by name
- (NSString *)executeOpenChat:(WAAccessibility *)wa name:(NSString *)name;

/// Get messages from a chat
- (NSString *)executeGetMessages:(WAAccessibility *)wa chatName:(NSString *)chatName;

/// Send a message
- (NSString *)executeSendMessage:(WAAccessibility *)wa message:(NSString *)message;

/// Search chats/messages
- (NSString *)executeSearch:(WAAccessibility *)wa query:(NSString *)query;

/// Execute a shell command (with safety checks)
- (NSString *)executeShellCommand:(NSString *)command;

/// Get user-friendly status message for tool execution
- (NSString *)friendlyStatusForTool:(NSString *)toolName;

@end

NS_ASSUME_NONNULL_END
