//
//  MCPStdioTransport.m
//  mcpwa
//
//  Stdio-based transport for MCP server
//

#import "MCPStdioTransport.h"

@interface MCPStdioTransport ()
@property (nonatomic, assign) BOOL running;
@property (nonatomic, strong) NSThread *readThread;
@property (nonatomic, strong) NSFileHandle *inputHandle;
@property (nonatomic, assign) BOOL connected;
@end

@implementation MCPStdioTransport

- (instancetype)init {
    self = [super init];
    if (self) {
        _running = NO;
        _connected = NO;
    }
    return self;
}

- (BOOL)isConnected {
    return _connected;
}

#pragma mark - MCPTransport

- (BOOL)start:(NSError **)error {
    if (self.running) return YES;

    self.running = YES;
    self.connected = YES;

    // Disable stdout buffering
    setvbuf(stdout, NULL, _IONBF, 0);

    // Notify connected (stdio is always "connected")
    if ([self.delegate respondsToSelector:@selector(transportDidConnect)]) {
        [self.delegate transportDidConnect];
    }

    // Start reader thread
    self.readThread = [[NSThread alloc] initWithTarget:self selector:@selector(readLoop) object:nil];
    self.readThread.name = @"MCPStdioTransport";
    [self.readThread start];

    return YES;
}

- (void)stop {
    self.running = NO;
    self.connected = NO;

    [self.inputHandle closeFile];

    while (self.readThread && !self.readThread.isFinished) {
        [NSThread sleepForTimeInterval:0.1];
    }
    self.readThread = nil;
}

- (void)writeLine:(NSString *)line {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

#pragma mark - Read Loop

- (void)readLoop {
    @autoreleasepool {
        self.inputHandle = [NSFileHandle fileHandleWithStandardInput];
        NSMutableData *buffer = [NSMutableData data];

        while (self.running) {
            @autoreleasepool {
                @try {
                    NSData *data = [self.inputHandle availableData];

                    if (data.length == 0) {
                        // EOF
                        [self log:@"stdio: EOF received"];
                        break;
                    }

                    [buffer appendData:data];
                    [self processBuffer:buffer];
                }
                @catch (NSException *exception) {
                    [self log:[NSString stringWithFormat:@"stdio exception: %@", exception]];
                    break;
                }
            }
        }

        self.running = NO;
        self.connected = NO;

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

        // Notify delegate on main queue (or current queue for processing)
        [self.delegate transportDidReceiveLine:line];
    }
}

- (void)log:(NSString *)message {
    if ([self.delegate respondsToSelector:@selector(transportLog:)]) {
        [self.delegate transportLog:message];
    }
}

@end
