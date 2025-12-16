// mcp-shim.m - with MCP handshake handling and hardcoded tools

#import <Foundation/Foundation.h>
#import <os/log.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <errno.h>

static os_log_t logger;
static NSString *socketPath = @"/tmp/mcpwa.sock";
static NSFileHandle *stdoutHandle;
static NSFileHandle *serverHandle;
static BOOL stdinClosed = NO;

#pragma mark - Tool Definitions

NSArray* getMcpwaTools(void) {
    return @[
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
            @"description": @"Get list of all visible WhatsApp chats with last message preview. Returns chat names, last messages, timestamps, and whether chats are pinned or group chats.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{},
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
        }
    ];
}

#pragma mark - Socket Connection

int connectToServer(void) {
    int sock = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sock < 0) {
        os_log_error(logger, "Failed to create socket: %{public}s", strerror(errno));
        return -1;
    }

    struct sockaddr_un addr = {0};
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, socketPath.UTF8String, sizeof(addr.sun_path) - 1);

    if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(sock);
        return -1;
    }

    os_log_info(logger, "Connected to mcpwa at %{public}@", socketPath);
    return sock;
}

#pragma mark - Response Helpers

void sendResponse(NSString *response) {
    NSString *line = [response stringByAppendingString:@"\n"];
    [stdoutHandle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
}

void sendJsonResponse(NSDictionary *dict) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
    sendResponse([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
}

void sendToServer(NSFileHandle *handle, NSDictionary *message) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:message options:0 error:nil];
    NSString *line = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] stringByAppendingString:@"\n"];
    [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
}

#pragma mark - Server Initialization

BOOL initializeServer(NSFileHandle *handle) {
    NSDictionary *initRequest = @{
        @"jsonrpc": @"2.0",
        @"id": @1,
        @"method": @"initialize",
        @"params": @{
            @"protocolVersion": @"2024-11-05",
            @"clientInfo": @{@"name": @"mcp-shim", @"version": @"1.0"},
            @"capabilities": @{}
        }
    };
    
    @try {
        sendToServer(handle, initRequest);
        os_log_info(logger, "Sent initialize to server");
        
        NSData *response = [handle availableData];
        if (response.length == 0) {
            os_log_error(logger, "Server closed during initialize");
            return NO;
        }
        os_log_info(logger, "Server responded to initialize");
        
        NSDictionary *initializedNotif = @{
            @"jsonrpc": @"2.0",
            @"method": @"notifications/initialized"
        };
        sendToServer(handle, initializedNotif);
        os_log_info(logger, "Sent initialized notification to server");
        
        return YES;
    } @catch (NSException *e) {
        os_log_error(logger, "Exception during server init: %{public}@", e.reason);
        return NO;
    }
}

#pragma mark - Local Request Handling

void handleLocalRequest(NSDictionary *request) {
    NSString *method = request[@"method"];
    id reqId = request[@"id"];
    
    if ([method isEqualToString:@"initialize"]) {
        NSDictionary *response = @{
            @"jsonrpc": @"2.0",
            @"id": reqId,
            @"result": @{
                @"protocolVersion": @"2024-11-05",
                @"serverInfo": @{@"name": @"mcpwa-shim", @"version": @"1.0"},
                @"capabilities": @{@"tools": @{}}
            }
        };
        sendJsonResponse(response);
        os_log_info(logger, "Handled initialize locally");
    }
    else if ([method isEqualToString:@"notifications/initialized"]) {
        os_log_info(logger, "Got initialized notification");
    }
    else if ([method isEqualToString:@"tools/list"]) {
        // Return hardcoded mcpwa tools
        NSDictionary *response = @{
            @"jsonrpc": @"2.0",
            @"id": reqId,
            @"result": @{@"tools": getMcpwaTools()}
        };
        sendJsonResponse(response);
        os_log_info(logger, "Returned mcpwa tools list (9 tools, server not connected)");
    }
    else if ([method isEqualToString:@"tools/call"]) {
        // Server not connected - return error
        NSString *toolName = request[@"params"][@"name"] ?: @"unknown";
        NSDictionary *response = @{
            @"jsonrpc": @"2.0",
            @"id": reqId,
            @"result": @{
                @"content": @[@{
                    @"type": @"text",
                    @"text": @"mcpwa server is not running. Please start the mcpwa application first."
                }],
                @"isError": @YES
            }
        };
        sendJsonResponse(response);
        os_log_info(logger, "Tool call '%{public}@' rejected - server not connected", toolName);
    }
    else {
        os_log_info(logger, "Unknown method handled locally: %{public}@", method);
    }
}

void forwardToServer(NSString *line) {
    if (serverHandle) {
        @try {
            [serverHandle writeData:[[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
        } @catch (NSException *e) {
            os_log_error(logger, "Failed to forward to server");
            serverHandle = nil;
        }
    }
}

#pragma mark - Main

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        logger = os_log_create("com.mcpwa.shim", "proxy");
        stdoutHandle = [NSFileHandle fileHandleWithStandardOutput];
        
        if (argc > 1) {
            socketPath = [NSString stringWithUTF8String:argv[1]];
        }
        
        os_log_info(logger, "Shim started, socket: %{public}@", socketPath);
        
        // Background: keep trying to connect to server
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            while (!stdinClosed) {
                if (!serverHandle) {
                    int sock = connectToServer();
                    if (sock >= 0) {
                        NSFileHandle *handle = [[NSFileHandle alloc] initWithFileDescriptor:sock closeOnDealloc:YES];
                        
                        if (!initializeServer(handle)) {
                            os_log_error(logger, "Failed to initialize server, will retry");
                            continue;
                        }
                        
                        serverHandle = handle;
                        
                        // Notify Claude that tools changed (server now available)
                        NSDictionary *notification = @{
                            @"jsonrpc": @"2.0",
                            @"method": @"notifications/tools/list_changed"
                        };
                        sendJsonResponse(notification);
                        os_log_info(logger, "Sent tools/list_changed notification to Claude");
                        
                        // Forward server responses to stdout
                        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                            NSFileHandle *h = serverHandle;
                            NSData *data;
                            while (h && (data = [h availableData]) && data.length > 0) {
                                [stdoutHandle writeData:data];
                            }
                            os_log_info(logger, "Server disconnected");
                            serverHandle = nil;
                        });
                    }
                }
                usleep(500000);
            }
        });
        
        // Main: read stdin, route appropriately
        NSFileHandle *stdinHandle = [NSFileHandle fileHandleWithStandardInput];
        NSMutableData *buffer = [NSMutableData data];
        
        NSData *chunk;
        while ((chunk = [stdinHandle availableData]) && chunk.length > 0) {
            [buffer appendData:chunk];
            
            NSString *str = [[NSString alloc] initWithData:buffer encoding:NSUTF8StringEncoding];
            NSArray *lines = [str componentsSeparatedByString:@"\n"];
            
            for (NSUInteger i = 0; i < lines.count - 1; i++) {
                NSString *line = lines[i];
                if (line.length == 0) continue;
                
                NSData *jsonData = [line dataUsingEncoding:NSUTF8StringEncoding];
                NSDictionary *request = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
                
                if (serverHandle) {
                    forwardToServer(line);
                } else {
                    handleLocalRequest(request);
                }
            }
            
            NSString *remainder = [lines lastObject];
            buffer = [[remainder dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
        }
        
        os_log_info(logger, "stdin closed, exiting");
        stdinClosed = YES;
        return 0;
    }
}
