
#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@protocol MCPServerDelegate <NSObject>
- (void)appendLog:(NSString *)message;
- (void)appendLog:(NSString *)message color:(NSColor *)color;
@end

@interface MCPServer : NSObject

@property (nonatomic, weak, nullable) id<MCPServerDelegate> delegate;

- (instancetype)initWithDelegate:(nullable id<MCPServerDelegate>)delegate;

/// Start the MCP server on a background thread
- (void)start;

/// Stop the MCP server
- (void)stop;

/// Check if server is running
@property (nonatomic, readonly) BOOL isRunning;

@end

NS_ASSUME_NONNULL_END
