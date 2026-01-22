//
//  BotChatWindowController+ModeManagement.m
//  mcpwa
//
//  Chat mode management: MCP/RAG mode switching, Gemini/RAG client setup, model selection
//

#import "BotChatWindowController+ModeManagement.h"
#import "BotChatWindowController+ThemeHandling.h"
#import "BotChatWindowController+MessageRendering.h"
#import "BotChatWindowController+MCPToolExecution.h"
#import "DebugConfigWindowController.h"
#import "WALogger.h"

@implementation BotChatWindowController (ModeManagement)

#pragma mark - Mode Change Handling

- (void)chatModeDidChange:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        WAChatMode newMode = [notification.userInfo[@"mode"] integerValue];
        self.currentChatMode = newMode;

        // Update mode indicator
        [self updateModeIndicator];

        // Reinitialize RAG client if URL might have changed
        if (newMode == WAChatModeRAG) {
            [self setupRAGClient];
        }

        // Show system message about mode change
        NSString *modeName = (newMode == WAChatModeRAG) ? @"RAG (Knowledge Base)" : @"MCP (WhatsApp)";
        [self addSystemMessage:[NSString stringWithFormat:@"Switched to %@ mode", modeName]];

        [self updateStatus:@"Ready"];
    });
}

#pragma mark - Client Setup

- (void)setupGeminiClient {
    NSString *apiKey = [GeminiClient loadAPIKey];

    if (!apiKey) {
        [self addSystemMessage:@"No Gemini API key found. Please set GEMINI_API_KEY environment variable "
                               "or add it to ~/Library/Application Support/mcpwa/config.json"];
        self.inputTextView.editable = NO;
        self.sendButton.enabled = NO;
        return;
    }

    self.geminiClient = [[GeminiClient alloc] initWithAPIKey:apiKey];
    self.geminiClient.delegate = self;

    // Set up tool executor for automatic tool call looping
    __weak typeof(self) weakSelf = self;
    self.geminiClient.toolExecutor = ^(GeminiFunctionCall *call, GeminiToolExecutorCompletion completion) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        [strongSelf updateStatus:[strongSelf friendlyStatusForTool:call.name]];

        [strongSelf executeMCPTool:call.name args:call.args completion:^(NSString *result) {
            // Show function result in chat only if debug mode is enabled
            if ([DebugConfigWindowController showDebugInChatEnabled]) {
                [strongSelf addFunctionMessage:call.name result:result];
            }
            completion(result);
        }];
    };

    // Load saved model preference
    NSString *savedModel = [[NSUserDefaults standardUserDefaults] stringForKey:@"GeminiSelectedModel"];
    if (savedModel.length > 0) {
        self.geminiClient.model = savedModel;
    }

    // Update model selector to reflect the loaded preference
    [self selectModelInSelector:self.geminiClient.model];

    [self updateStatus:@"Ready"];
}

- (void)setupRAGClient {
    NSString *ragURL = [SettingsWindowController ragServiceURL];
    self.ragClient = [[RAGClient alloc] initWithBaseURL:ragURL];
    self.ragClient.delegate = self;

    // Fetch available models from the server
    [self populateRAGModelSelector];
}

- (void)loadMCPTools {
    // Define MCP tools that Gemini can call
    self.mcpTools = @[
        @{
            @"name": @"whatsapp_start_session",
            @"description": @"Call this at the START of processing any user prompt that requires WhatsApp access. Initializes WhatsApp by navigating to Chats tab and clearing stale search state.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{},
                @"required": @[]
            }
        },
        @{
            @"name": @"whatsapp_stop_session",
            @"description": @"Call this at the END of processing any user prompt that required WhatsApp access. Cleans up by clearing any active search.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{},
                @"required": @[]
            }
        },
        @{
            @"name": @"whatsapp_status",
            @"description": @"Check WhatsApp accessibility status - whether the app is running and permissions are granted",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{},
                @"required": @[]
            }
        },
        @{
            @"name": @"whatsapp_list_chats",
            @"description": @"Get list of recent visible WhatsApp chats with last message preview. Returns chat names, last messages, timestamps, and whether chats are pinned or group chats.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"filter": @{
                        @"type": @"string",
                        @"description": @"Optional filter: 'all' (default), 'unread', 'favorites', or 'groups'",
                        @"enum": @[@"all", @"unread", @"favorites", @"groups"]
                    }
                },
                @"required": @[]
            }
        },
        @{
            @"name": @"whatsapp_get_current_chat",
            @"description": @"Get the currently open chat's name and all visible messages.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{},
                @"required": @[]
            }
        },
        @{
            @"name": @"whatsapp_open_chat",
            @"description": @"Open a specific chat by name. Use partial matching - e.g., 'John' will match 'John Smith'.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"name": @{
                        @"type": @"string",
                        @"description": @"Name of the chat or contact to open"
                    }
                },
                @"required": @[@"name"]
            }
        },
        @{
            @"name": @"whatsapp_get_messages",
            @"description": @"Get messages from a specific chat. Opens the chat if not already open, then returns all visible messages.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"chat_name": @{
                        @"type": @"string",
                        @"description": @"Name of the chat to get messages from"
                    }
                },
                @"required": @[@"chat_name"]
            }
        },
        @{
            @"name": @"whatsapp_send_message",
            @"description": @"Send a message to the currently open chat. Use whatsapp_open_chat first to select the recipient.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"message": @{
                        @"type": @"string",
                        @"description": @"The message text to send"
                    }
                },
                @"required": @[@"message"]
            }
        },
        @{
            @"name": @"whatsapp_search",
            @"description": @"Global search across all WhatsApp chats. Searches for keywords in chat names and message content.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"query": @{
                        @"type": @"string",
                        @"description": @"Search query - keywords to find in chat names and message content"
                    }
                },
                @"required": @[@"query"]
            }
        },
        // === Local Tools (Gemini can search web and fetch URLs natively) ===
        @{
            @"name": @"run_shell_command",
            @"description": @"Execute a shell command on the local Mac and return the output. Use for file operations, system info, running scripts, etc. Examples: 'ls -la', 'cat file.txt', 'date', 'pwd'.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"command": @{
                        @"type": @"string",
                        @"description": @"The shell command to execute"
                    }
                },
                @"required": @[@"command"]
            }
        }
    ];

    [self.geminiClient configureMCPTools:self.mcpTools];
}

#pragma mark - Model Selection

- (void)populateModelSelector {
    [self.modelSelector removeAllItems];
    for (NSString *modelId in [GeminiClient availableModels]) {
        NSString *displayName = [GeminiClient displayNameForModel:modelId];
        [self.modelSelector addItemWithTitle:displayName];
        self.modelSelector.lastItem.representedObject = modelId;
    }
}

- (void)selectModelInSelector:(NSString *)modelId {
    for (NSMenuItem *item in self.modelSelector.itemArray) {
        if ([item.representedObject isEqualToString:modelId]) {
            [self.modelSelector selectItem:item];
            return;
        }
    }
}

- (void)modelChanged:(NSPopUpButton *)sender {
    NSString *selectedModelId = sender.selectedItem.representedObject;
    if (selectedModelId) {
        self.geminiClient.model = selectedModelId;
        [[NSUserDefaults standardUserDefaults] setObject:selectedModelId forKey:@"GeminiSelectedModel"];

        NSString *displayName = [GeminiClient displayNameForModel:selectedModelId];
        [self updateStatus:@"Ready"];

        // Add system message about model change
        [self addSystemMessage:[NSString stringWithFormat:@"Switched to %@", displayName]];
    }
}

- (void)ragModelChanged:(NSPopUpButton *)sender {
    NSString *selectedModelId = sender.selectedItem.representedObject;
    if (selectedModelId) {
        self.selectedRAGModelId = selectedModelId;
        [[NSUserDefaults standardUserDefaults] setObject:selectedModelId forKey:@"RAGSelectedModel"];

        NSString *displayName = sender.selectedItem.title;
        [self updateStatus:@"Ready"];

        // Add system message about model change
        [self addSystemMessage:[NSString stringWithFormat:@"Switched to %@", displayName]];
    }
}

- (void)populateRAGModelSelector {
    [WALogger info:@"[RAG UI] populateRAGModelSelector called"];
    [self.ragModelSelector removeAllItems];

    // Add placeholder while loading
    [self.ragModelSelector addItemWithTitle:@"Loading models..."];
    self.ragModelSelector.enabled = NO;

    // Fetch models from server
    [self.ragClient listModelsWithCompletion:^(NSArray<RAGModelItem *> *models, NSString *error) {
        [WALogger info:@"[RAG UI] listModelsWithCompletion returned - models: %lu, error: %@",
            (unsigned long)models.count, error];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.ragModelSelector removeAllItems];

            if (error) {
                [WALogger error:@"[RAG] Failed to fetch models: %@", error];
                [self.ragModelSelector addItemWithTitle:@"Error loading models"];
                return;
            }

            if (models.count == 0) {
                [self.ragModelSelector addItemWithTitle:@"No models available"];
                return;
            }

            self.ragModels = models;
            self.ragModelSelector.enabled = YES;

            // Group models by provider for better organization
            NSMutableDictionary<NSString *, NSMutableArray<RAGModelItem *> *> *byProvider = [NSMutableDictionary dictionary];
            for (RAGModelItem *model in models) {
                NSString *provider = model.provider ?: @"other";
                if (!byProvider[provider]) {
                    byProvider[provider] = [NSMutableArray array];
                }
                [byProvider[provider] addObject:model];
            }

            // Add models to selector, grouped by provider
            NSArray *providerOrder = @[@"gemini", @"anthropic", @"openai", @"other"];
            NSString *defaultModelId = @"gemini-3-pro";
            BOOL foundDefault = NO;

            for (NSString *provider in providerOrder) {
                NSArray<RAGModelItem *> *providerModels = byProvider[provider];
                if (!providerModels || providerModels.count == 0) continue;

                // Add separator with provider name if we have multiple providers
                if (byProvider.count > 1 && self.ragModelSelector.numberOfItems > 0) {
                    [self.ragModelSelector.menu addItem:[NSMenuItem separatorItem]];
                }

                for (RAGModelItem *model in providerModels) {
                    // Add provider emoji prefix
                    NSString *prefix = @"";
                    if ([model.provider isEqualToString:@"gemini"]) {
                        prefix = @"\u2728 ";  // sparkles for Gemini
                    } else if ([model.provider isEqualToString:@"anthropic"]) {
                        prefix = @"\U0001F9E0 ";  // brain for Anthropic
                    } else if ([model.provider isEqualToString:@"openai"]) {
                        prefix = @"\U0001F916 ";  // robot for OpenAI
                    }

                    NSString *displayName = [NSString stringWithFormat:@"%@%@", prefix, model.name];
                    [self.ragModelSelector addItemWithTitle:displayName];
                    self.ragModelSelector.lastItem.representedObject = model.modelId;

                    // Check if this is the default model
                    if ([model.modelId isEqualToString:defaultModelId]) {
                        foundDefault = YES;
                    }
                }
            }

            // Select saved model or default
            NSString *savedModelId = [[NSUserDefaults standardUserDefaults] stringForKey:@"RAGSelectedModel"];
            NSString *modelToSelect = savedModelId.length > 0 ? savedModelId : defaultModelId;

            // Find and select the model
            BOOL selected = NO;
            for (NSMenuItem *item in self.ragModelSelector.itemArray) {
                if ([item.representedObject isEqualToString:modelToSelect]) {
                    [self.ragModelSelector selectItem:item];
                    self.selectedRAGModelId = modelToSelect;
                    selected = YES;
                    break;
                }
            }

            // If not found, select first non-separator item
            if (!selected && self.ragModelSelector.numberOfItems > 0) {
                for (NSMenuItem *item in self.ragModelSelector.itemArray) {
                    if (!item.isSeparatorItem && item.representedObject) {
                        [self.ragModelSelector selectItem:item];
                        self.selectedRAGModelId = item.representedObject;
                        break;
                    }
                }
            }
        });
    }];
}

#pragma mark - Title Generation

- (void)generateTitleIfNeeded {
    if (self.hasTitleBeenGenerated || !self.firstUserMessage) {
        return;
    }
    self.hasTitleBeenGenerated = YES;

    // Generate title asynchronously using Gemini API
    NSString *apiKey = [GeminiClient loadAPIKey];
    if (!apiKey) return;

    NSString *prompt = [NSString stringWithFormat:
        @"Generate a very short title (2-5 words max) for a chat that starts with this message: \"%@\". "
        @"Reply with ONLY the title, no quotes, no explanation.", self.firstUserMessage];

    // Use a fast model for title generation
    NSString *urlString = [NSString stringWithFormat:
        @"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=%@", apiKey];
    NSURL *url = [NSURL URLWithString:urlString];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSDictionary *body = @{
        @"contents": @[@{
            @"parts": @[@{@"text": prompt}]
        }]
    };

    NSError *jsonError;
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
    if (jsonError) return;

    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) return;

        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *title = json[@"candidates"][0][@"content"][@"parts"][0][@"text"];

        if (title.length > 0) {
            // Clean up the title - remove quotes and trim
            title = [title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            title = [title stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\"'"]];

            // Limit title length
            if (title.length > 40) {
                title = [[title substringToIndex:37] stringByAppendingString:@"..."];
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                self.titleLabel.stringValue = title;
            });
        }
    }];
    [task resume];
}

@end
