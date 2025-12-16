//
//  MCPSocketTransport.h
//  mcpwa
//
//  Unix socket transport for MCP server
//

#import <Foundation/Foundation.h>
#import "MCPTransport.h"

NS_ASSUME_NONNULL_BEGIN

/// Default socket path
extern NSString * const kMCPDefaultSocketPath;

@interface MCPSocketTransport : NSObject <MCPTransport>

@property (nonatomic, weak, nullable) id<MCPTransportDelegate> delegate;
@property (nonatomic, readonly) BOOL isConnected;
@property (nonatomic, readonly) NSString *socketPath;

/// Initialize with custom socket path
- (instancetype)initWithSocketPath:(NSString *)path;

/// Initialize with default socket path (/tmp/mcpwa.sock)
- (instancetype)init;

@end

NS_ASSUME_NONNULL_END
