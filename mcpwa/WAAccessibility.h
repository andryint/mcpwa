//
//  WAAccessibility.h
//  mcpwa
//
//  Accessibility interface for WhatsApp Desktop
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Data Models

/// Chat list filter options (All, Unread, Favorites, Groups)
typedef NS_ENUM(NSInteger, WAChatFilter) {
    WAChatFilterAll = 0,
    WAChatFilterUnread,
    WAChatFilterFavorites,
    WAChatFilterGroups
};

@interface WAChat : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *lastMessage;
@property (nonatomic, copy, nullable) NSString *timestamp;
@property (nonatomic, copy, nullable) NSString *sender;      // For group chats
@property (nonatomic, assign) BOOL isPinned;
@property (nonatomic, assign) BOOL isGroup;
@property (nonatomic, assign) BOOL isUnread;
@property (nonatomic, assign) NSInteger index;               // Position in chat list
@end

typedef NS_ENUM(NSInteger, WAMessageDirection) {
    WAMessageDirectionIncoming,
    WAMessageDirectionOutgoing,
    WAMessageDirectionSystem
};

@interface WAMessage : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy, nullable) NSString *sender;      // For incoming/group messages
@property (nonatomic, copy, nullable) NSString *timestamp;
@property (nonatomic, assign) WAMessageDirection direction;
@property (nonatomic, copy, nullable) NSString *replyTo;     // If replying to someone
@property (nonatomic, copy, nullable) NSString *replyText;   // The quoted text
@property (nonatomic, strong, nullable) NSArray<NSString *> *reactions;
@property (nonatomic, assign) BOOL isRead;                   // For outgoing
@end

@interface WACurrentChat : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy, nullable) NSString *lastSeen;    // "last seen today at 18:52"
@property (nonatomic, strong) NSArray<WAMessage *> *messages;
@end

#pragma mark - Search Result Models

/// A chat that matches the search query (by name)
@interface WASearchChatResult : NSObject
@property (nonatomic, copy) NSString *chatName;
@property (nonatomic, copy, nullable) NSString *lastMessagePreview;
@end

/// A message that matches the search query (by content)
@interface WASearchMessageResult : NSObject
@property (nonatomic, copy) NSString *chatName;
@property (nonatomic, copy, nullable) NSString *sender;
@property (nonatomic, copy) NSString *messagePreview;
@end

/// Combined search results
@interface WASearchResults : NSObject
@property (nonatomic, copy) NSString *query;
@property (nonatomic, strong) NSArray<WASearchChatResult *> *chatMatches;
@property (nonatomic, strong) NSArray<WASearchMessageResult *> *messageMatches;
@end

#pragma mark - Main Class

@interface WAAccessibility : NSObject

@property (readonly) pid_t whatsappPID;
/// Shared instance
+ (instancetype)shared;

/// Check if WhatsApp is running and accessible
- (BOOL)isWhatsAppAvailable;

/// Activate WhatsApp window
- (BOOL)activateWhatsApp;

/// Ensure WhatsApp is visible (unminimize from Dock if needed, unhide if hidden)
/// Call this before operations that require the WhatsApp window to be accessible
- (BOOL)ensureWhatsAppVisible;

- (AXUIElementRef)getMainWindow;
- (void)pressKey:(CGKeyCode)keyCode withFlags:(CGEventFlags)flags toProcess:(pid_t)pid;
- (void)typeString:(NSString *)string toProcess:(pid_t)pid;


#pragma mark - Search Mode Detection

/// Check if WhatsApp is currently in search mode (search bar active with query)
- (BOOL)isInSearchMode;

#pragma mark - Chat List Filters

/// Get the currently selected chat filter (All, Unread, Favorites, Groups)
- (WAChatFilter)getSelectedChatFilter;

/// Select a chat filter by pressing the corresponding button
/// Returns YES if the filter was successfully selected
- (BOOL)selectChatFilter:(WAChatFilter)filter;

/// Convert filter enum to string for display/API
+ (NSString *)stringFromChatFilter:(WAChatFilter)filter;

/// Convert string to filter enum (case-insensitive)
+ (WAChatFilter)chatFilterFromString:(NSString *)string;

#pragma mark - Chat List

/// Get list of visible chats
- (NSArray<WAChat *> *)getRecentChats;

/// Get list of visible chats with optional filter
/// If filter is not WAChatFilterAll, will switch to that filter first
- (NSArray<WAChat *> *)getRecentChatsWithFilter:(WAChatFilter)filter;

/// Get chat by name (partial match)
/// This method is smart about the current UI state:
/// 1. If in search mode, looks in search results first
/// 2. If not found or in chat list mode, searches visible chat list
/// 3. If still not found, performs a search and looks in results
- (nullable WAChat *)findChatWithName:(NSString *)name;

/// Navigate to a specific chat by clicking on it
- (BOOL)openChat:(WAChat *)chat;

/// Open chat by name (convenience method)
- (BOOL)openChatWithName:(NSString *)name;

#pragma mark - Current Chat

/// Get info about the currently open chat
- (nullable WACurrentChat *)getCurrentChat;

/// Get messages from the currently open chat
- (NSArray<WAMessage *> *)getMessages;

/// Get messages with limit
- (NSArray<WAMessage *> *)getMessagesWithLimit:(NSInteger)limit;

#pragma mark - Global Search

/// Perform a global search across all chats and messages
/// Returns both chat name matches and message content matches
- (nullable WASearchResults *)globalSearch:(NSString *)query;

/// Clear the search field and return to normal chat list view
- (BOOL)clearSearch;

#pragma mark - Actions

/// Send a message to the current chat
- (BOOL)sendMessage:(NSString *)message;

/// Search within WhatsApp (just enters query, use globalSearch for results)
- (BOOL)searchFor:(NSString *)query;

#pragma mark - Navigation

/// Click the Chats tab
- (BOOL)navigateToChats;

/// Click the Calls tab
- (BOOL)navigateToCalls;

/// Click the Archived tab
- (BOOL)navigateToArchived;

/// Click the Settings tab
- (BOOL)navigateToSettings;

@end

NS_ASSUME_NONNULL_END
