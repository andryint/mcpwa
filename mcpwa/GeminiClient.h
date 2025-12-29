//
//  GeminiClient.h
//  mcpwa
//
//  Gemini API client with function calling support for MCP tools
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Message roles
typedef NS_ENUM(NSInteger, GeminiRole) {
    GeminiRoleUser,
    GeminiRoleModel,
    GeminiRoleFunction
};

// Message object for conversation history
@interface GeminiMessage : NSObject
@property (nonatomic, assign) GeminiRole role;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy, nullable) NSString *functionName;
@property (nonatomic, copy, nullable) NSDictionary *functionArgs;
@property (nonatomic, copy, nullable) NSString *functionResult;

+ (instancetype)userMessage:(NSString *)text;
+ (instancetype)modelMessage:(NSString *)text;
+ (instancetype)functionCall:(NSString *)name args:(NSDictionary *)args;
+ (instancetype)functionResult:(NSString *)name result:(NSString *)result;
@end

// Function call request from Gemini
@interface GeminiFunctionCall : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSDictionary *args;
@end

// Chat response from Gemini
@interface GeminiChatResponse : NSObject
@property (nonatomic, copy, nullable) NSString *text;
@property (nonatomic, strong, nullable) NSArray<GeminiFunctionCall *> *functionCalls;
@property (nonatomic, assign) BOOL hasFunctionCalls;
@property (nonatomic, copy, nullable) NSString *error;
@end

// Delegate for streaming responses and function calls
@protocol GeminiClientDelegate <NSObject>
@optional
- (void)geminiClient:(id)client didReceivePartialResponse:(NSString *)text;
- (void)geminiClient:(id)client didCompleteSendWithResponse:(GeminiChatResponse *)response;
- (void)geminiClient:(id)client didFailWithError:(NSError *)error;
- (void)geminiClient:(id)client didRequestFunctionCall:(GeminiFunctionCall *)call;
@end

// Main Gemini client
@interface GeminiClient : NSObject

@property (nonatomic, weak, nullable) id<GeminiClientDelegate> delegate;
@property (nonatomic, copy, readonly) NSString *apiKey;
@property (nonatomic, copy) NSString *model;
@property (nonatomic, strong, readonly) NSMutableArray<GeminiMessage *> *conversationHistory;
@property (nonatomic, assign) BOOL enableFunctionCalling;

// Initialization
- (instancetype)initWithAPIKey:(NSString *)apiKey;

// Load API key from environment or config
+ (nullable NSString *)loadAPIKey;

// Configure MCP tools as functions
- (void)configureMCPTools:(NSArray<NSDictionary *> *)tools;

// Send message (async with delegate callbacks)
- (void)sendMessage:(NSString *)message;

// Send function result back to continue the conversation
- (void)sendFunctionResult:(NSString *)functionName result:(NSString *)result;

// Clear conversation history
- (void)clearHistory;

// Cancel any in-progress request
- (void)cancelRequest;

@end

NS_ASSUME_NONNULL_END
