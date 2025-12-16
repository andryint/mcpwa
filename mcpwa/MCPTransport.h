//
//  MCPTransport.h
//  mcpwa
//
//  Transport abstraction for MCP server - allows stdio or Unix socket
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Transport type enumeration
typedef NS_ENUM(NSInteger, MCPTransportType) {
    MCPTransportTypeStdio,      // Read from stdin, write to stdout
    MCPTransportTypeSocket      // Listen on Unix socket
};

/// Delegate protocol for receiving transport events
@protocol MCPTransportDelegate <NSObject>
- (void)transportDidReceiveLine:(NSString *)line;
- (void)transportDidDisconnect;
- (void)transportDidConnect;
@optional
- (void)transportLog:(NSString *)message;
@end

/// Abstract transport protocol
@protocol MCPTransport <NSObject>
@property (nonatomic, weak, nullable) id<MCPTransportDelegate> delegate;
@property (nonatomic, readonly) BOOL isConnected;

/// Start the transport (begin listening/accepting)
- (BOOL)start:(NSError **)error;

/// Stop the transport
- (void)stop;

/// Write data to connected client
- (void)writeLine:(NSString *)line;
@end

NS_ASSUME_NONNULL_END
