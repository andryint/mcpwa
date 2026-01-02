//
//  GeminiClient.m
//  mcpwa
//
//  Gemini API client with function calling support for MCP tools
//

#import "GeminiClient.h"

static NSString * const kGeminiAPIBaseURL = @"https://generativelanguage.googleapis.com/v1beta/models";
static NSString * const kDefaultModel = @"gemini-3-pro-preview";

// Model constants
NSString * const kGeminiModel_2_0_Flash = @"gemini-2.0-flash-exp";
NSString * const kGeminiModel_2_5_Flash = @"gemini-2.5-flash-preview-05-20";
NSString * const kGeminiModel_2_5_Pro = @"gemini-2.5-pro-preview-05-06";
NSString * const kGeminiModel_3_0_Flash = @"gemini-3-flash-preview";
NSString * const kGeminiModel_3_0_Pro = @"gemini-3-pro-preview";

#pragma mark - GeminiMessage

@implementation GeminiMessage

+ (instancetype)userMessage:(NSString *)text {
    GeminiMessage *msg = [[GeminiMessage alloc] init];
    msg.role = GeminiRoleUser;
    msg.text = text;
    return msg;
}

+ (instancetype)modelMessage:(NSString *)text {
    GeminiMessage *msg = [[GeminiMessage alloc] init];
    msg.role = GeminiRoleModel;
    msg.text = text;
    return msg;
}

+ (instancetype)functionCall:(NSString *)name args:(NSDictionary *)args thoughtSignature:(NSString *)signature {
    GeminiMessage *msg = [[GeminiMessage alloc] init];
    msg.role = GeminiRoleModel;
    msg.functionName = name;
    msg.functionArgs = args;
    msg.thoughtSignature = signature;
    return msg;
}

+ (instancetype)functionResult:(NSString *)name result:(NSString *)result {
    GeminiMessage *msg = [[GeminiMessage alloc] init];
    msg.role = GeminiRoleFunction;
    msg.functionName = name;
    msg.functionResult = result;
    return msg;
}

@end

#pragma mark - GeminiFunctionCall

@implementation GeminiFunctionCall
@end

#pragma mark - GeminiChatResponse

@implementation GeminiChatResponse

- (BOOL)hasFunctionCalls {
    return self.functionCalls.count > 0;
}

@end

#pragma mark - GeminiClient

static const NSInteger kMaxToolLoopIterations = 20; // Safety limit to prevent infinite loops

@interface GeminiClient ()
@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, strong) NSMutableArray<GeminiMessage *> *conversationHistory;
@property (nonatomic, strong) NSArray<NSDictionary *> *mcpToolDefinitions;
@property (nonatomic, strong) NSURLSessionDataTask *currentTask;
@property (nonatomic, assign) NSInteger toolLoopIterations;
@end

@implementation GeminiClient

- (instancetype)initWithAPIKey:(NSString *)apiKey {
    self = [super init];
    if (self) {
        _apiKey = [apiKey copy];
        _model = kDefaultModel;
        _conversationHistory = [NSMutableArray array];
        _mcpToolDefinitions = @[];
        _enableFunctionCalling = YES;
    }
    return self;
}

+ (nullable NSString *)loadAPIKey {
    // 1. Check environment variable
    NSString *envKey = [[NSProcessInfo processInfo] environment][@"GEMINI_API_KEY"];
    if (envKey.length > 0) {
        return envKey;
    }

    // 2. Check user defaults
    NSString *defaultsKey = [[NSUserDefaults standardUserDefaults] stringForKey:@"GeminiAPIKey"];
    if (defaultsKey.length > 0) {
        return defaultsKey;
    }

    // 3. Check config file in app support
    NSString *configPath = [NSHomeDirectory() stringByAppendingPathComponent:
        @"Library/Application Support/mcpwa/config.json"];
    NSData *data = [NSData dataWithContentsOfFile:configPath];
    if (data) {
        NSDictionary *config = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *fileKey = config[@"geminiApiKey"];
        if (fileKey.length > 0) {
            return fileKey;
        }
    }

    return nil;
}

+ (NSArray<NSString *> *)availableModels {
    return @[
        kGeminiModel_3_0_Flash,
        kGeminiModel_3_0_Pro,
        kGeminiModel_2_5_Flash,
        kGeminiModel_2_5_Pro,
        kGeminiModel_2_0_Flash
    ];
}

+ (NSString *)displayNameForModel:(NSString *)modelId {
    if ([modelId isEqualToString:kGeminiModel_3_0_Flash]) {
        return @"Gemini 3.0 Flash";
    } else if ([modelId isEqualToString:kGeminiModel_3_0_Pro]) {
        return @"Gemini 3.0 Pro";
    } else if ([modelId isEqualToString:kGeminiModel_2_5_Flash]) {
        return @"Gemini 2.5 Flash";
    } else if ([modelId isEqualToString:kGeminiModel_2_5_Pro]) {
        return @"Gemini 2.5 Pro";
    } else if ([modelId isEqualToString:kGeminiModel_2_0_Flash]) {
        return @"Gemini 2.0 Flash";
    }
    return modelId;
}

- (void)configureMCPTools:(NSArray<NSDictionary *> *)tools {
    // Convert MCP tool definitions to Gemini function declarations format
    NSMutableArray *geminiTools = [NSMutableArray array];

    for (NSDictionary *tool in tools) {
        NSDictionary *inputSchema = tool[@"inputSchema"];

        // Convert MCP inputSchema to Gemini parameters format
        NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
        parameters[@"type"] = @"object";

        NSDictionary *properties = inputSchema[@"properties"];
        if (properties) {
            parameters[@"properties"] = properties;
        }

        NSArray *required = inputSchema[@"required"];
        if (required) {
            parameters[@"required"] = required;
        }

        NSDictionary *functionDeclaration = @{
            @"name": tool[@"name"],
            @"description": tool[@"description"] ?: @"",
            @"parameters": parameters
        };

        [geminiTools addObject:functionDeclaration];
    }

    self.mcpToolDefinitions = geminiTools;
}

- (void)sendMessage:(NSString *)message {
    // Add user message to history
    [self.conversationHistory addObject:[GeminiMessage userMessage:message]];

    // Reset tool loop counter for new message
    self.toolLoopIterations = 0;

    [self sendRequestWithFunctionResult:nil];
}

- (void)sendFunctionResult:(NSString *)functionName result:(NSString *)result {
    // Add function result to history
    [self.conversationHistory addObject:[GeminiMessage functionResult:functionName result:result]];

    [self sendRequestWithFunctionResult:@{
        @"name": functionName,
        @"response": @{
            @"name": functionName,
            @"content": result
        }
    }];
}

- (void)sendRequestWithFunctionResult:(NSDictionary * _Nullable)functionResponse {
    NSString *urlString = [NSString stringWithFormat:@"%@/%@:generateContent?key=%@",
                           kGeminiAPIBaseURL, self.model, self.apiKey];

    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    // Build request body
    NSMutableDictionary *body = [NSMutableDictionary dictionary];

    // Add system instruction
    body[@"toolConfig"] = @{
        @"functionCallingConfig": @{
            @"mode": @"AUTO"
        }
    };
    
    body[@"systemInstruction"] = @{
        @"parts": @[@{
            @"text": @"<ROLE>\n"
                     "You are a Grounded WhatsApp Assistant. You interact with the user's real-time data strictly via MCP tools.\n"
                     "</ROLE>\n\n"
                     
                     "<PROTOCOLS>\n"
                     "1. SESSION_FLOW: You MUST execute `whatsapp_start_session` before any data request. You MUST execute `whatsapp_stop_session` after your final response.\n"
                     "2. SOURCE_OF_TRUTH: Your ONLY source of information is the raw output from a successful tool call. If the tool has not been called or returned an error, you have NO information.\n"
                     "3. NO_SIMULATION: Never generate text that mimics a tool output (e.g., JSON blocks, lists of chats). You must wait for the actual system to provide the tool result.\n"
                     "4. ERROR_REPORTING: If a tool returns 'empty', 'null', or an error, state: \"I couldn't find any information in your WhatsApp for that request.\"\n"
                     "</PROTOCOLS>\n\n"
                     
                     "<CONSTRAINTS>\n"
                     "1. NEVER invent contact names, message content, or group titles. \n"
                     "2. NEVER use placeholder data or 'example' chats to fill a response.\n"
                     "3. Use external knowledge ONLY to provide context for existing chat data (e.g., explaining a link found in a message), never to supplement missing data.\n"
                     "</CONSTRAINTS>\n\n"
                     
                     "<STYLE>\n"
                     "Be concise, technical, and strictly factual. Use bullet points for chat lists only when data is verified.\n"
                     "</STYLE>"
        }]
    };
    
    // Build contents array from conversation history
    NSMutableArray *contents = [NSMutableArray array];

    for (GeminiMessage *msg in self.conversationHistory) {
        NSMutableDictionary *content = [NSMutableDictionary dictionary];

        switch (msg.role) {
            case GeminiRoleUser:
                content[@"role"] = @"user";
                content[@"parts"] = @[@{@"text": msg.text}];
                break;

            case GeminiRoleModel:
                content[@"role"] = @"model";
                if (msg.functionName) {
                    // Function call from model - include thoughtSignature for Gemini 3.0+
                    NSMutableDictionary *functionCallPart = [NSMutableDictionary dictionary];
                    functionCallPart[@"functionCall"] = @{
                        @"name": msg.functionName,
                        @"args": msg.functionArgs ?: @{}
                    };
                    if (msg.thoughtSignature) {
                        functionCallPart[@"thoughtSignature"] = msg.thoughtSignature;
                    }
                    content[@"parts"] = @[functionCallPart];
                } else {
                    content[@"parts"] = @[@{@"text": msg.text ?: @""}];
                }
                break;

            case GeminiRoleFunction:
                content[@"role"] = @"user";
                content[@"parts"] = @[@{
                    @"functionResponse": @{
                        @"name": msg.functionName,
                        @"response": @{
                            @"name": msg.functionName,
                            @"content": msg.functionResult ?: @""
                        }
                    }
                }];
                break;
        }

        [contents addObject:content];
    }

    body[@"contents"] = contents;

    // Add function calling tools (Google Search grounding cannot be combined with function calling)
    if (self.enableFunctionCalling && self.mcpToolDefinitions.count > 0) {
        body[@"tools"] = @[@{
            @"functionDeclarations": self.mcpToolDefinitions
        }];
    }

    // Generation config
    body[@"generationConfig"] = @{
        @"temperature": @0.7,
        @"maxOutputTokens": @8192
    };

    NSError *jsonError;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
    if (jsonError) {
        [self notifyError:[NSError errorWithDomain:@"GeminiClient"
                                              code:1
                                          userInfo:@{NSLocalizedDescriptionKey: @"Failed to serialize request"}]];
        return;
    }

    request.HTTPBody = jsonData;

    // Make request
    NSURLSession *session = [NSURLSession sharedSession];

    __weak typeof(self) weakSelf = self;
    self.currentTask = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        strongSelf.currentTask = nil;

        if (error) {
            [strongSelf notifyError:error];
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            NSString *errorBody = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSError *apiError = [NSError errorWithDomain:@"GeminiAPI"
                                                    code:httpResponse.statusCode
                                                userInfo:@{NSLocalizedDescriptionKey: errorBody ?: @"API error"}];
            [strongSelf notifyError:apiError];
            return;
        }

        [strongSelf parseResponse:data];
    }];

    [self.currentTask resume];
}

- (void)parseResponse:(NSData *)data {
    NSError *jsonError;
    NSDictionary *response = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];

    if (jsonError) {
        [self notifyError:jsonError];
        return;
    }

    GeminiChatResponse *chatResponse = [[GeminiChatResponse alloc] init];

    // Check for error in response
    NSDictionary *errorDict = response[@"error"];
    if (errorDict) {
        chatResponse.error = errorDict[@"message"] ?: @"Unknown error";
        [self notifyComplete:chatResponse];
        return;
    }

    // Parse candidates
    NSArray *candidates = response[@"candidates"];
    if (candidates.count == 0) {
        chatResponse.error = @"No response generated";
        [self notifyComplete:chatResponse];
        return;
    }

    NSDictionary *content = candidates[0][@"content"];
    NSArray *parts = content[@"parts"];

    NSMutableString *textBuilder = [NSMutableString string];
    NSMutableArray *functionCalls = [NSMutableArray array];

    for (NSDictionary *part in parts) {
        // Check for text response
        NSString *text = part[@"text"];
        if (text) {
            [textBuilder appendString:text];
        }

        // Check for function call
        NSDictionary *functionCall = part[@"functionCall"];
        if (functionCall) {
            GeminiFunctionCall *call = [[GeminiFunctionCall alloc] init];
            call.name = functionCall[@"name"];
            call.args = functionCall[@"args"] ?: @{};
            // Extract thoughtSignature for Gemini 3.0+ (it's at the part level, not inside functionCall)
            call.thoughtSignature = part[@"thoughtSignature"];
            [functionCalls addObject:call];

            // Add to conversation history with thoughtSignature
            [self.conversationHistory addObject:[GeminiMessage functionCall:call.name args:call.args thoughtSignature:call.thoughtSignature]];
        }
    }

    if (textBuilder.length > 0) {
        chatResponse.text = textBuilder;
        // Add model response to history
        [self.conversationHistory addObject:[GeminiMessage modelMessage:textBuilder]];
    }

    if (functionCalls.count > 0) {
        chatResponse.functionCalls = functionCalls;
    }

    [self notifyComplete:chatResponse];
}

- (void)clearHistory {
    [self.conversationHistory removeAllObjects];
}

- (void)cancelRequest {
    [self.currentTask cancel];
    self.currentTask = nil;
}

#pragma mark - Delegate Notification

- (void)notifyError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(geminiClient:didFailWithError:)]) {
            [self.delegate geminiClient:self didFailWithError:error];
        }
    });
}

- (void)notifyComplete:(GeminiChatResponse *)response {
    dispatch_async(dispatch_get_main_queue(), ^{
        // If we have a tool executor and there are function calls, handle the looping internally
        if (self.toolExecutor && response.hasFunctionCalls) {
            [self executeToolLoopWithResponse:response];
            return;
        }

        // If we have a tool executor and were in a tool loop, notify completion
        if (self.toolExecutor && self.toolLoopIterations > 0) {
            NSLog(@"[GeminiClient] Tool loop completed after %ld iterations with text response", (long)self.toolLoopIterations);
            if ([self.delegate respondsToSelector:@selector(geminiClient:didCompleteToolLoopWithResponse:)]) {
                [self.delegate geminiClient:self didCompleteToolLoopWithResponse:response];
            }
            return;
        }

        if ([self.delegate respondsToSelector:@selector(geminiClient:didCompleteSendWithResponse:)]) {
            [self.delegate geminiClient:self didCompleteSendWithResponse:response];
        }

        // Also notify about function calls (for backwards compatibility when toolExecutor is not set)
        if (response.hasFunctionCalls) {
            for (GeminiFunctionCall *call in response.functionCalls) {
                if ([self.delegate respondsToSelector:@selector(geminiClient:didRequestFunctionCall:)]) {
                    [self.delegate geminiClient:self didRequestFunctionCall:call];
                }
            }
        }
    });
}

#pragma mark - Tool Loop Execution

- (void)executeToolLoopWithResponse:(GeminiChatResponse *)response {
    self.toolLoopIterations++;

    // Safety check to prevent infinite loops
    if (self.toolLoopIterations > kMaxToolLoopIterations) {
        NSLog(@"[GeminiClient] Tool loop exceeded maximum iterations (%ld), stopping", (long)kMaxToolLoopIterations);
        GeminiChatResponse *errorResponse = [[GeminiChatResponse alloc] init];
        errorResponse.error = [NSString stringWithFormat:@"Tool loop exceeded maximum iterations (%ld)", (long)kMaxToolLoopIterations];
        if ([self.delegate respondsToSelector:@selector(geminiClient:didCompleteToolLoopWithResponse:)]) {
            [self.delegate geminiClient:self didCompleteToolLoopWithResponse:errorResponse];
        }
        return;
    }

    NSLog(@"[GeminiClient] Tool loop iteration %ld, processing %lu function calls",
          (long)self.toolLoopIterations, (unsigned long)response.functionCalls.count);

    // Notify delegate about intermediate response (for UI updates)
    if ([self.delegate respondsToSelector:@selector(geminiClient:didCompleteSendWithResponse:)]) {
        [self.delegate geminiClient:self didCompleteSendWithResponse:response];
    }

    // Notify about each function call
    for (GeminiFunctionCall *call in response.functionCalls) {
        if ([self.delegate respondsToSelector:@selector(geminiClient:didRequestFunctionCall:)]) {
            [self.delegate geminiClient:self didRequestFunctionCall:call];
        }
    }

    // Execute all function calls sequentially
    [self executeFunctionCallsAtIndex:0 calls:response.functionCalls];
}

- (void)executeFunctionCallsAtIndex:(NSUInteger)index calls:(NSArray<GeminiFunctionCall *> *)calls {
    if (index >= calls.count) {
        // All function calls executed, send results back to Gemini
        NSLog(@"[GeminiClient] All %lu function calls executed, sending results to Gemini", (unsigned long)calls.count);
        [self sendRequestWithFunctionResult:nil];
        return;
    }

    GeminiFunctionCall *call = calls[index];
    NSLog(@"[GeminiClient] Executing function %lu/%lu: %@", (unsigned long)(index + 1), (unsigned long)calls.count, call.name);

    __weak typeof(self) weakSelf = self;
    self.toolExecutor(call, ^(NSString *result) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        // Add function result to history
        [strongSelf.conversationHistory addObject:[GeminiMessage functionResult:call.name result:result]];

        // Process next function call
        [strongSelf executeFunctionCallsAtIndex:index + 1 calls:calls];
    });
}

@end
