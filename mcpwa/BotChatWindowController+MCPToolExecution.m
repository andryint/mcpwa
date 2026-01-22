//
//  BotChatWindowController+MCPToolExecution.m
//  mcpwa
//
//  WhatsApp MCP tool execution
//

#import "BotChatWindowController+MCPToolExecution.h"
#import "WALogger.h"

@implementation BotChatWindowController (MCPToolExecution)

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

#pragma mark - Status Helper

- (NSString *)friendlyStatusForTool:(NSString *)toolName {
    // Map internal tool names to user-friendly status messages
    static NSDictionary *friendlyNames = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        friendlyNames = @{
            @"whatsapp_start_session": @"Connecting to WhatsApp...",
            @"whatsapp_stop_session": @"Finishing up...",
            @"whatsapp_status": @"Checking WhatsApp...",
            @"whatsapp_list_chats": @"Loading chats...",
            @"whatsapp_get_current_chat": @"Reading chat...",
            @"whatsapp_open_chat": @"Opening chat...",
            @"whatsapp_get_messages": @"Reading messages...",
            @"whatsapp_send_message": @"Sending message...",
            @"whatsapp_search": @"Searching chats...",
            @"run_shell_command": @"Running command..."
        };
    });

    NSString *friendly = friendlyNames[toolName];
    return friendly ?: [NSString stringWithFormat:@"Processing..."];
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

@end
