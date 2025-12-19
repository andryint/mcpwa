// WALogger.m
// Centralized logging for WhatsApp Accessibility

#import "WALogger.h"

NSNotificationName const WALogNotification = @"WALogNotification";

@implementation WALogger

+ (void)debug:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self log:WALogLevelDebug message:message];
}

+ (void)info:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self log:WALogLevelInfo message:message];
}

+ (void)warn:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self log:WALogLevelWarning message:message];
}

+ (void)error:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self log:WALogLevelError message:message];
}

+ (void)log:(WALogLevel)level message:(NSString *)message {
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
