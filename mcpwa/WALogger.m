// WALogger.m
// Centralized logging for WhatsApp Accessibility

#import "WALogger.h"
#import "DebugConfigWindowController.h"

NSNotificationName const WALogNotification = @"WALogNotification";

@implementation WALogger

+ (void)debug:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self log:WALogLevelDebug category:WALogCategoryGeneral message:message];
}

+ (void)info:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self log:WALogLevelInfo category:WALogCategoryGeneral message:message];
}

+ (void)warn:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self log:WALogLevelWarning category:WALogCategoryGeneral message:message];
}

+ (void)error:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self log:WALogLevelError category:WALogCategoryGeneral message:message];
}

+ (void)debug:(WALogCategory)category format:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self log:WALogLevelDebug category:category message:message];
}

+ (void)info:(WALogCategory)category format:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self log:WALogLevelInfo category:category message:message];
}

+ (void)log:(WALogLevel)level message:(NSString *)message {
    [self log:level category:WALogCategoryGeneral message:message];
}

+ (void)log:(WALogLevel)level category:(WALogCategory)category message:(NSString *)message {
    // Check if accessibility logs should be filtered
    // We detect accessibility logs both by explicit category and by message content patterns
    BOOL isAccessibilityLog = (category == WALogCategoryAccessibility);

    // Also detect by common accessibility-related prefixes in log messages
    if (!isAccessibilityLog) {
        static NSArray *accessibilityPrefixes = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            accessibilityPrefixes = @[
                @"connectToWhatsApp:",
                @"isWhatsAppAvailable:",
                @"ensureWhatsAppVisible:",
                @"getMainWindow:",
                @"isInSearchMode:",
                @"getSelectedChatFilter:",
                @"selectChatFilter:",
                @"getRecentChats",
                @"findChat",
                @"openChat",
                @"scrollChatList",
                @"getCurrentChat",
                @"getMessages",
                @"globalSearch",
                @"clearSearch",
                @"searchFor:",
                @"navigateTo",
                @"Found "  // "Found X chats" etc
            ];
        });

        for (NSString *prefix in accessibilityPrefixes) {
            if ([message hasPrefix:prefix] || [message containsString:prefix]) {
                isAccessibilityLog = YES;
                break;
            }
        }
    }

    if (isAccessibilityLog && ![DebugConfigWindowController logAccessibilityEnabled]) {
        return;
    }

    NSString *levelStr;
    switch (level) {
        case WALogLevelDebug: levelStr = @"DEBUG"; break;
        case WALogLevelInfo: levelStr = @"INFO"; break;
        case WALogLevelWarning: levelStr = @"WARN"; break;
        case WALogLevelError: levelStr = @"ERROR"; break;
    }

    // Post notification for UI logging
    [[NSNotificationCenter defaultCenter] postNotificationName:WALogNotification
                                                        object:nil
                                                      userInfo:@{
        @"message": message,
        @"level": levelStr
    }];

    // Also log to console
    NSLog(@"[WA-%@] %@", levelStr, message);
}

@end
