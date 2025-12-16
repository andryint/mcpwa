
#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import "MCPTransport.h"

NS_ASSUME_NONNULL_BEGIN

@protocol MCPServerDelegate <NSObject>
- (void)appendLog:(NSString *)message;
- (void)appendLog:(NSString *)message color:(NSColor *)color;
@optional
- (void)serverDidConnect;
- (void)serverDidDisconnect;
@end

@interface MCPServer : NSObject <MCPTransportDelegate>

@property (nonatomic, weak, nullable) id<MCPServerDelegate> delegate;
@property (nonatomic, strong, readonly) id<MCPTransport> transport;

/// Initialize with custom transport
- (instancetype)initWithTransport:(id<MCPTransport>)transport
                         delegate:(nullable id<MCPServerDelegate>)delegate;

/// Initialize with delegate (uses socket transport by default)
- (instancetype)initWithDelegate:(nullable id<MCPServerDelegate>)delegate;

/// Start the MCP server
- (BOOL)start:(NSError **)error;

/// Start the MCP server (legacy, ignores errors)
- (void)start;

/// Stop the MCP server
- (void)stop;

/// Check if server is running
@property (nonatomic, readonly) BOOL isRunning;

/// Check if client is connected
@property (nonatomic, readonly) BOOL isConnected;

@end

NS_ASSUME_NONNULL_END
