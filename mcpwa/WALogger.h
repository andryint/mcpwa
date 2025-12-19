// WALogger.h
// Centralized logging for WhatsApp Accessibility

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Notification posted when a log message is added
/// userInfo contains: @"message" (NSString), @"level" (NSString)
extern NSNotificationName const WALogNotification;

typedef NS_ENUM(NSInteger, WALogLevel) {
    WALogLevelDebug,
    WALogLevelInfo,
    WALogLevelWarning,
    WALogLevelError
};

@interface WALogger : NSObject

+ (void)debug:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
+ (void)info:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
+ (void)warn:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
+ (void)error:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

+ (void)log:(WALogLevel)level message:(NSString *)message;

@end

NS_ASSUME_NONNULL_END
