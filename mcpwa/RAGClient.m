//
//  RAGClient.m
//  mcpwa
//
//  RAG API client for querying external RAG service
//

#import "RAGClient.h"
#import "WALogger.h"

#pragma mark - RAGQueryResponse

@implementation RAGQueryResponse
@end

#pragma mark - RAGSearchResult

@implementation RAGSearchResult
@end

#pragma mark - RAGChatItem

@implementation RAGChatItem
@end

#pragma mark - RAGModelItem

@implementation RAGModelItem
@end

#pragma mark - RAGClient

@interface RAGClient () <NSURLSessionDataDelegate>
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong, nullable) NSURLSessionDataTask *currentTask;
@property (nonatomic, strong) NSMutableString *streamBuffer;
@property (nonatomic, strong) NSMutableString *accumulatedResponse;
@property (nonatomic, strong, nullable) NSHTTPURLResponse *pendingErrorResponse;
@property (nonatomic, assign) BOOL streamCompleted;
@end

@implementation RAGClient

- (instancetype)initWithBaseURL:(NSString *)baseURL {
    self = [super init];
    if (self) {
        // Remove trailing slash if present
        if ([baseURL hasSuffix:@"/"]) {
            baseURL = [baseURL substringToIndex:baseURL.length - 1];
        }
        _baseURL = [baseURL copy];
        _streamBuffer = [NSMutableString string];
        _accumulatedResponse = [NSMutableString string];

        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 60.0;
        config.timeoutIntervalForResource = 120.0;
        // Use a background queue for delegate callbacks to avoid blocking main thread
        // UI updates will dispatch to main queue explicitly
        NSOperationQueue *delegateQueue = [[NSOperationQueue alloc] init];
        delegateQueue.name = @"RAGClient.delegateQueue";
        delegateQueue.maxConcurrentOperationCount = 1;
        _session = [NSURLSession sessionWithConfiguration:config
                                                 delegate:self
                                            delegateQueue:delegateQueue];
    }
    return self;
}

#pragma mark - Configuration

+ (nullable NSString *)loadRAGURL {
    // First check NSUserDefaults
    NSString *url = [[NSUserDefaults standardUserDefaults] stringForKey:@"RAGServiceURL"];
    if (url.length > 0) {
        return url;
    }

    // Then check config.json
    NSString *configPath = [@"~/Library/Application Support/mcpwa/config.json" stringByExpandingTildeInPath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:configPath]) {
        NSData *data = [NSData dataWithContentsOfFile:configPath];
        if (data) {
            NSError *error;
            NSDictionary *config = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
            if (!error && [config isKindOfClass:[NSDictionary class]]) {
                NSString *configURL = config[@"ragServiceURL"];
                if ([configURL isKindOfClass:[NSString class]] && configURL.length > 0) {
                    return configURL;
                }
            }
        }
    }

    // Default URL
    return @"http://localhost:8000";
}

+ (void)saveRAGURL:(NSString *)url {
    [[NSUserDefaults standardUserDefaults] setObject:url forKey:@"RAGServiceURL"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - Health Check

- (void)checkHealthWithCompletion:(void(^)(BOOL available, NSString * _Nullable error))completion {
    NSString *urlString = [NSString stringWithFormat:@"%@/health", self.baseURL];
    NSURL *url = [NSURL URLWithString:urlString];

    if (!url) {
        completion(NO, @"Invalid URL");
        return;
    }

    NSURLRequest *request = [NSURLRequest requestWithURL:url];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            completion(NO, error.localizedDescription);
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode == 200) {
            completion(YES, nil);
        } else {
            completion(NO, [NSString stringWithFormat:@"HTTP %ld", (long)httpResponse.statusCode]);
        }
    }];
    [task resume];
}

#pragma mark - Query

- (void)query:(NSString *)prompt {
    [self query:prompt k:0 chatFilter:0 model:nil systemPrompt:nil];
}

- (void)query:(NSString *)prompt k:(NSInteger)k chatFilter:(NSInteger)chatFilter model:(NSString *)model systemPrompt:(NSString *)systemPrompt {
    [WALogger info:@"[RAG] Query: %@", prompt];

    NSString *urlString = [NSString stringWithFormat:@"%@/query", self.baseURL];
    NSURL *url = [NSURL URLWithString:urlString];

    if (!url) {
        [self notifyError:@"Invalid URL"];
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    // Build request body according to API spec
    NSMutableDictionary *body = [NSMutableDictionary dictionaryWithObject:prompt forKey:@"prompt"];
    if (k > 0) {
        body[@"k"] = @(k);
    }
    if (chatFilter > 0) {
        body[@"chat_filter"] = @(chatFilter);
    }
    if (model.length > 0) {
        body[@"model"] = model;
    }
    if (systemPrompt.length > 0) {
        body[@"system_prompt"] = systemPrompt;
    }

    NSError *jsonError;
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];

    if (jsonError) {
        [self notifyError:jsonError.localizedDescription];
        return;
    }

    self.currentTask = [self.session dataTaskWithRequest:request
                                       completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            [self notifyError:error.localizedDescription];
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            [self handleHTTPError:httpResponse data:data];
            return;
        }

        [self parseQueryResponse:data];
    }];
    [self.currentTask resume];
}

- (void)parseQueryResponse:(NSData *)data {
    NSError *error;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];

    if (error) {
        [self notifyError:error.localizedDescription];
        return;
    }

    RAGQueryResponse *response = [[RAGQueryResponse alloc] init];
    response.answer = json[@"answer"];
    response.sources = json[@"sources"];
    response.model = json[@"model"];

    [WALogger info:@"[RAG] Query completed, answer length: %lu, model: %@", (unsigned long)response.answer.length, response.model];

    if ([self.delegate respondsToSelector:@selector(ragClient:didCompleteQueryWithResponse:)]) {
        [self.delegate ragClient:self didCompleteQueryWithResponse:response];
    }
}

#pragma mark - Streaming Query

- (void)queryStream:(NSString *)prompt {
    [self queryStream:prompt k:0 chatFilter:0 model:nil systemPrompt:nil];
}

- (void)queryStream:(NSString *)prompt k:(NSInteger)k chatFilter:(NSInteger)chatFilter model:(NSString *)model systemPrompt:(NSString *)systemPrompt {
    [WALogger info:@"[RAG] Stream query: %@", prompt];

    [self.streamBuffer setString:@""];
    [self.accumulatedResponse setString:@""];
    self.streamCompleted = NO;

    NSString *urlString = [NSString stringWithFormat:@"%@/query/stream", self.baseURL];
    NSURL *url = [NSURL URLWithString:urlString];

    if (!url) {
        [self notifyError:@"Invalid URL"];
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"text/event-stream" forHTTPHeaderField:@"Accept"];

    // Build request body according to API spec
    NSMutableDictionary *body = [NSMutableDictionary dictionaryWithObject:prompt forKey:@"prompt"];
    if (k > 0) {
        body[@"k"] = @(k);
    }
    if (chatFilter > 0) {
        body[@"chat_filter"] = @(chatFilter);
    }
    if (model.length > 0) {
        body[@"model"] = model;
    }
    if (systemPrompt.length > 0) {
        body[@"system_prompt"] = systemPrompt;
    }

    NSError *jsonError;
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];

    if (jsonError) {
        [self notifyError:jsonError.localizedDescription];
        return;
    }

    // Use delegate-based task for streaming
    self.currentTask = [self.session dataTaskWithRequest:request];
    [self.currentTask resume];
}

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

    if (httpResponse.statusCode != 200) {
        // For non-200 responses, allow data to come through so we can parse the error
        self.pendingErrorResponse = httpResponse;
        completionHandler(NSURLSessionResponseAllow);
    } else {
        self.pendingErrorResponse = nil;
        completionHandler(NSURLSessionResponseAllow);
    }
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    // Check if this is an error response
    if (self.pendingErrorResponse) {
        [self handleHTTPError:self.pendingErrorResponse data:data];
        self.pendingErrorResponse = nil;
        [self.currentTask cancel];
        return;
    }

    NSString *chunk = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!chunk) return;

    [WALogger debug:@"[RAG] SSE raw chunk: %@", chunk];
    [self.streamBuffer appendString:chunk];

    // Process SSE events
    [self processSSEBuffer];
}

- (void)processSSEBuffer {
    // Standard SSE format: events are separated by \n\n (double newline)
    // Each event contains lines like "data: <content>"
    // See: https://html.spec.whatwg.org/multipage/server-sent-events.html
    NSString *buffer = self.streamBuffer;

    [WALogger debug:@"[RAG] processSSEBuffer called, buffer length: %lu", (unsigned long)buffer.length];

    while (YES) {
        // Look for event boundary (double newline)
        NSRange eventEnd = [buffer rangeOfString:@"\n\n"];

        if (eventEnd.location == NSNotFound) {
            // No complete event yet
            [WALogger debug:@"[RAG] No \\n\\n found, waiting for more data. Buffer: %@",
                [buffer stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"]];
            break;
        }

        // Extract the event
        NSString *event = [buffer substringToIndex:eventEnd.location];
        buffer = [buffer substringFromIndex:eventEnd.location + 2];
        [self.streamBuffer setString:buffer];

        // Parse data lines from the event
        NSMutableString *dataContent = [NSMutableString string];
        NSArray *lines = [event componentsSeparatedByString:@"\n"];

        for (NSString *line in lines) {
            if ([line hasPrefix:@"data: "]) {
                if (dataContent.length > 0) [dataContent appendString:@"\n"];
                [dataContent appendString:[line substringFromIndex:6]];
            } else if ([line hasPrefix:@"data:"]) {
                if (dataContent.length > 0) [dataContent appendString:@"\n"];
                [dataContent appendString:[line substringFromIndex:5]];
            }
            // Ignore event:, id:, retry:, and comments (:)
        }

        if (dataContent.length > 0) {
            [WALogger debug:@"[RAG] Extracted event data: %@", dataContent];
            [self parseSSEEvent:dataContent];
        } else {
            [WALogger debug:@"[RAG] Event had no data content"];
        }
    }
}

- (void)parseSSEEvent:(NSString *)eventData {
    // All events are now JSON with a "type" field:
    // - {"type": "chunk", "text": "..."} - text fragments
    // - {"type": "done", "model": "...", "sources": [...]} - final event
    // - {"type": "error", "error": "..."} - errors

    NSData *data = [eventData dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return;

    NSError *error;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];

    if (error || !json) {
        [WALogger error:@"[RAG] Failed to parse SSE event as JSON: %@", eventData];
        return;
    }

    NSString *type = json[@"type"];
    if (!type) {
        [WALogger error:@"[RAG] SSE event missing 'type' field: %@", eventData];
        return;
    }

    if ([type isEqualToString:@"status"]) {
        // Status update event - pipeline stage notification
        NSString *stage = json[@"stage"];
        NSString *message = json[@"message"];
        [WALogger info:@"[RAG] Status update - stage: %@, message: %@", stage, message];
        if ([self.delegate respondsToSelector:@selector(ragClient:didReceiveStatusUpdate:message:)]) {
            [self.delegate ragClient:self didReceiveStatusUpdate:stage message:message];
        }
    } else if ([type isEqualToString:@"chunk"]) {
        // Text chunk
        NSString *text = json[@"text"];
        if (text) {
            // Log decoded text - check if it contains literal \u escapes (not decoded)
            BOOL hasLiteralEscapes = [text containsString:@"\\u"];
            NSLog(@"[RAG] Chunk text (len=%lu, hasLiteralEscapes=%d): %@",
                  (unsigned long)text.length, hasLiteralEscapes, text);
            [self.accumulatedResponse appendString:text];
            if ([self.delegate respondsToSelector:@selector(ragClient:didReceiveStreamChunk:)]) {
                [self.delegate ragClient:self didReceiveStreamChunk:text];
            }
        }
    } else if ([type isEqualToString:@"done"]) {
        // Final event with sources
        [WALogger info:@"[RAG] Received 'done' event, sources count: %lu, model: %@",
            (unsigned long)[json[@"sources"] count], json[@"model"]];
        self.streamCompleted = YES;
        RAGQueryResponse *response = [[RAGQueryResponse alloc] init];
        response.answer = [self.accumulatedResponse copy];
        response.sources = json[@"sources"];
        response.model = json[@"model"];

        if ([self.delegate respondsToSelector:@selector(ragClient:didCompleteQueryWithResponse:)]) {
            [WALogger info:@"[RAG] Calling delegate didCompleteQueryWithResponse"];
            [self.delegate ragClient:self didCompleteQueryWithResponse:response];
        }
    } else if ([type isEqualToString:@"error"]) {
        // Error event
        [WALogger info:@"[RAG] Received 'error' event: %@", json[@"error"]];
        self.streamCompleted = YES;
        [self notifyError:json[@"error"] ?: @"Unknown error"];
    } else {
        [WALogger info:@"[RAG] Unknown event type: %@", type];
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    [WALogger info:@"[RAG] URLSession didCompleteWithError called, error: %@", error];

    if (error) {
        // Check if it was cancelled
        if (error.code == NSURLErrorCancelled) {
            [WALogger info:@"[RAG] Request was cancelled"];
            return;
        }
        [WALogger info:@"[RAG] Request failed with error: %@", error.localizedDescription];
        [self notifyError:error.localizedDescription];
    } else {
        // Connection completed successfully - process any remaining buffer
        [WALogger info:@"[RAG] Stream connection completed successfully"];
        [WALogger info:@"[RAG] Buffer remaining: '%@'", self.streamBuffer];
        [WALogger info:@"[RAG] Accumulated response length: %lu", (unsigned long)self.accumulatedResponse.length];
        [WALogger info:@"[RAG] Stream completed flag: %@", self.streamCompleted ? @"YES" : @"NO"];

        // Process any remaining data in buffer (server may not have sent final \n\n)
        if (self.streamBuffer.length > 0 && !self.streamCompleted) {
            [WALogger info:@"[RAG] Processing remaining buffer as final event"];
            // Add \n\n to force processing of remaining data
            [self.streamBuffer appendString:@"\n\n"];
            [self processSSEBuffer];
        }

        // If we have accumulated response but didn't get a "done" event, finalize it
        if (!self.streamCompleted && self.accumulatedResponse.length > 0) {
            [WALogger info:@"[RAG] Finalizing stream without done event, answer length: %lu", (unsigned long)self.accumulatedResponse.length];
            self.streamCompleted = YES;
            RAGQueryResponse *response = [[RAGQueryResponse alloc] init];
            response.answer = [self.accumulatedResponse copy];

            if ([self.delegate respondsToSelector:@selector(ragClient:didCompleteQueryWithResponse:)]) {
                [WALogger info:@"[RAG] Calling delegate didCompleteQueryWithResponse (fallback)"];
                [self.delegate ragClient:self didCompleteQueryWithResponse:response];
            } else {
                [WALogger info:@"[RAG] Delegate does not respond to didCompleteQueryWithResponse!"];
            }
        } else if (self.streamCompleted) {
            [WALogger info:@"[RAG] Stream was already completed via done event"];
        } else {
            [WALogger info:@"[RAG] No accumulated response to finalize"];
        }
    }
}

#pragma mark - Search

- (void)search:(NSString *)query k:(NSInteger)k chatFilter:(NSInteger)chatFilter {
    [WALogger info:@"[RAG] Search: %@", query];

    NSString *urlString = [NSString stringWithFormat:@"%@/search", self.baseURL];
    NSURL *url = [NSURL URLWithString:urlString];

    if (!url) {
        [self notifyError:@"Invalid URL"];
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    // Build request body according to API spec
    NSMutableDictionary *body = [NSMutableDictionary dictionaryWithObject:query forKey:@"query"];
    if (k > 0) {
        body[@"k"] = @(k);
    }
    if (chatFilter > 0) {
        body[@"chat_filter"] = @(chatFilter);
    }

    NSError *jsonError;
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];

    if (jsonError) {
        [self notifyError:jsonError.localizedDescription];
        return;
    }

    self.currentTask = [self.session dataTaskWithRequest:request
                                       completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            [self notifyError:error.localizedDescription];
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            [self handleHTTPError:httpResponse data:data];
            return;
        }

        [self parseSearchResponse:data];
    }];
    [self.currentTask resume];
}

- (void)parseSearchResponse:(NSData *)data {
    NSError *error;
    // API returns array directly, not wrapped in object
    NSArray *jsonArray = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];

    if (error) {
        [self notifyError:error.localizedDescription];
        return;
    }

    RAGSearchResult *result = [[RAGSearchResult alloc] init];
    if ([jsonArray isKindOfClass:[NSArray class]]) {
        result.results = jsonArray;
    } else {
        // Fallback if response is wrapped in object
        NSDictionary *dict = (NSDictionary *)jsonArray;
        result.results = dict[@"results"];
    }

    [WALogger info:@"[RAG] Search completed, results: %lu", (unsigned long)result.results.count];

    if ([self.delegate respondsToSelector:@selector(ragClient:didCompleteSearchWithResponse:)]) {
        [self.delegate ragClient:self didCompleteSearchWithResponse:result];
    }
}

#pragma mark - List Chats

- (void)listChatsWithCompletion:(void(^)(NSArray<RAGChatItem *> * _Nullable chats, NSString * _Nullable error))completion {
    NSString *urlString = [NSString stringWithFormat:@"%@/chats", self.baseURL];
    NSURL *url = [NSURL URLWithString:urlString];

    if (!url) {
        completion(nil, @"Invalid URL");
        return;
    }

    NSURLRequest *request = [NSURLRequest requestWithURL:url];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            completion(nil, error.localizedDescription);
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            completion(nil, [NSString stringWithFormat:@"HTTP %ld", (long)httpResponse.statusCode]);
            return;
        }

        NSError *jsonError;
        NSArray *jsonArray = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];

        if (jsonError || ![jsonArray isKindOfClass:[NSArray class]]) {
            completion(nil, @"Invalid response format");
            return;
        }

        NSMutableArray<RAGChatItem *> *chats = [NSMutableArray array];
        for (NSDictionary *item in jsonArray) {
            if (![item isKindOfClass:[NSDictionary class]]) continue;

            RAGChatItem *chat = [[RAGChatItem alloc] init];
            // Parse according to API ChatInfo response
            chat.chatId = [item[@"id"] integerValue];
            chat.name = item[@"name"];
            chat.isGroup = [item[@"is_group"] boolValue];
            chat.messageCount = [item[@"message_count"] integerValue];
            chat.participants = item[@"participants"];
            [chats addObject:chat];
        }

        [WALogger info:@"[RAG] Listed %lu chats", (unsigned long)chats.count];
        completion(chats, nil);
    }];
    [task resume];
}

#pragma mark - List Models

- (void)listModelsWithCompletion:(void(^)(NSArray<RAGModelItem *> * _Nullable models, NSString * _Nullable error))completion {
    NSString *urlString = [NSString stringWithFormat:@"%@/models", self.baseURL];
    NSURL *url = [NSURL URLWithString:urlString];

    if (!url) {
        completion(nil, @"Invalid URL");
        return;
    }

    NSURLRequest *request = [NSURLRequest requestWithURL:url];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            completion(nil, error.localizedDescription);
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            completion(nil, [NSString stringWithFormat:@"HTTP %ld", (long)httpResponse.statusCode]);
            return;
        }

        NSError *jsonError;
        NSDictionary *jsonDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];

        if (jsonError || ![jsonDict isKindOfClass:[NSDictionary class]]) {
            completion(nil, @"Invalid response format");
            return;
        }

        // Parse models array from response
        NSArray *modelsArray = jsonDict[@"models"];
        if (![modelsArray isKindOfClass:[NSArray class]]) {
            completion(nil, @"Missing models array in response");
            return;
        }

        NSMutableArray<RAGModelItem *> *models = [NSMutableArray array];
        for (NSDictionary *item in modelsArray) {
            if (![item isKindOfClass:[NSDictionary class]]) continue;

            RAGModelItem *model = [[RAGModelItem alloc] init];
            model.modelId = item[@"id"];
            model.name = item[@"name"];
            model.provider = item[@"provider"];
            if (model.modelId && model.name) {
                [models addObject:model];
            }
        }

        [WALogger info:@"[RAG] Listed %lu models", (unsigned long)models.count];
        completion(models, nil);
    }];
    [task resume];
}

#pragma mark - Cancel

- (void)cancelRequest {
    [self.currentTask cancel];
    self.currentTask = nil;
    [self.streamBuffer setString:@""];
    [self.accumulatedResponse setString:@""];
}

#pragma mark - Helpers

- (void)handleHTTPError:(NSHTTPURLResponse *)response data:(NSData *)data {
    NSInteger statusCode = response.statusCode;
    NSString *errorMessage = nil;

    // Try to parse error details from response body
    if (data.length > 0) {
        NSError *parseError;
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];

        if (!parseError && [json isKindOfClass:[NSDictionary class]]) {
            NSDictionary *errorDict = (NSDictionary *)json;

            // FastAPI validation error format
            if (errorDict[@"detail"]) {
                id detail = errorDict[@"detail"];
                if ([detail isKindOfClass:[NSString class]]) {
                    errorMessage = detail;
                } else if ([detail isKindOfClass:[NSArray class]]) {
                    // FastAPI returns validation errors as array of objects
                    NSMutableArray *messages = [NSMutableArray array];
                    for (NSDictionary *err in detail) {
                        NSString *loc = [err[@"loc"] componentsJoinedByString:@"."];
                        NSString *msg = err[@"msg"];
                        if (loc && msg) {
                            [messages addObject:[NSString stringWithFormat:@"%@: %@", loc, msg]];
                        } else if (msg) {
                            [messages addObject:msg];
                        }
                    }
                    if (messages.count > 0) {
                        errorMessage = [messages componentsJoinedByString:@"; "];
                    }
                }
            }
            // Generic error format
            else if (errorDict[@"error"]) {
                errorMessage = errorDict[@"error"];
            }
            else if (errorDict[@"message"]) {
                errorMessage = errorDict[@"message"];
            }
        }

        // If JSON parsing failed, try to use raw string
        if (!errorMessage) {
            NSString *rawBody = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (rawBody.length > 0 && rawBody.length < 500) {
                errorMessage = rawBody;
            }
        }
    }

    // Build final error message
    NSString *finalMessage;
    if (errorMessage) {
        finalMessage = [NSString stringWithFormat:@"HTTP %ld: %@", (long)statusCode, errorMessage];
    } else {
        finalMessage = [NSString stringWithFormat:@"HTTP %ld", (long)statusCode];
    }

    [WALogger error:@"[RAG] HTTP Error: %@", finalMessage];
    [self notifyError:finalMessage];
}

- (void)notifyError:(NSString *)message {
    [WALogger error:@"[RAG] Error: %@", message];

    NSError *error = [NSError errorWithDomain:@"RAGClientError"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: message}];

    if ([self.delegate respondsToSelector:@selector(ragClient:didFailWithError:)]) {
        [self.delegate ragClient:self didFailWithError:error];
    }
}

@end
