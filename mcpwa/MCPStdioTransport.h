//
//  MCPStdioTransport.h
//  mcpwa
//
//  Stdio-based transport for MCP server (legacy mode for MCP Inspector)
//

#import <Foundation/Foundation.h>
#import "MCPTransport.h"

NS_ASSUME_NONNULL_BEGIN

@interface MCPStdioTransport : NSObject <MCPTransport>

@property (nonatomic, weak, nullable) id<MCPTransportDelegate> delegate;
@property (nonatomic, readonly) BOOL isConnected;

@end

NS_ASSUME_NONNULL_END
