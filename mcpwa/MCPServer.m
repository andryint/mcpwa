//
//  MCPServer.m
//  mcpwa
//
//  MCP (Model Context Protocol) server implementation for Claude Desktop
//  Communicates via transport layer (socket or stdio) using JSON-RPC 2.0
//

#import "MCPServer.h"
#import "MCPSocketTransport.h"
#import "WAAccessibility.h"
#import <Cocoa/Cocoa.h>

// MCP Protocol version
static NSString * const kMCPProtocolVersion = @"2024-11-05";
static NSString * const kServerName = @"whatsapp-mcp";
static NSString * const kServerVersion = @"1.0.0";

@interface MCPServer ()
@property (nonatomic, assign) BOOL running;
@property (nonatomic, strong) id<MCPTransport> transport;
@end

@implementation MCPServer

- (instancetype)initWithTransport:(id<MCPTransport>)transport
                         delegate:(id<MCPServerDelegate>)delegate {
    self = [super init];
    if (self) {
        _transport = transport;
        _transport.delegate = self;
        _delegate = delegate;
        _running = NO;
    }
    return self;
}

- (instancetype)initWithDelegate:(id<MCPServerDelegate>)delegate {
    // Default to socket transport
    MCPSocketTransport *socketTransport = [[MCPSocketTransport alloc] init];
    return [self initWithTransport:socketTransport delegate:delegate];
}

- (BOOL)isRunning {
    return _running;
}

- (BOOL)isConnected {
    return self.transport.isConnected;
}

#pragma mark - Server Lifecycle

- (BOOL)start:(NSError **)error {
    if (self.running) return YES;

    if (![self.transport start:error]) {
        return NO;
    }

    self.running = YES;
    return YES;
}

- (void)start {
    NSError *error = nil;
    if (![self start:&error]) {
        [self log:[NSString stringWithFormat:@"Failed to start: %@", error.localizedDescription]
            color:NSColor.redColor];
    }
}

- (void)stop {
    self.running = NO;
    [self.transport stop];
}

#pragma mark - MCPTransportDelegate

- (void)transportDidReceiveLine:(NSString *)line {
    [self processLine:line];
}

- (void)transportDidConnect {
    [self log:@"Client connected" color:NSColor.greenColor];
    if ([self.delegate respondsToSelector:@selector(serverDidConnect)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate serverDidConnect];
        });
    }
}

- (void)transportDidDisconnect {
    [self log:@"Client disconnected" color:NSColor.yellowColor];
    if ([self.delegate respondsToSelector:@selector(serverDidDisconnect)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate serverDidDisconnect];
        });
    }
}

- (void)transportLog:(NSString *)message {
    [self log:message color:NSColor.systemGrayColor];
}

- (void)processLine:(NSString *)line {
    // Log incoming (truncate long messages)
    NSString *displayLine = line.length > 200 ? 
        [[line substringToIndex:200] stringByAppendingString:@"..."] : line;
    [self log:[NSString stringWithFormat:@"◀ RECV: %@", displayLine] color:NSColor.systemBlueColor];
    
    NSError *error = nil;
    NSDictionary *request = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding]
                                                            options:0
                                                              error:&error];
    
    if (error || !request) {
        [self log:[NSString stringWithFormat:@"JSON parse error: %@", error.localizedDescription] color:NSColor.redColor];
        [self sendErrorCode:-32700 message:@"Parse error" id:nil];
        return;
    }
    
    NSString *method = request[@"method"];
    NSDictionary *params = request[@"params"] ?: @{};
    id requestId = request[@"id"];
    
    // Route to handlers
    if ([method isEqualToString:@"initialize"]) {
        [self handleInitialize:params id:requestId];
    } else if ([method isEqualToString:@"notifications/initialized"]) {
        [self log:@"✅ Client initialized" color:NSColor.greenColor];
    } else if ([method isEqualToString:@"tools/list"]) {
        [self handleToolsList:requestId];
    } else if ([method isEqualToString:@"tools/call"]) {
        [self handleToolCall:params id:requestId];
    } else if ([method isEqualToString:@"ping"]) {
        [self sendResult:@{} id:requestId];
    } else {
        [self log:[NSString stringWithFormat:@"Unknown method: %@", method] color:NSColor.orangeColor];
        [self sendErrorCode:-32601 message:@"Method not found" id:requestId];
    }
}

#pragma mark - MCP Protocol Handlers

- (void)handleInitialize:(NSDictionary *)params id:(id)requestId {
    [self log:@"🤝 Client connecting..." color:NSColor.cyanColor];
    
    NSDictionary *clientInfo = params[@"clientInfo"];
    if (clientInfo) {
        [self log:[NSString stringWithFormat:@"   Client: %@ v%@", 
                   clientInfo[@"name"] ?: @"Unknown",
                   clientInfo[@"version"] ?: @"?"]
            color:NSColor.systemGrayColor];
    }
    
    NSDictionary *result = @{
        @"protocolVersion": kMCPProtocolVersion,
        @"capabilities": @{
            @"tools": @{}
        },
        @"serverInfo": @{
            @"name": kServerName,
            @"version": kServerVersion
        }
    };
    [self sendResult:result id:requestId];
}

- (void)handleToolsList:(id)requestId {
    [self log:@"📋 Tools list requested" color:NSColor.cyanColor];
    
    NSArray *tools = @[
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
            @"description": @"Get list of recent visible WhatsApp chats with last message preview. Returns chat names, last messages, timestamps, and whether chats are pinned or group chats. Optionally filter by: 'all' (default), 'unread', 'favorites', or 'groups'.",
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
            @"description": @"Get the currently open chat's name and all visible messages. Use this to read the conversation that's currently on screen in WhatsApp.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{},
                @"required": @[]
            }
        },
        @{
            @"name": @"whatsapp_open_chat",
            @"description": @"Open a specific chat by name. Use partial matching - e.g., 'John' will match 'John Smith'. After opening, use whatsapp_get_current_chat to read messages.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"name": @{
                        @"type": @"string",
                        @"description": @"Name of the chat or contact to open (case-insensitive partial match)"
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
            @"name": @"whatsapp_find_chat",
            @"description": @"Find a chat by name without opening it. Returns chat info if found.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"name": @{
                        @"type": @"string",
                        @"description": @"Name to search for (case-insensitive partial match)"
                    }
                },
                @"required": @[@"name"]
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
            @"description": @"Global search across all WhatsApp chats. Searches for keywords in chat names and message content. Returns two lists: chats whose names match the query, and individual messages containing the query text.",
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
        @{
            @"name": @"whatsapp_clear_search",
            @"description": @"Clear the search field and return to normal chat list view.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{},
                @"required": @[]
            }
        },
        @{
            @"name": @"whatsapp_get_chat_filter",
            @"description": @"Get the currently selected chat list filter (All, Unread, Favorites, or Groups).",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{},
                @"required": @[]
            }
        },
        @{
            @"name": @"whatsapp_set_chat_filter",
            @"description": @"Set the chat list filter to show only certain chats. Options: 'all', 'unread' (only unread chats), 'favorites' (only favorite/starred chats), 'groups' (only group chats).",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"filter": @{
                        @"type": @"string",
                        @"description": @"Filter to apply: 'all', 'unread', 'favorites', or 'groups'",
                        @"enum": @[@"all", @"unread", @"favorites", @"groups"]
                    }
                },
                @"required": @[@"filter"]
            }
        }
    ];
    
    [self sendResult:@{@"tools": tools} id:requestId];
    [self log:[NSString stringWithFormat:@"   Sent %lu tools", (unsigned long)tools.count] color:NSColor.systemGrayColor];
}

- (void)handleToolCall:(NSDictionary *)params id:(id)requestId {
    NSString *toolName = params[@"name"];
    NSDictionary *args = params[@"arguments"] ?: @{};
    
    [self log:[NSString stringWithFormat:@"🔧 Tool call: %@", toolName] color:NSColor.magentaColor];
    if (args.count > 0) {
        [self log:[NSString stringWithFormat:@"   Args: %@", args] color:NSColor.systemGrayColor];
    }
    
    // Dispatch to tool implementations
    if ([toolName isEqualToString:@"whatsapp_status"]) {
        [self toolStatus:requestId];
    } else if ([toolName isEqualToString:@"whatsapp_list_chats"]) {
        [self toolListRecentChats:args[@"filter"] id:requestId];
    } else if ([toolName isEqualToString:@"whatsapp_get_chat_filter"]) {
        [self toolGetChatFilter:requestId];
    } else if ([toolName isEqualToString:@"whatsapp_set_chat_filter"]) {
        [self toolSetChatFilter:args[@"filter"] id:requestId];
    } else if ([toolName isEqualToString:@"whatsapp_get_current_chat"]) {
        [self toolGetCurrentChat:requestId];
    } else if ([toolName isEqualToString:@"whatsapp_open_chat"]) {
        [self toolOpenChat:args[@"name"] id:requestId];
    } else if ([toolName isEqualToString:@"whatsapp_get_messages"]) {
        [self toolGetMessages:args[@"chat_name"] id:requestId];
    } else if ([toolName isEqualToString:@"whatsapp_find_chat"]) {
        [self toolFindChat:args[@"name"] id:requestId];
    } else if ([toolName isEqualToString:@"whatsapp_send_message"]) {
        [self toolSendMessage:args[@"message"] id:requestId];
    } else if ([toolName isEqualToString:@"whatsapp_search"]) {
        [self toolGlobalSearch:args[@"query"] id:requestId];
    } else if ([toolName isEqualToString:@"whatsapp_clear_search"]) {
        [self toolClearSearch:requestId];
    } else {
        [self sendToolError:[NSString stringWithFormat:@"Unknown tool: %@", toolName] id:requestId];
    }
}

#pragma mark - Tool Implementations

- (BOOL)checkPrerequisites:(id)requestId {
    WAAccessibility *wa = [WAAccessibility shared];
    
    if (![wa isWhatsAppAvailable]) {
        [self log:@"❌ WhatsApp not available" color:NSColor.redColor];
        [self sendToolError:@"WhatsApp is not available.\n\nPlease ensure:\n1. WhatsApp Desktop is running\n2. mcpwa has Accessibility permissions in System Settings → Privacy & Security → Accessibility" id:requestId];
        return NO;
    }
    
    return YES;
}

- (void)toolStatus:(id)requestId {
    WAAccessibility *wa = [WAAccessibility shared];
    
    BOOL isAvailable = [wa isWhatsAppAvailable];
    
    NSString *message;
    if (isAvailable) {
        message = @"WhatsApp is running and accessible";
    } else {
        message = @"WhatsApp is not available. Ensure it's running and accessibility permissions are granted.";
    }
    
    NSDictionary *status = @{
        @"available": @(isAvailable),
        @"ready": @(isAvailable),
        @"message": message
    };
    
    [self log:[NSString stringWithFormat:@"   Status: %@", isAvailable ? @"Ready" : @"Not ready"] 
        color:NSColor.systemGrayColor];
    [self sendToolResult:[self jsonStringPretty:status] id:requestId];
}

- (void)toolListRecentChats:(NSString *)filterString id:(id)requestId
{
    if (![self checkPrerequisites:requestId]) return;

    WAAccessibility *wa = [WAAccessibility shared];
    WAChatFilter filter = [WAAccessibility chatFilterFromString:filterString];

    NSArray<WAChat *> *chats;
    if (filterString && filterString.length > 0) {
        chats = [wa getRecentChatsWithFilter:filter];
    } else {
        chats = [wa getRecentChats];
    }

    NSMutableArray *chatDicts = [NSMutableArray arrayWithCapacity:chats.count];
    for (WAChat *chat in chats) {
        [chatDicts addObject:[self chatToDictionary:chat]];
    }

    NSString *filterName = [WAAccessibility stringFromChatFilter:filter];
    NSDictionary *result = @{
        @"filter": filterName,
        @"count": @(chats.count),
        @"chats": chatDicts
    };

    [self log:[NSString stringWithFormat:@"   Filter: %@, Found %lu chats", filterName, (unsigned long)chats.count]
        color:NSColor.systemGrayColor];
    [self sendToolResult:[self jsonStringPretty:result] id:requestId];
}

- (void)toolGetCurrentChat:(id)requestId
{
    if (![self checkPrerequisites:requestId]) return;
    
    WAAccessibility *wa = [WAAccessibility shared];
    
    WACurrentChat *current = [wa getCurrentChat];
    
    if (!current) {
        NSDictionary *result = @{
            @"chatName": @"No chat open",
            @"messageCount": @0,
            @"messages": @[]
        };
        [self log:@"   No chat open" color:NSColor.yellowColor];
        [self sendToolResult:[self jsonStringPretty:result] id:requestId];
        return;
    }
    
    NSMutableArray *msgDicts = [NSMutableArray arrayWithCapacity:current.messages.count];
    for (WAMessage *msg in current.messages) {
        [msgDicts addObject:[self messageToDictionary:msg]];
    }
    
    NSDictionary *result = @{
        @"chatName": current.name ?: @"Unknown",
        @"lastSeen": current.lastSeen ?: @"",
        @"messageCount": @(current.messages.count),
        @"messages": msgDicts
    };
    
    [self log:[NSString stringWithFormat:@"   Chat: %@, %lu messages", 
               current.name ?: @"(none)", (unsigned long)current.messages.count]
        color:NSColor.systemGrayColor];
    [self sendToolResult:[self jsonStringPretty:result] id:requestId];
}

- (void)toolOpenChat:(NSString *)chatName id:(id)requestId {
    if (![self checkPrerequisites:requestId]) return;
    
    if (!chatName || chatName.length == 0) {
        [self sendToolError:@"Chat name is required" id:requestId];
        return;
    }
    
    WAAccessibility *wa = [WAAccessibility shared];
    BOOL success = [wa openChatWithName:chatName];
    
    if (success) {
        [NSThread sleepForTimeInterval:0.3];
        WACurrentChat *current = [wa getCurrentChat];
        NSString *actualName = current.name ?: chatName;
        [self log:[NSString stringWithFormat:@"   Opened: %@", actualName] 
            color:NSColor.greenColor];
        [self sendToolResult:[NSString stringWithFormat:@"Opened chat: %@", actualName] id:requestId];
    } else {
        [self log:[NSString stringWithFormat:@"   Not found: %@", chatName] color:NSColor.redColor];
        [self sendToolError:[NSString stringWithFormat:@"Could not find chat matching: %@", chatName] id:requestId];
    }
}

- (void)toolGetMessages:(NSString *)chatName id:(id)requestId {
    if (![self checkPrerequisites:requestId]) return;
    
    if (!chatName || chatName.length == 0) {
        [self sendToolError:@"Chat name is required" id:requestId];
        return;
    }
    
    WAAccessibility *wa = [WAAccessibility shared];
    
    WACurrentChat *current = [wa getCurrentChat];
    BOOL needsSwitch = !current || ![current.name.lowercaseString containsString:chatName.lowercaseString];
    
    if (needsSwitch) {
        [self log:[NSString stringWithFormat:@"   Switching to chat: %@", chatName] color:NSColor.systemGrayColor];
        if (![wa openChatWithName:chatName]) {
            [self log:[NSString stringWithFormat:@"   Not found: %@", chatName] color:NSColor.redColor];
            [self sendToolError:[NSString stringWithFormat:@"Could not find chat matching: %@", chatName] id:requestId];
            return;
        }
        [NSThread sleepForTimeInterval:0.5];
    }
    
    [self toolGetCurrentChat:requestId];
}

- (void)toolFindChat:(NSString *)name id:(id)requestId {
    if (![self checkPrerequisites:requestId]) return;
    
    if (!name || name.length == 0) {
        [self sendToolError:@"Search name is required" id:requestId];
        return;
    }
    
    WAChat *chat = [[WAAccessibility shared] findChatWithName:name];
    
    if (chat) {
        NSDictionary *result = @{
            @"found": @YES,
            @"chat": [self chatToDictionary:chat]
        };
        [self log:[NSString stringWithFormat:@"   Found: %@", chat.name] color:NSColor.greenColor];
        [self sendToolResult:[self jsonStringPretty:result] id:requestId];
    } else {
        NSDictionary *result = @{
            @"found": @NO,
            @"message": [NSString stringWithFormat:@"No chat found matching: %@", name]
        };
        [self log:[NSString stringWithFormat:@"   Not found: %@", name] color:NSColor.yellowColor];
        [self sendToolResult:[self jsonStringPretty:result] id:requestId];
    }
}

- (void)toolSendMessage:(NSString *)message id:(id)requestId {
    if (![self checkPrerequisites:requestId]) return;
    
    if (!message || message.length == 0) {
        [self sendToolError:@"Message text is required" id:requestId];
        return;
    }
    
    WAAccessibility *wa = [WAAccessibility shared];
    
    // Check if a chat is open
    WACurrentChat *current = [wa getCurrentChat];
    if (!current) {
        [self sendToolError:@"No chat is currently open. Use whatsapp_open_chat first to select a recipient." id:requestId];
        return;
    }
    
    // Activate WhatsApp first
    [wa activateWhatsApp];
    [NSThread sleepForTimeInterval:0.2];
    
    BOOL success = [wa sendMessage:message];
    
    if (success) {
        [self log:[NSString stringWithFormat:@"   Sent to %@: %@", current.name, message] color:NSColor.greenColor];
        [self sendToolResult:[NSString stringWithFormat:@"Message sent to %@", current.name] id:requestId];
    } else {
        [self log:@"   Failed to send message" color:NSColor.redColor];
        [self sendToolError:@"Failed to send message. Make sure WhatsApp is in the foreground." id:requestId];
    }
}

- (void)toolGlobalSearch:(NSString *)query id:(id)requestId {
    if (![self checkPrerequisites:requestId]) return;
    
    if (!query || query.length == 0) {
        [self sendToolError:@"Search query is required" id:requestId];
        return;
    }
    
    [self log:[NSString stringWithFormat:@"   Searching: %@", query] color:NSColor.systemGrayColor];
    
    WAAccessibility *wa = [WAAccessibility shared];
    WASearchResults *results = [wa globalSearch:query];
    
    if (!results) {
        [self sendToolError:@"Search failed - could not access search field" id:requestId];
        return;
    }
    
    // Convert chat matches to dictionaries
    NSMutableArray *chatDicts = [NSMutableArray arrayWithCapacity:results.chatMatches.count];
    for (WASearchChatResult *chat in results.chatMatches) {
        [chatDicts addObject:[self searchChatResultToDictionary:chat]];
    }
    
    // Convert message matches to dictionaries
    NSMutableArray *msgDicts = [NSMutableArray arrayWithCapacity:results.messageMatches.count];
    for (WASearchMessageResult *msg in results.messageMatches) {
        [msgDicts addObject:[self searchMessageResultToDictionary:msg]];
    }
    
    NSDictionary *result = @{
        @"query": results.query,
        @"chatMatchCount": @(results.chatMatches.count),
        @"messageMatchCount": @(results.messageMatches.count),
        @"chatMatches": chatDicts,
        @"messageMatches": msgDicts
    };
    
    [self log:[NSString stringWithFormat:@"   Found %lu chats, %lu messages", 
               (unsigned long)results.chatMatches.count, 
               (unsigned long)results.messageMatches.count]
        color:NSColor.greenColor];
    [self sendToolResult:[self jsonStringPretty:result] id:requestId];
}

- (void)toolClearSearch:(id)requestId {
    if (![self checkPrerequisites:requestId]) return;

    WAAccessibility *wa = [WAAccessibility shared];
    BOOL success = [wa clearSearch];

    if (success) {
        [self log:@"   Search cleared" color:NSColor.greenColor];
        [self sendToolResult:@"Search cleared" id:requestId];
    } else {
        [self log:@"   No active search to clear" color:NSColor.yellowColor];
        [self sendToolResult:@"No active search to clear" id:requestId];
    }
}

- (void)toolGetChatFilter:(id)requestId {
    if (![self checkPrerequisites:requestId]) return;

    WAAccessibility *wa = [WAAccessibility shared];
    WAChatFilter filter = [wa getSelectedChatFilter];
    NSString *filterName = [WAAccessibility stringFromChatFilter:filter];

    NSDictionary *result = @{
        @"filter": filterName,
        @"description": [self filterDescription:filter]
    };

    [self log:[NSString stringWithFormat:@"   Current filter: %@", filterName] color:NSColor.systemGrayColor];
    [self sendToolResult:[self jsonStringPretty:result] id:requestId];
}

- (void)toolSetChatFilter:(NSString *)filterString id:(id)requestId {
    if (![self checkPrerequisites:requestId]) return;

    if (!filterString || filterString.length == 0) {
        [self sendToolError:@"Filter is required. Options: 'all', 'unread', 'favorites', 'groups'" id:requestId];
        return;
    }

    WAAccessibility *wa = [WAAccessibility shared];
    WAChatFilter filter = [WAAccessibility chatFilterFromString:filterString];
    NSString *filterName = [WAAccessibility stringFromChatFilter:filter];

    BOOL success = [wa selectChatFilter:filter];

    if (success) {
        NSDictionary *result = @{
            @"success": @YES,
            @"filter": filterName,
            @"description": [self filterDescription:filter]
        };
        [self log:[NSString stringWithFormat:@"   Set filter: %@", filterName] color:NSColor.greenColor];
        [self sendToolResult:[self jsonStringPretty:result] id:requestId];
    } else {
        [self log:[NSString stringWithFormat:@"   Failed to set filter: %@", filterName] color:NSColor.redColor];
        [self sendToolError:[NSString stringWithFormat:@"Could not set filter to '%@'. Make sure WhatsApp is showing the chat list.", filterName] id:requestId];
    }
}

- (NSString *)filterDescription:(WAChatFilter)filter {
    switch (filter) {
        case WAChatFilterAll:
            return @"Showing all chats";
        case WAChatFilterUnread:
            return @"Showing only unread chats";
        case WAChatFilterFavorites:
            return @"Showing only favorite/starred chats";
        case WAChatFilterGroups:
            return @"Showing only group chats";
    }
    return @"Showing all chats";
}

#pragma mark - Data Conversion Helpers

- (NSDictionary *)chatToDictionary:(WAChat *)chat {
    return @{
        @"name": chat.name ?: @"",
        @"lastMessage": chat.lastMessage ?: @"",
        @"timestamp": chat.timestamp ?: @"",
        @"isPinned": @(chat.isPinned),
        @"isGroup": @(chat.isGroup),
        @"sender": chat.sender ?: @"",
        @"index": @(chat.index)
    };
}

- (NSDictionary *)messageToDictionary:(WAMessage *)msg {
    NSString *directionStr;
    switch (msg.direction) {
        case WAMessageDirectionIncoming:
            directionStr = @"incoming";
            break;
        case WAMessageDirectionOutgoing:
            directionStr = @"outgoing";
            break;
        default:
            directionStr = @"system";
            break;
    }
    
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:@{
        @"text": msg.text ?: @"",
        @"direction": directionStr,
        @"timestamp": msg.timestamp ?: @"",
        @"isRead": @(msg.isRead)
    }];
    
    if (msg.sender) {
        dict[@"sender"] = msg.sender;
    }
    if (msg.replyTo) {
        dict[@"replyTo"] = msg.replyTo;
    }
    if (msg.replyText) {
        dict[@"replyText"] = msg.replyText;
    }
    if (msg.reactions.count > 0) {
        dict[@"reactions"] = msg.reactions;
    }
    
    return dict;
}

- (NSDictionary *)searchChatResultToDictionary:(WASearchChatResult *)chat {
    return @{
        @"chatName": chat.chatName ?: @"",
        @"lastMessagePreview": chat.lastMessagePreview ?: @""
    };
}

- (NSDictionary *)searchMessageResultToDictionary:(WASearchMessageResult *)msg {
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:@{
        @"chatName": msg.chatName ?: @"",
        @"messagePreview": msg.messagePreview ?: @""
    }];
    
    if (msg.sender) {
        dict[@"sender"] = msg.sender;
    }
    
    return dict;
}

#pragma mark - JSON-RPC Response Helpers

- (void)sendResult:(NSDictionary *)result id:(id)requestId {
    NSDictionary *response = @{
        @"jsonrpc": @"2.0",
        @"id": requestId ?: [NSNull null],
        @"result": result
    };
    [self writeJSON:response];
}

- (void)sendErrorCode:(NSInteger)code message:(NSString *)message id:(id)requestId {
    NSDictionary *response = @{
        @"jsonrpc": @"2.0",
        @"id": requestId ?: [NSNull null],
        @"error": @{
            @"code": @(code),
            @"message": message
        }
    };
    [self writeJSON:response];
}

- (void)sendToolResult:(NSString *)content id:(id)requestId {
    NSDictionary *result = @{
        @"content": @[@{
            @"type": @"text",
            @"text": content
        }]
    };
    [self sendResult:result id:requestId];
}

- (void)sendToolError:(NSString *)errorMessage id:(id)requestId {
    NSDictionary *result = @{
        @"content": @[@{
            @"type": @"text",
            @"text": errorMessage
        }],
        @"isError": @YES
    };
    [self sendResult:result id:requestId];
}

- (void)writeJSON:(NSDictionary *)dict {
    NSString *json = [self jsonString:dict];
    [self.transport writeLine:json];

    // Log outgoing (truncate long messages)
    NSString *displayJson = json.length > 200 ?
        [[json substringToIndex:200] stringByAppendingString:@"..."] : json;
    [self log:[NSString stringWithFormat:@"▶ SEND: %@", displayJson] color:NSColor.systemTealColor];
}

- (NSString *)jsonString:(id)obj {
    NSData *data = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (NSString *)jsonStringPretty:(id)obj {
    NSData *data = [NSJSONSerialization dataWithJSONObject:obj options:NSJSONWritingPrettyPrinted error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

#pragma mark - Logging

- (void)log:(NSString *)message color:(NSColor *)color {
    if (self.delegate) {
        [self.delegate appendLog:message color:color];
    }
}

@end
