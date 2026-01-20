//
//  RAGClient.h
//  mcpwa
//
//  RAG API client for querying external RAG service
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// RAG query response with answer and sources
@interface RAGQueryResponse : NSObject
@property (nonatomic, copy, nullable) NSString *answer;
@property (nonatomic, strong, nullable) NSArray<NSDictionary *> *sources;
@property (nonatomic, copy, nullable) NSString *model;
@property (nonatomic, copy, nullable) NSString *error;
@end

/// RAG search result (semantic search without LLM)
@interface RAGSearchResult : NSObject
@property (nonatomic, strong, nullable) NSArray<NSDictionary *> *results;
@property (nonatomic, copy, nullable) NSString *error;
@end

/// RAG chat item (matches API ChatInfo response)
@interface RAGChatItem : NSObject
@property (nonatomic, assign) NSInteger chatId;
@property (nonatomic, copy, nullable) NSString *name;
@property (nonatomic, assign) BOOL isGroup;
@property (nonatomic, assign) NSInteger messageCount;
@property (nonatomic, strong, nullable) NSArray<NSString *> *participants;
@end

/// RAG model item (matches API ModelInfo response)
@interface RAGModelItem : NSObject
@property (nonatomic, copy) NSString *modelId;      // API "id" field
@property (nonatomic, copy) NSString *name;         // Display name
@property (nonatomic, copy) NSString *provider;     // Provider (gemini, anthropic, openai)
@end

/// Delegate for RAG client callbacks
@protocol RAGClientDelegate <NSObject>
@optional
- (void)ragClient:(id)client didReceiveStreamChunk:(NSString *)chunk;
- (void)ragClient:(id)client didReceiveStatusUpdate:(NSString *)stage message:(NSString *)message;
- (void)ragClient:(id)client didCompleteQueryWithResponse:(RAGQueryResponse *)response;
- (void)ragClient:(id)client didCompleteSearchWithResponse:(RAGSearchResult *)response;
- (void)ragClient:(id)client didFailWithError:(NSError *)error;
@end

/// RAG API client
@interface RAGClient : NSObject

@property (nonatomic, weak, nullable) id<RAGClientDelegate> delegate;
@property (nonatomic, copy) NSString *baseURL;

/// Initialize with base URL
- (instancetype)initWithBaseURL:(NSString *)baseURL;

/// Load RAG URL from config
+ (nullable NSString *)loadRAGURL;

/// Save RAG URL to config
+ (void)saveRAGURL:(NSString *)url;

/// Health check - returns YES if service is available
- (void)checkHealthWithCompletion:(void(^)(BOOL available, NSString * _Nullable error))completion;

/// Query RAG service (non-streaming)
/// @param prompt User's question or prompt
/// @param k Number of context chunks to retrieve (1-50, default 5)
/// @param chatFilter Optional chat_id filter (pass 0 for no filter)
/// @param model Optional Gemini model (pass nil for default)
/// @param systemPrompt Optional custom system prompt (pass nil for default)
- (void)query:(NSString *)prompt k:(NSInteger)k chatFilter:(NSInteger)chatFilter model:(nullable NSString *)model systemPrompt:(nullable NSString *)systemPrompt;

/// Query RAG service with streaming (SSE)
/// @param prompt User's question or prompt
/// @param k Number of context chunks to retrieve (1-50, default 5)
/// @param chatFilter Optional chat_id filter (pass 0 for no filter)
/// @param model Optional Gemini model (pass nil for default)
/// @param systemPrompt Optional custom system prompt (pass nil for default)
- (void)queryStream:(NSString *)prompt k:(NSInteger)k chatFilter:(NSInteger)chatFilter model:(nullable NSString *)model systemPrompt:(nullable NSString *)systemPrompt;

/// Simple query with defaults (non-streaming)
- (void)query:(NSString *)prompt;

/// Simple query with defaults (streaming)
- (void)queryStream:(NSString *)prompt;

/// Semantic search without LLM
/// @param query Search query text
/// @param k Number of results (1-50, default 5)
/// @param chatFilter Optional chat_id filter (pass 0 for no filter)
- (void)search:(NSString *)query k:(NSInteger)k chatFilter:(NSInteger)chatFilter;

/// List all chats
- (void)listChatsWithCompletion:(void(^)(NSArray<RAGChatItem *> * _Nullable chats, NSString * _Nullable error))completion;

/// List available models from the server
- (void)listModelsWithCompletion:(void(^)(NSArray<RAGModelItem *> * _Nullable models, NSString * _Nullable error))completion;

/// Cancel any in-progress request
- (void)cancelRequest;

@end

NS_ASSUME_NONNULL_END
