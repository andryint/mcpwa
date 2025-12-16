// mcp-shim.m - with MCP handshake handling

#import <Foundation/Foundation.h>
#import <os/log.h>
#import <sys/socket.h>
#import <sys/un.h>

static os_log_t logger;
static NSString *socketPath = @"/tmp/mcpwa.sock";
static NSFileHandle *stdoutHandle;
static NSFileHandle *serverHandle;
static BOOL stdinClosed = NO;

int connectToServer(void) {
    int sock = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sock < 0) return -1;
    
    struct sockaddr_un addr = {0};
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, socketPath.UTF8String, sizeof(addr.sun_path) - 1);
    
    if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(sock);
        return -1;
    }
    
    os_log_info(logger, "Connected to mcpwa");
    return sock;
}

void sendResponse(NSString *response) {
    NSString *line = [response stringByAppendingString:@"\n"];
    [stdoutHandle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
}

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
        NSData *data = [NSJSONSerialization dataWithJSONObject:response options:0 error:nil];
        sendResponse([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
        os_log_info(logger, "Handled initialize locally");
    }
    else if ([method isEqualToString:@"notifications/initialized"]) {
        // No response needed for notifications
        os_log_info(logger, "Got initialized notification");
    }
    else if ([method isEqualToString:@"tools/list"]) {
        // Return empty tools until server connects
        NSDictionary *response = @{
            @"jsonrpc": @"2.0",
            @"id": reqId,
            @"result": @{@"tools": @[]}
        };
        NSData *data = [NSJSONSerialization dataWithJSONObject:response options:0 error:nil];
        sendResponse([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
        os_log_info(logger, "Returned empty tools list (server not connected)");
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
                        serverHandle = [[NSFileHandle alloc] initWithFileDescriptor:sock closeOnDealloc:YES];
                        
                        // Notify Claude that tools changed (server now available)
                        NSDictionary *notification = @{
                            @"jsonrpc": @"2.0",
                            @"method": @"notifications/tools/list_changed"
                        };
                        NSData *data = [NSJSONSerialization dataWithJSONObject:notification options:0 error:nil];
                        sendResponse([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
                        os_log_info(logger, "Sent tools/list_changed notification");
                        
                        // Forward server responses to stdout
                        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                            NSFileHandle *handle = serverHandle;
                            NSData *data;
                            while (handle && (data = [handle availableData]) && data.length > 0) {
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
            
            // Process complete lines
            NSString *str = [[NSString alloc] initWithData:buffer encoding:NSUTF8StringEncoding];
            NSArray *lines = [str componentsSeparatedByString:@"\n"];
            
            for (NSUInteger i = 0; i < lines.count - 1; i++) {
                NSString *line = lines[i];
                if (line.length == 0) continue;
                
                NSData *jsonData = [line dataUsingEncoding:NSUTF8StringEncoding];
                NSDictionary *request = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
                
                if (serverHandle) {
                    // Forward to real server
                    forwardToServer(line);
                } else {
                    // Handle locally
                    handleLocalRequest(request);
                }
            }
            
            // Keep incomplete line in buffer
            NSString *remainder = [lines lastObject];
            buffer = [[remainder dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
        }
        
        os_log_info(logger, "stdin closed, exiting");
        stdinClosed = YES;
        return 0;
    }
}