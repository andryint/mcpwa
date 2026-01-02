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

typedef NS_ENUM(NSInteger, WALogCategory) {
    WALogCategoryGeneral,      // General application logs
    WALogCategoryAccessibility // Accessibility API related logs
};

@interface WALogger : NSObject

+ (void)debug:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
+ (void)info:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
+ (void)warn:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
+ (void)error:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

/// Log with explicit category for filtering
+ (void)debug:(WALogCategory)category format:(NSString *)format, ... NS_FORMAT_FUNCTION(2,3);
+ (void)info:(WALogCategory)category format:(NSString *)format, ... NS_FORMAT_FUNCTION(2,3);

+ (void)log:(WALogLevel)level message:(NSString *)message;
+ (void)log:(WALogLevel)level category:(WALogCategory)category message:(NSString *)message;

@end

NS_ASSUME_NONNULL_END
