// SettingsWindowController.h
// User Preferences Window Controller

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Theme preference options
typedef NS_ENUM(NSInteger, WAThemeMode) {
    WAThemeModeLight = 0,
    WAThemeModeDark = 1,
    WAThemeModeAuto = 2
};

/// Chat mode options
typedef NS_ENUM(NSInteger, WAChatMode) {
    WAChatModeMCP = 0,  // MCP mode (Gemini + WhatsApp tools)
    WAChatModeRAG = 1   // RAG mode (external RAG service)
};

/// RAG environment options
typedef NS_ENUM(NSInteger, WARAGEnvironment) {
    WARAGEnvironmentProduction = 0,  // Production: localhost:8000
    WARAGEnvironmentDevelopment = 1  // Development: localhost:8001
};

/// NSUserDefaults key for theme setting
extern NSString *const WAThemeModeKey;

/// NSUserDefaults key for chat mode setting
extern NSString *const WAChatModeKey;

/// NSUserDefaults key for RAG service URL
extern NSString *const WARAGServiceURLKey;

/// NSUserDefaults key for RAG environment
extern NSString *const WARAGEnvironmentKey;

/// Notification posted when theme changes
extern NSString *const WAThemeDidChangeNotification;

/// Notification posted when chat mode changes
extern NSString *const WAChatModeDidChangeNotification;

@interface SettingsWindowController : NSWindowController

+ (instancetype)sharedController;

- (void)showWindow;
- (void)toggleWindow;

/// Current theme mode preference
@property (class, readonly) WAThemeMode currentThemeMode;

/// Current chat mode preference
@property (class, readonly) WAChatMode currentChatMode;

/// Current RAG service URL
@property (class, readonly) NSString *ragServiceURL;

/// Current RAG environment
@property (class, readonly) WARAGEnvironment ragEnvironment;

/// Returns the effective appearance based on current theme mode
+ (NSAppearance *)effectiveAppearance;

/// Apply theme to all windows
+ (void)applyThemeToAllWindows;

/// Set chat mode programmatically
+ (void)setChatMode:(WAChatMode)mode;

/// Set RAG service URL programmatically
+ (void)setRAGServiceURL:(NSString *)url;

/// Set RAG environment programmatically
+ (void)setRAGEnvironment:(WARAGEnvironment)environment;

@end

NS_ASSUME_NONNULL_END
