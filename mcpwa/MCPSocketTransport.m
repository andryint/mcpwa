//
//  MCPSocketTransport.m
//  mcpwa
//
//  Unix socket transport for MCP server
//

#import "MCPSocketTransport.h"
#import <sys/socket.h>
#import <sys/un.h>
#import <unistd.h>

NSString * const kMCPDefaultSocketPath = @"/tmp/mcpwa.sock";

@interface MCPSocketTransport ()
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) int serverSocket;
@property (nonatomic, assign) int clientSocket;
@property (nonatomic, strong) NSThread *acceptThread;
@property (nonatomic, strong) NSThread *readThread;
@property (nonatomic, strong) NSString *path;
@property (nonatomic, assign) BOOL connected;
@end

@implementation MCPSocketTransport

- (instancetype)init {
    return [self initWithSocketPath:kMCPDefaultSocketPath];
}

- (instancetype)initWithSocketPath:(NSString *)path {
    self = [super init];
    if (self) {
        _path = [path copy];
        _running = NO;
        _connected = NO;
        _serverSocket = -1;
        _clientSocket = -1;
    }
    return self;
}

- (NSString *)socketPath {
    return _path;
}

- (BOOL)isConnected {
    return _connected;
}

#pragma mark - MCPTransport

- (BOOL)start:(NSError **)error {
    if (self.running) return YES;

    // Remove stale socket file
    unlink(self.path.UTF8String);

    // Create socket
    self.serverSocket = socket(AF_UNIX, SOCK_STREAM, 0);
    if (self.serverSocket < 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"MCPSocketTransport"
                                         code:errno
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to create socket"}];
        }
        return NO;
    }

    // Bind to path
    struct sockaddr_un addr = {0};
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, self.path.UTF8String, sizeof(addr.sun_path) - 1);

    if (bind(self.serverSocket, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"MCPSocketTransport"
                                         code:errno
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to bind socket"}];
        }
        close(self.serverSocket);
        self.serverSocket = -1;
        return NO;
    }

    // Listen
    if (listen(self.serverSocket, 1) < 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"MCPSocketTransport"
                                         code:errno
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to listen on socket"}];
        }
        close(self.serverSocket);
        unlink(self.path.UTF8String);
        self.serverSocket = -1;
        return NO;
    }

    self.running = YES;

    [self log:[NSString stringWithFormat:@"Listening on %@", self.path]];

    // Start accept thread
    self.acceptThread = [[NSThread alloc] initWithTarget:self selector:@selector(acceptLoop) object:nil];
    self.acceptThread.name = @"MCPSocketTransport-Accept";
    [self.acceptThread start];

    return YES;
}

- (void)stop {
    self.running = NO;

    // Close client connection if any
    if (self.clientSocket >= 0) {
        close(self.clientSocket);
        self.clientSocket = -1;
    }

    // Close server socket
    if (self.serverSocket >= 0) {
        close(self.serverSocket);
        self.serverSocket = -1;
    }

    // Remove socket file
    unlink(self.path.UTF8String);

    // Wait for threads
    while (self.acceptThread && !self.acceptThread.isFinished) {
        [NSThread sleepForTimeInterval:0.1];
    }
    while (self.readThread && !self.readThread.isFinished) {
        [NSThread sleepForTimeInterval:0.1];
    }

    self.acceptThread = nil;
    self.readThread = nil;
    self.connected = NO;
}

- (void)writeLine:(NSString *)line {
    if (self.clientSocket < 0) return;

    NSString *lineWithNewline = [line stringByAppendingString:@"\n"];
    NSData *data = [lineWithNewline dataUsingEncoding:NSUTF8StringEncoding];

    ssize_t written = write(self.clientSocket, data.bytes, data.length);
    if (written < 0) {
        [self log:@"Write error, closing client"];
        [self closeClient];
    }
}

#pragma mark - Accept Loop

- (void)acceptLoop {
    @autoreleasepool {
        while (self.running) {
            [self log:@"Waiting for client connection..."];

            int client = accept(self.serverSocket, NULL, NULL);

            if (client < 0) {
                if (self.running) {
                    [self log:[NSString stringWithFormat:@"Accept error: %d", errno]];
                }
                break;
            }

            [self log:@"Client connected"];
            self.clientSocket = client;
            self.connected = YES;

            // Notify delegate
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([self.delegate respondsToSelector:@selector(transportDidConnect)]) {
                    [self.delegate transportDidConnect];
                }
            });

            // Handle this client (blocks until disconnect)
            [self handleClient];

            // Client disconnected, loop back to accept new connection
            [self log:@"Client disconnected, waiting for reconnection..."];
        }

        [self log:@"Accept loop ended"];
    }
}

- (void)handleClient {
    NSMutableData *buffer = [NSMutableData data];
    char readBuffer[4096];

    while (self.running && self.clientSocket >= 0) {
        ssize_t bytesRead = read(self.clientSocket, readBuffer, sizeof(readBuffer));

        if (bytesRead <= 0) {
            // EOF or error
            break;
        }

        [buffer appendBytes:readBuffer length:bytesRead];
        [self processBuffer:buffer];
    }

    // Cleanup
    [self closeClient];
}

- (void)closeClient {
    if (self.clientSocket >= 0) {
        close(self.clientSocket);
        self.clientSocket = -1;
    }

    BOOL wasConnected = self.connected;
    self.connected = NO;

    if (wasConnected) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate transportDidDisconnect];
        });
    }
}

- (void)processBuffer:(NSMutableData *)buffer {
    while (YES) {
        NSRange newlineRange = [buffer rangeOfData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]
                                           options:0
                                             range:NSMakeRange(0, buffer.length)];

        if (newlineRange.location == NSNotFound) break;

        NSData *lineData = [buffer subdataWithRange:NSMakeRange(0, newlineRange.location)];
        [buffer replaceBytesInRange:NSMakeRange(0, newlineRange.location + 1) withBytes:NULL length:0];

        if (lineData.length == 0) continue;

        NSString *line = [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];

        // Notify delegate
        [self.delegate transportDidReceiveLine:line];
    }
}

- (void)log:(NSString *)message {
    if ([self.delegate respondsToSelector:@selector(transportLog:)]) {
        [self.delegate transportLog:[NSString stringWithFormat:@"[socket] %@", message]];
    }
}

@end
