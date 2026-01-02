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

/// NSUserDefaults key for theme setting
extern NSString *const WAThemeModeKey;

/// Notification posted when theme changes
extern NSString *const WAThemeDidChangeNotification;

@interface SettingsWindowController : NSWindowController

+ (instancetype)sharedController;

- (void)showWindow;
- (void)toggleWindow;

/// Current theme mode preference
@property (class, readonly) WAThemeMode currentThemeMode;

/// Returns the effective appearance based on current theme mode
+ (NSAppearance *)effectiveAppearance;

/// Apply theme to all windows
+ (void)applyThemeToAllWindows;

@end

NS_ASSUME_NONNULL_END
