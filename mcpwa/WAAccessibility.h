//
//  WAAccessibility.h
//  mcpwa
//
//  Accessibility interface for WhatsApp Desktop
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Data Models

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

#pragma mark - Main Class

@interface WAAccessibility : NSObject

/// Shared instance
+ (instancetype)shared;

/// Check if WhatsApp is running and accessible
- (BOOL)isWhatsAppAvailable;

/// Activate WhatsApp window
- (BOOL)activateWhatsApp;

#pragma mark - Chat List

/// Get list of visible chats
- (NSArray<WAChat *> *)getChats;

/// Get chat by name (partial match)
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

#pragma mark - Actions

/// Send a message to the current chat
- (BOOL)sendMessage:(NSString *)message;

/// Search within WhatsApp
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
