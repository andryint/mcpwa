// mcp-shim.m
// Compile: clang -framework Foundation -o mcp-shim mcp-shim.m

#import <Foundation/Foundation.h>
#import <os/log.h>
#import <sys/socket.h>
#import <sys/un.h>

static os_log_t logger;
static NSString *socketPath = @"/tmp/mcpwa.sock";
static NSFileHandle *stdoutHandle;
static BOOL stdinClosed = NO;

int connectToServer(void) {
    int sock = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sock < 0) {
        os_log_error(logger, "Failed to create socket: %d", errno);
        return -1;
    }
    
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

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        logger = os_log_create("com.mcpwa.shim", "proxy");
        stdoutHandle = [NSFileHandle fileHandleWithStandardOutput];
        
        if (argc > 1) {
            socketPath = [NSString stringWithUTF8String:argv[1]];
        }
        
        os_log_info(logger, "Shim started, socket: %{public}@", socketPath);
        
        // stdin monitor — exit when Claude dies
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSFileHandle *stdinHandle = [NSFileHandle fileHandleWithStandardInput];
            NSMutableData *pendingData = [NSMutableData data];
            
            NSData *data;
            while ((data = [stdinHandle availableData]) && data.length > 0) {
                @synchronized (pendingData) {
                    [pendingData appendData:data];
                }
            }
            os_log_info(logger, "stdin closed, exiting");
            stdinClosed = YES;
            exit(0);
        });
        
        // Main loop — connect, proxy, reconnect on server restart
        while (!stdinClosed) {
            int sock = connectToServer();
            
            if (sock < 0) {
                usleep(500000);  // retry every 500ms
                continue;
            }
            
            NSFileHandle *serverHandle = [[NSFileHandle alloc] initWithFileDescriptor:sock closeOnDealloc:YES];
            
            // Forward stdin to server (in background)
            // Note: simplified — in production you'd buffer pending data
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSFileHandle *stdinHandle = [NSFileHandle fileHandleWithStandardInput];
                NSData *data;
                while ((data = [stdinHandle availableData]) && data.length > 0) {
                    @try {
                        [serverHandle writeData:data];
                    } @catch (NSException *e) {
                        break;  // server gone, exit write loop
                    }
                }
            });
            
            // Forward server to stdout (main thread)
            NSData *data;
            while ((data = [serverHandle availableData]) && data.length > 0) {
                [stdoutHandle writeData:data];
            }
            
            os_log_info(logger, "Server disconnected, will reconnect...");
            // Loop continues, will reconnect
        }
        
        return 0;
    }
}