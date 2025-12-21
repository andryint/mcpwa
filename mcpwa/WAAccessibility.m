//
//  WAAccessibility.m
//  mcpwa
//
//  Accessibility interface for WhatsApp Desktop
//

#import "WAAccessibility.h"
#import "WALogger.h"
#import <ApplicationServices/ApplicationServices.h>

#pragma mark - Data Model Implementations

@implementation WAChat
- (NSString *)description {
    return [NSString stringWithFormat:@"<WAChat: %@ - %@>", self.name, self.lastMessage];
}
@end

@implementation WAMessage
- (NSString *)description {
    NSString *dir = self.direction == WAMessageDirectionIncoming ? @"←" : 
                    self.direction == WAMessageDirectionOutgoing ? @"→" : @"•";
    return [NSString stringWithFormat:@"<%@ %@: %@>", dir, self.sender ?: @"me", self.text];
}
@end

@implementation WACurrentChat
@end

@implementation WASearchChatResult
- (NSString *)description {
    return [NSString stringWithFormat:@"<WASearchChatResult: %@>", self.chatName];
}
@end

@implementation WASearchMessageResult
- (NSString *)description {
    return [NSString stringWithFormat:@"<WASearchMessageResult: %@ in %@>", self.messagePreview, self.chatName];
}
@end

@implementation WASearchResults
- (NSString *)description {
    return [NSString stringWithFormat:@"<WASearchResults: query='%@' chats=%lu messages=%lu>", 
            self.query, (unsigned long)self.chatMatches.count, (unsigned long)self.messageMatches.count];
}
@end

#pragma mark - WAAccessibility

@interface WAAccessibility ()
@property (nonatomic, assign) pid_t whatsappPID;
@property (nonatomic, assign) AXUIElementRef appElement;
@end

@implementation WAAccessibility

+ (instancetype)shared {
    static WAAccessibility *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[WAAccessibility alloc] init];
    });
    return instance;
}

- (void)dealloc {
    if (_appElement) {
        CFRelease(_appElement);
    }
}

#pragma mark - String Helpers

/// Strip Unicode LTR marks and trim whitespace
- (NSString *)cleanString:(NSString *)str {
    if (!str) return nil;
    
    // Remove various Unicode direction and formatting marks
    NSMutableString *clean = [str mutableCopy];
    [clean replaceOccurrencesOfString:@"\u200E" withString:@"" options:0 range:NSMakeRange(0, clean.length)]; // LTR mark
    [clean replaceOccurrencesOfString:@"\u200F" withString:@"" options:0 range:NSMakeRange(0, clean.length)]; // RTL mark
    [clean replaceOccurrencesOfString:@"\u200B" withString:@"" options:0 range:NSMakeRange(0, clean.length)]; // Zero-width space
    [clean replaceOccurrencesOfString:@"\u2068" withString:@"" options:0 range:NSMakeRange(0, clean.length)]; // First strong isolate
    [clean replaceOccurrencesOfString:@"\u2069" withString:@"" options:0 range:NSMakeRange(0, clean.length)]; // Pop directional isolate
    [clean replaceOccurrencesOfString:@"\u202A" withString:@"" options:0 range:NSMakeRange(0, clean.length)]; // Left-to-right embedding
    [clean replaceOccurrencesOfString:@"\u202C" withString:@"" options:0 range:NSMakeRange(0, clean.length)]; // Pop directional formatting
    [clean replaceOccurrencesOfString:@"\u00A0" withString:@" " options:0 range:NSMakeRange(0, clean.length)]; // Non-breaking space -> space
    
    return [clean stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

#pragma mark - AX Helpers

- (NSString *)stringAttribute:(CFStringRef)attr fromElement:(AXUIElementRef)element {
    if (!element || !attr) return nil;
    
    // Validate the element is still valid before querying
    CFTypeRef value = NULL;
    AXError err = AXUIElementCopyAttributeValue(element, attr, &value);
    
    if (err != kAXErrorSuccess || !value) {
        return nil;
    }
    
    // Make sure it's actually a string
    if (CFGetTypeID(value) != CFStringGetTypeID()) {
        CFRelease(value);
        return nil;
    }
    
    NSString *str = (__bridge_transfer NSString *)value;
    return [self cleanString:str];
}

- (NSArray *)childrenOfElement:(AXUIElementRef)element {
    if (!element) return @[];
    
    CFTypeRef value = NULL;
    AXError err = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute, &value);
    
    if (err != kAXErrorSuccess || !value) {
        return @[];
    }
    
    // Verify it's an array
    if (CFGetTypeID(value) != CFArrayGetTypeID()) {
        CFRelease(value);
        return @[];
    }
    
    return (__bridge_transfer NSArray *)value;
}

- (NSString *)roleOfElement:(AXUIElementRef)element {
    return [self stringAttribute:kAXRoleAttribute fromElement:element];
}

- (NSString *)identifierOfElement:(AXUIElementRef)element {
    return [self stringAttribute:CFSTR("AXIdentifier") fromElement:element];
}

- (NSString *)descriptionOfElement:(AXUIElementRef)element {
    return [self stringAttribute:kAXDescriptionAttribute fromElement:element];
}

- (NSString *)valueOfElement:(AXUIElementRef)element {
    return [self stringAttribute:kAXValueAttribute fromElement:element];
}

- (NSString *)titleOfElement:(AXUIElementRef)element {
    return [self stringAttribute:kAXTitleAttribute fromElement:element];
}

- (BOOL)pressElement:(AXUIElementRef)element {
    if (!element) return NO;
    AXError err = AXUIElementPerformAction(element, kAXPressAction);
    return err == kAXErrorSuccess;
}

- (BOOL)setValueOfElement:(AXUIElementRef)element to:(NSString *)value {
    if (!element || !value) return NO;
    AXError err = AXUIElementSetAttributeValue(element, kAXValueAttribute, (__bridge CFTypeRef)value);
    return err == kAXErrorSuccess;
}

- (BOOL)setFocusOnElement:(AXUIElementRef)element {
    if (!element) return NO;
    AXError err = AXUIElementSetAttributeValue(element, kAXFocusedAttribute, kCFBooleanTrue);
    return err == kAXErrorSuccess;
}

#pragma mark - Element Finding

- (void)findElementsIn:(AXUIElementRef)root
             predicate:(BOOL(^)(AXUIElementRef element, NSString *role, NSString *identifier))predicate
              maxDepth:(int)maxDepth
               results:(NSMutableArray *)results
                 depth:(int)depth {
    
    if (depth >= maxDepth || !root) return;
    
    @try {
        // Validate the element before using it
        CFTypeRef testValue = NULL;
        AXError testErr = AXUIElementCopyAttributeValue(root, kAXRoleAttribute, &testValue);
        if (testErr != kAXErrorSuccess) {
            // Element is invalid or stale
            return;
        }
        
        NSString *role = nil;
        if (testValue) {
            if (CFGetTypeID(testValue) == CFStringGetTypeID()) {
                role = [self cleanString:(__bridge NSString *)testValue];
            }
            CFRelease(testValue);
        }
        
        NSString *identifier = [self identifierOfElement:root];
        
        // Call predicate with safe values (role/identifier may be nil)
        BOOL matches = NO;
        @try {
            matches = predicate(root, role ?: @"", identifier ?: @"");
        } @catch (NSException *e) {
            // Predicate threw - skip this element
            matches = NO;
        }
        
        if (matches) {
            // RETAIN the element before storing - caller must release elements in array
            CFRetain(root);
            [results addObject:(__bridge id)root];
        }
        
        NSArray *children = [self childrenOfElement:root];
        for (id child in children) {
            if (child && child != [NSNull null]) {
                AXUIElementRef childRef = (__bridge AXUIElementRef)child;
                if (childRef) {
                    [self findElementsIn:childRef
                               predicate:predicate
                                maxDepth:maxDepth
                                 results:results
                                   depth:depth + 1];
                }
            }
        }
    } @catch (NSException *exception) {
        // Log and continue - don't crash
        NSLog(@"WAAccessibility: Exception in findElementsIn: %@", exception);
    }
}

// Returns array of RETAINED elements - caller must CFRelease each element
- (NSArray *)findElementsIn:(AXUIElementRef)root
                  predicate:(BOOL(^)(AXUIElementRef element, NSString *role, NSString *identifier))predicate
                   maxDepth:(int)maxDepth {
    NSMutableArray *results = [NSMutableArray array];
    [self findElementsIn:root predicate:predicate maxDepth:maxDepth results:results depth:0];
    return results;
}

// Returns a RETAINED element - caller must CFRelease
- (AXUIElementRef)findFirstElementIn:(AXUIElementRef)root
                           predicate:(BOOL(^)(AXUIElementRef element, NSString *role, NSString *identifier))predicate
                            maxDepth:(int)maxDepth {
    NSArray *results = [self findElementsIn:root predicate:predicate maxDepth:maxDepth];
    AXUIElementRef result = NULL;
    
    if (results.count > 0) {
        // Elements are already retained in array, just take the first one
        result = (__bridge AXUIElementRef)results[0];
        // Retain it again since we're returning it and will release the array's copy
        if (result) {
            CFRetain(result);
        }
    }
    
    // Release all elements in the array
    for (id elem in results) {
        if (elem && elem != [NSNull null]) {
            CFRelease((__bridge AXUIElementRef)elem);
        }
    }
    
    return result;
}

// Returns a RETAINED element - caller must CFRelease
- (AXUIElementRef)findElementWithIdentifier:(NSString *)identifier inElement:(AXUIElementRef)root {
    return [self findFirstElementIn:root predicate:^BOOL(AXUIElementRef element, NSString *role, NSString *ident) {
        return ident && [ident isEqualToString:identifier];
    } maxDepth:15];
}

#pragma mark - WhatsApp Connection

- (BOOL)connectToWhatsApp {
    NSArray *apps = [[NSWorkspace sharedWorkspace] runningApplications];
    
    for (NSRunningApplication *app in apps) {
        if ([app.bundleIdentifier isEqualToString:@"net.whatsapp.WhatsApp"]) {
            self.whatsappPID = app.processIdentifier;
            
            if (self.appElement) {
                CFRelease(self.appElement);
            }
            self.appElement = AXUIElementCreateApplication(self.whatsappPID);
            return self.appElement != NULL;
        }
    }
    
    return NO;
}

- (BOOL)isWhatsAppAvailable {
    if (![self connectToWhatsApp]) {
        return NO;
    }
    
    // Verify we can actually query it
    NSString *role = [self roleOfElement:self.appElement];
    return [role isEqualToString:@"AXApplication"];
}

- (BOOL)activateWhatsApp {
    NSArray *apps = [[NSWorkspace sharedWorkspace] runningApplications];
    
    for (NSRunningApplication *app in apps) {
        if ([app.bundleIdentifier isEqualToString:@"net.whatsapp.WhatsApp"]) {
            BOOL activated = [app activateWithOptions:NSApplicationActivateIgnoringOtherApps];
            
            if (activated) {
                // Wait until WhatsApp is actually frontmost (up to 1 second)
                for (int i = 0; i < 20; i++) {
                    [NSThread sleepForTimeInterval:0.05];
                    if ([app isActive]) {
                        // Extra delay to ensure window is ready for keyboard input
                        [NSThread sleepForTimeInterval:0.15];
                        return YES;
                    }
                }
            }
            return activated;
        }
    }
    
    return NO;
}

- (AXUIElementRef)getMainWindow {
    if (![self connectToWhatsApp]) return NULL;
    if (!self.appElement) return NULL;
    
    CFTypeRef windowsValue = NULL;
    AXError err = AXUIElementCopyAttributeValue(self.appElement, kAXWindowsAttribute, &windowsValue);
    
    if (err != kAXErrorSuccess || !windowsValue) {
        return NULL;
    }
    
    // Verify it's an array
    if (CFGetTypeID(windowsValue) != CFArrayGetTypeID()) {
        CFRelease(windowsValue);
        return NULL;
    }
    
    NSArray *windows = (__bridge NSArray *)windowsValue;  // Don't transfer - we'll release manually
    AXUIElementRef result = NULL;
    
    if (windows.count > 0) {
        AXUIElementRef window = (__bridge AXUIElementRef)windows[0];
        
        // Quick validation
        CFTypeRef roleValue = NULL;
        AXError roleErr = AXUIElementCopyAttributeValue(window, kAXRoleAttribute, &roleValue);
        if (roleErr == kAXErrorSuccess && roleValue) {
            CFRelease(roleValue);
            // Retain the window since we're returning it and windowsValue will be released
            result = (AXUIElementRef)CFRetain(window);
        }
    }
    
    CFRelease(windowsValue);
    return result;  // Caller is responsible for releasing this
}

#pragma mark - Search Mode Detection

- (BOOL)isInSearchMode {
    AXUIElementRef window = [self getMainWindow];
    if (!window) {
        [WALogger debug:@"isInSearchMode: no main window"];
        return NO;
    }

    // Check if the search clear/delete button exists - indicates search mode is active
    AXUIElementRef clearButton = [self findElementWithIdentifier:@"TokenizedSearchBar_DeleteButton" inElement:window];
    BOOL inSearchMode = (clearButton != NULL);

    if (clearButton) {
        CFRelease(clearButton);
    }
    CFRelease(window);

    [WALogger debug:@"isInSearchMode: %@", inSearchMode ? @"YES" : @"NO"];
    return inSearchMode;
}

#pragma mark - Chat List

- (NSArray<WAChat *> *)getRecentChats {
    AXUIElementRef window = [self getMainWindow];
    if (!window) return @[];
    
    if ([self isInSearchMode]) {
        [WALogger debug:@"getRecentChats: we need to close search before"];
        [self clearSearch];
        [NSThread sleepForTimeInterval:0.3];
    }
    
    NSMutableArray<WAChat *> *chats = [NSMutableArray array];
    
    // Find the ChatListView_TableView container first
    AXUIElementRef tableView = [self findElementWithIdentifier:@"ChatListView_TableView" inElement:window];
    if (!tableView) {
        [WALogger debug:@"getChats: Could not find ChatListView_TableView"];
        CFRelease(window);
        return @[];
    }
    
    // Get direct children of the table view - these are chat buttons
    NSArray *children = [self childrenOfElement:tableView];
    
    NSInteger index = 0;
    for (id child in children) {
        AXUIElementRef element = (__bridge AXUIElementRef)child;
        
        NSString *role = [self roleOfElement:element];
        if (![role isEqualToString:@"AXButton"]) continue;
        
        NSString *desc = [self descriptionOfElement:element];
        NSString *value = [self valueOfElement:element];
        
        // Skip filter buttons (they have values like "1 of 4", "2 of 4")
        if (value && [value containsString:@" of "]) continue;
        
        // Skip buttons without a proper name
        if (!desc || desc.length == 0) continue;
        
        WAChat *chat = [[WAChat alloc] init];
        chat.index = index++;
        chat.name = desc;
        
        if (value) {
            [self parseChatValue:value intoChat:chat];
        }
        
        [chats addObject:chat];
    }
    
    [WALogger debug:@"Found %lu chats", (unsigned long)chats.count];
    for(WAChat* chat in chats) {
        [WALogger debug:@"\t * %@", chat.name];
    }
    
    CFRelease(tableView);
    CFRelease(window);
    return chats;
}


- (void)parseChatValue:(NSString *)value intoChat:(WAChat *)chat {
    // Format examples:
    // "~ Emin A. left, 20Novemberat22:10, Pinned"
    // "message, форварднул, 12:23, Received from Igor B"
    // "Your message, text here, 6December..."
    // "Message from Мама Сами, Bonsoir samy..."
    // "Album with 13 photos, Received in..."
    
    chat.lastMessage = value;
    
    // Check for pinned
    chat.isPinned = [value containsString:@"Pinned"];
    
    // Check for group message indicator
    if ([value hasPrefix:@"Message from "]) {
        chat.isGroup = YES;
        // Extract sender name
        NSRange commaRange = [value rangeOfString:@", "];
        if (commaRange.location != NSNotFound) {
            NSString *fromPart = [value substringToIndex:commaRange.location];
            chat.sender = [fromPart stringByReplacingOccurrencesOfString:@"Message from " withString:@""];
        }
    }
    
    // Check if it contains "Received" - indicates unread potentially
    // (This is a heuristic - WhatsApp doesn't clearly expose unread state)
}

/**
 * Find chat in search results (when in search mode)
 * Looks for ChatListSearchView_ChatResult elements that match the name
 */
- (WAChat *)findChatInSearchResults:(NSString *)name {
    [WALogger debug:@"findChatInSearchResults: looking for '%@'", name];

    AXUIElementRef window = [self getMainWindow];
    if (!window) {
        [WALogger warn:@"findChatInSearchResults: no main window"];
        return nil;
    }

    NSString *lowerName = [name lowercaseString];
    WAChat *foundChat = nil;

    // Find chat results in search (ChatListSearchView_ChatResult)
    NSArray *chatResults = [self findElementsIn:window predicate:^BOOL(AXUIElementRef element, NSString *role, NSString *identifier) {
        return [identifier isEqualToString:@"ChatListSearchView_ChatResult"];
    } maxDepth:15];

    [WALogger debug:@"findChatInSearchResults: found %lu ChatResult elements", (unsigned long)chatResults.count];

    NSInteger index = 0;
    for (id chatBtn in chatResults) {
        AXUIElementRef button = (__bridge AXUIElementRef)chatBtn;
        NSString *chatName = [self descriptionOfElement:button];
        [WALogger debug:@"  [%ld] chatName='%@'", (long)index, chatName ?: @"<nil>"];

        if (chatName && [[chatName lowercaseString] containsString:lowerName]) {
            foundChat = [[WAChat alloc] init];
            foundChat.name = chatName;
            foundChat.index = index;
            foundChat.lastMessage = [self valueOfElement:button];
            [WALogger info:@"findChatInSearchResults: FOUND '%@' at index %ld", chatName, (long)index];
            break;
        }
        index++;
    }

    // Release all elements
    for (id btn in chatResults) {
        CFRelease((__bridge AXUIElementRef)btn);
    }
    CFRelease(window);

    if (!foundChat) {
        [WALogger debug:@"findChatInSearchResults: NOT FOUND"];
    }
    return foundChat;
}

- (WAChat *)findChatWithName:(NSString *)name {
    [WALogger info:@"findChatWithName: '%@'", name];

    NSString *lowerName = [name lowercaseString];

    // Step 1: Check if we're in search mode
    BOOL inSearchMode = [self isInSearchMode];
    [WALogger debug:@"findChatWithName: inSearchMode=%@", inSearchMode ? @"YES" : @"NO"];

    if (inSearchMode) {
        // Step 2a: In search mode - look for chat in search results first
        [WALogger debug:@"findChatWithName: trying search results first"];
        WAChat *chat = [self findChatInSearchResults:name];
        if (chat) {
            [WALogger info:@"findChatWithName: found in search results: '%@'", chat.name];
            return chat;
        }
        // If not found in current search results, clear search and try chat list
        [WALogger debug:@"findChatWithName: not in search results, clearing search"];
        [self clearSearch];
        [NSThread sleepForTimeInterval:0.3];
    }

    // Step 2b: In chat list mode - search the visible chat list
    [WALogger debug:@"findChatWithName: searching visible chat list"];
    NSArray<WAChat *> *chats = [self getRecentChats];
    [WALogger debug:@"findChatWithName: got %lu chats in list", (unsigned long)chats.count];

    for (WAChat *chat in chats) {
        if ([[chat.name lowercaseString] containsString:lowerName]) {
            [WALogger info:@"findChatWithName: found in chat list: '%@'", chat.name];
            return chat;
        }
    }

    // Step 3: Not found in current view - perform a search
    [WALogger debug:@"findChatWithName: not found in chat list, performing search"];

    pid_t waPid = self.whatsappPID;
    if (waPid == 0) {
        [WALogger error:@"findChatWithName: no WhatsApp PID"];
        return nil;
    }

    AXUIElementRef window = [self getMainWindow];
    if (!window) {
        [WALogger error:@"findChatWithName: no main window for search"];
        return nil;
    }

    // Clear any existing search first
    AXUIElementRef clearButton = [self findElementWithIdentifier:@"TokenizedSearchBar_DeleteButton" inElement:window];
    if (clearButton) {
        [WALogger debug:@"findChatWithName: clearing existing search"];
        [self pressElement:clearButton];
        CFRelease(clearButton);
        [NSThread sleepForTimeInterval:0.2];
    }

    // Press Cmd+F to open search
    [WALogger debug:@"findChatWithName: opening search (Cmd+F)"];
    [self pressKey:3 withFlags:kCGEventFlagMaskCommand toProcess:waPid];  // F key
    [NSThread sleepForTimeInterval:0.5];

    // Type the search query
    [WALogger debug:@"findChatWithName: typing query '%@'", name];
    [self typeString:name toProcess:waPid];
    [NSThread sleepForTimeInterval:0.8];

    CFRelease(window);

    // Step 4: Find the chat in search results
    [WALogger debug:@"findChatWithName: looking in new search results"];
    WAChat *foundChat = [self findChatInSearchResults:name];

    if (foundChat) {
        [WALogger info:@"findChatWithName: found after search: '%@'", foundChat.name];
    } else {
        [WALogger warn:@"findChatWithName: NOT FOUND anywhere for '%@'", name];
    }

    return foundChat;
}

- (BOOL)openChat:(WAChat *)chat
{
    if (!chat) return NO;
    
    AXUIElementRef window = [self getMainWindow];
    if (!window) return NO;
    
    BOOL result = NO;
    
    // First check if we're in search mode - buttons might be search results
    BOOL inSearchMode = [self isInSearchMode];
    
    if (inSearchMode) {
        // In search mode, look for ChatListSearchView_ChatResult buttons
        NSArray *buttons = [self findElementsIn:window predicate:^BOOL(AXUIElementRef element, NSString *role, NSString *identifier) {
            if (![role isEqualToString:@"AXButton"]) return NO;
            // Search results have this identifier
            if (![identifier isEqualToString:@"ChatListSearchView_ChatResult"]) return NO;
            NSString *desc = [self descriptionOfElement:element];
            return desc && [[desc lowercaseString] containsString:[chat.name lowercaseString]];
        } maxDepth:15];
        
        if (buttons.count > 0) {
            result = [self pressElement:(__bridge AXUIElementRef)buttons[0]];
        }
        
        for (id btn in buttons) {
            CFRelease((__bridge AXUIElementRef)btn);
        }
    } else {
        // In normal chat list mode - find ChatListView_TableView and look for button
        AXUIElementRef tableView = [self findElementWithIdentifier:@"ChatListView_TableView" inElement:window];
        if (tableView) {
            NSArray *children = [self childrenOfElement:tableView];
            
            for (id child in children) {
                AXUIElementRef element = (__bridge AXUIElementRef)child;
                
                NSString *role = [self roleOfElement:element];
                if (![role isEqualToString:@"AXButton"]) continue;
                
                NSString *desc = [self descriptionOfElement:element];
                if (desc && [[desc lowercaseString] containsString:[chat.name lowercaseString]]) {
                    result = [self pressElement:element];
                    break;
                }
            }
            
            CFRelease(tableView);
        }
    }
    
    CFRelease(window);
    return result;
}


- (BOOL)openChatWithName:(NSString *)name {
    WAChat *chat = [self findChatWithName:name];
    if (!chat) return NO;
    return [self openChat:chat];
}

#pragma mark - Current Chat

- (WACurrentChat *)getCurrentChat
{
    AXUIElementRef window = [self getMainWindow];
    if (!window) return nil;
    
    WACurrentChat *currentChat = [[WACurrentChat alloc] init];
    
    // Find the chat header - it's an AXHeading with id NavigationBar_HeaderViewButton
    AXUIElementRef chatHeader = [self findElementWithIdentifier:@"NavigationBar_HeaderViewButton" inElement:window];
    
    if (chatHeader) {
        // Name is in description, "last seen" status is in value
        currentChat.name = [self descriptionOfElement:chatHeader];
        currentChat.lastSeen = [self valueOfElement:chatHeader];
        CFRelease(chatHeader);
    }
    
    // Get messages
    currentChat.messages = [self getMessages];
    
    CFRelease(window);
    
    // Return nil if no chat is open (no name and no messages)
    if (!currentChat.name && currentChat.messages.count == 0) {
        return nil;
    }
    
    return currentChat;
}

- (NSArray<WAMessage *> *)getMessagesWithLimit:(NSInteger)limit
{
    AXUIElementRef window = [self getMainWindow];
    if (!window) return @[];
    
    NSMutableArray<WAMessage *> *messages = [NSMutableArray array];
    
    // Find the messages table - it's ChatMessagesTableView
    AXUIElementRef messagesTable = [self findElementWithIdentifier:@"ChatMessagesTableView" inElement:window];
    
    if (!messagesTable) {
        [WALogger debug:@"getMessages: ChatMessagesTableView not found"];
        CFRelease(window);
        return @[];
    }
    
    // Get direct children of the messages table
    NSArray *children = [self childrenOfElement:messagesTable];
    
    NSInteger count = 0;
    for (id child in children) {
        if (count >= limit) break;
        
        AXUIElementRef element = (__bridge AXUIElementRef)child;
        NSString *identifier = [self identifierOfElement:element];
        
        // Message cells have id WAMessageBubbleTableViewCell
        if (![identifier isEqualToString:@"WAMessageBubbleTableViewCell"]) {
            continue;
        }
        
        // The actual message content is in an AXGenericElement child
        NSArray *cellChildren = [self childrenOfElement:element];
        for (id cellChild in cellChildren) {
            AXUIElementRef contentElement = (__bridge AXUIElementRef)cellChild;
            NSString *role = [self roleOfElement:contentElement];
            
            // Look for AXGenericElement which contains the message description
            if ([role isEqualToString:@"AXGenericElement"]) {
                NSString *desc = [self descriptionOfElement:contentElement];
                if (desc && desc.length > 0) {
                    WAMessage *message = [self parseMessageDescription:desc];
                    if (message && message.text.length > 0) {
                        [messages addObject:message];
                        count++;
                    }
                }
                break; // Only one content element per cell
            }
        }
    }
    
    [WALogger debug:@"getMessages: found %lu messages", (unsigned long)messages.count];
    
    CFRelease(messagesTable);
    CFRelease(window);
    return messages;
}


- (NSArray<WAMessage *> *)getMessages {
    return [self getMessagesWithLimit:50];
}


- (WAMessage *)parseMessageDescription:(NSString *)desc {
    // Format examples:
    // "message, text here, 11:15, Received from Igor Berezovsky"
    // "Your message, text here, 11:14, Sent to Igor Berezovsky, Red"
    // "Replying to Igor Berezovsky.\nmessage, да, теперь стартует! 👍, 12:22, Received from Igor"
    // "Replying to You.\nmessage, форварднул, 12:23, Received from Igor Berezovsky"
    
    WAMessage *message = [[WAMessage alloc] init];
    
    // Check for reply
    if ([desc hasPrefix:@"Replying to "]) {
        NSRange newlineRange = [desc rangeOfString:@"\n"];
        if (newlineRange.location != NSNotFound) {
            NSString *replyPart = [desc substringToIndex:newlineRange.location];
            // Extract who they're replying to
            NSString *replyTo = [[replyPart stringByReplacingOccurrencesOfString:@"Replying to " withString:@""] 
                                stringByReplacingOccurrencesOfString:@"." withString:@""];
            message.replyTo = replyTo;
            
            // Continue parsing the rest
            desc = [desc substringFromIndex:newlineRange.location + 1];
        }
    }
    
    // Determine direction
    if ([desc hasPrefix:@"Your message, "]) {
        message.direction = WAMessageDirectionOutgoing;
        desc = [desc substringFromIndex:14]; // Remove "Your message, "
    } else if ([desc hasPrefix:@"message, "]) {
        message.direction = WAMessageDirectionIncoming;
        desc = [desc substringFromIndex:9]; // Remove "message, "
    } else {
        // System message or unknown format
        message.direction = WAMessageDirectionSystem;
        message.text = desc;
        return message;
    }
    
    // Now parse: "text, timestamp, Received from/Sent to Name"
    // This is tricky because text itself may contain commas
    
    // Find timestamp pattern (HH:MM)
    NSRegularExpression *timeRegex = [NSRegularExpression regularExpressionWithPattern:@", (\\d{1,2}:\\d{2}), " options:0 error:nil];
    NSTextCheckingResult *timeMatch = [timeRegex firstMatchInString:desc options:0 range:NSMakeRange(0, desc.length)];
    
    if (timeMatch && timeMatch.numberOfRanges >= 2) {
        // Extract timestamp
        message.timestamp = [desc substringWithRange:[timeMatch rangeAtIndex:1]];
        
        // Text is everything before the timestamp
        NSRange beforeTime = NSMakeRange(0, timeMatch.range.location);
        message.text = [desc substringWithRange:beforeTime];
        
        // After timestamp is sender/recipient info
        NSUInteger afterTimeStart = timeMatch.range.location + timeMatch.range.length;
        NSString *afterTime = [desc substringFromIndex:afterTimeStart];
        
        if ([afterTime hasPrefix:@"Received from "]) {
            NSString *sender = [afterTime stringByReplacingOccurrencesOfString:@"Received from " withString:@""];
            // May have trailing info, find comma
            NSRange commaRange = [sender rangeOfString:@", "];
            if (commaRange.location != NSNotFound) {
                sender = [sender substringToIndex:commaRange.location];
            }
            message.sender = sender;
        } else if ([afterTime hasPrefix:@"Sent to "]) {
            // Check for read status
            message.isRead = ![afterTime containsString:@"Red"]; // "Red" likely means "not read" indicator
        }
    } else {
        // Fallback - just use the whole thing as text
        message.text = desc;
    }
    
    return message;
}

#pragma mark - Keyboard Simulation

- (void)pasteString:(NSString *)string {
    // Save current clipboard contents
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    NSArray *previousContents = [pasteboard readObjectsForClasses:@[[NSString class]] options:nil];
    NSString *previousString = previousContents.firstObject;
    
    // Put our string on the clipboard
    [pasteboard clearContents];
    [pasteboard setString:string forType:NSPasteboardTypeString];
    
    // Small delay to ensure clipboard is ready
    [NSThread sleepForTimeInterval:0.1];
    
    // Send Cmd+V to paste
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    CGEventRef keyDown = CGEventCreateKeyboardEvent(source, 9, true);  // 9 = 'V' key
    CGEventRef keyUp = CGEventCreateKeyboardEvent(source, 9, false);
    CGEventSetFlags(keyDown, kCGEventFlagMaskCommand);
    CGEventSetFlags(keyUp, kCGEventFlagMaskCommand);
    CGEventPost(kCGHIDEventTap, keyDown);
    [NSThread sleepForTimeInterval:0.05];
    CGEventPost(kCGHIDEventTap, keyUp);
    CFRelease(keyDown);
    CFRelease(keyUp);
    if (source) CFRelease(source);
    
    // Small delay for paste to complete
    [NSThread sleepForTimeInterval:0.2];
    
    // Restore previous clipboard (optional, be nice to user)
    if (previousString) {
        [pasteboard clearContents];
        [pasteboard setString:previousString forType:NSPasteboardTypeString];
    }
}

- (void)pressKey:(CGKeyCode)keyCode withFlags:(CGEventFlags)flags {
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    CGEventRef keyDown = CGEventCreateKeyboardEvent(source, keyCode, true);
    CGEventRef keyUp = CGEventCreateKeyboardEvent(source, keyCode, false);
    if (flags) {
        CGEventSetFlags(keyDown, flags);
        CGEventSetFlags(keyUp, flags);
    }
    CGEventPost(kCGHIDEventTap, keyDown);
    [NSThread sleepForTimeInterval:0.05];
    CGEventPost(kCGHIDEventTap, keyUp);
    CFRelease(keyDown);
    CFRelease(keyUp);
    if (source) CFRelease(source);
}

- (void)pressKey:(CGKeyCode)keyCode withFlags:(CGEventFlags)flags toProcess:(pid_t)pid {
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    CGEventRef keyDown = CGEventCreateKeyboardEvent(source, keyCode, true);
    CGEventRef keyUp = CGEventCreateKeyboardEvent(source, keyCode, false);
    if (flags) {
        CGEventSetFlags(keyDown, flags);
        CGEventSetFlags(keyUp, flags);
    }
    
    // Post directly to target process - no focus stealing!
    CGEventPostToPid(pid, keyDown);
    [NSThread sleepForTimeInterval:0.05];
    CGEventPostToPid(pid, keyUp);
    
    CFRelease(keyDown);
    CFRelease(keyUp);
    if (source) CFRelease(source);
}

- (void)typeStringViaClipboard:(NSString *)string toProcess:(pid_t)pid {
    // Save current clipboard
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
//    NSArray *oldContents = [pb readObjectsForClasses:@[[NSString class], [NSImage class]] options:nil];
    
    // Set our string
    [pb clearContents];
    [pb setString:string forType:NSPasteboardTypeString];
    
    // Paste (keyDown only to avoid duplication)
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    CGEventRef keyDown = CGEventCreateKeyboardEvent(source, 0x09, true);  // V
    CGEventSetFlags(keyDown, kCGEventFlagMaskCommand);
    CGEventPostToPid(pid, keyDown);
    CFRelease(keyDown);
    
    [NSThread sleepForTimeInterval:0.05];
    CGEventRef keyUp = CGEventCreateKeyboardEvent(source, 0x09, false);
    CGEventPostToPid(pid, keyUp);
    CFRelease(keyUp);

    if (source) CFRelease(source);
    
    [NSThread sleepForTimeInterval:0.1];
    
    // Restore clipboard
    [pb clearContents];
//    if (oldContents.count > 0) {
//        [pb writeObjects:oldContents];
//    }
}


- (void)typeString:(NSString *)string toProcess:(pid_t)pid {
    [self typeStringViaClipboard:string toProcess:pid];
    /*
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    
    for (NSUInteger i = 0; i < string.length; i++) {
        unichar character = [string characterAtIndex:i];
        
        // Create key events with Unicode character
        CGEventRef keyDown = CGEventCreateKeyboardEvent(source, 0, true);
        CGEventRef keyUp = CGEventCreateKeyboardEvent(source, 0, false);
        
        // Set the Unicode string for this event
        UniChar chars[1] = { character };
        CGEventKeyboardSetUnicodeString(keyDown, 1, chars);
        CGEventKeyboardSetUnicodeString(keyUp, 1, chars);
        
        // Post to target process
        CGEventPostToPid(pid, keyDown);
        [NSThread sleepForTimeInterval:0.03];
        CGEventPostToPid(pid, keyUp);
        [NSThread sleepForTimeInterval:0.03];
        
        CFRelease(keyDown);
        CFRelease(keyUp);
    }
    
    if (source) CFRelease(source);
     */
}

#pragma mark - Global Search

- (WASearchResults *)globalSearch:(NSString *)query {
    if (!query || query.length == 0) return nil;
    
    AXUIElementRef window = [self getMainWindow];
    if (!window) return nil;
    
    WASearchResults *results = [[WASearchResults alloc] init];
    results.query = query;
    results.chatMatches = @[];
    results.messageMatches = @[];
    
    NSMutableArray<WASearchChatResult *> *chatMatches = [NSMutableArray array];
    NSMutableArray<WASearchMessageResult *> *messageMatches = [NSMutableArray array];
    NSMutableArray *allFoundElements = [NSMutableArray array]; // Track for cleanup
    
    @try {
        // Get WhatsApp's PID for targeted key events (no focus stealing!)
        pid_t waPid = self.whatsappPID;
        if (waPid == 0) {
            CFRelease(window);
            return results;
        }
        
        // 1. Clear any existing search if clear button is available
        AXUIElementRef clearButton = [self findElementWithIdentifier:@"TokenizedSearchBar_DeleteButton" inElement:window];
        if (clearButton) {
            [self pressElement:clearButton];
            CFRelease(clearButton);
            [NSThread sleepForTimeInterval:0.2];
        }
        
        // 2. Press Cmd+F to open search (sent directly to WhatsApp)
        [self pressKey:3 withFlags:kCGEventFlagMaskCommand toProcess:waPid];  // F
        [NSThread sleepForTimeInterval:0.5];
        
        // 3. Type query character by character (clipboard paste causes duplication)
        [self typeString:query toProcess:waPid];
        
        // Re-get window
        CFRelease(window);
        window = [self getMainWindow];
        if (!window) return results;
        
        // Wait for search results to populate
        [NSThread sleepForTimeInterval:0.8];
        
        // Re-get window to refresh element tree
        CFRelease(window);
        window = [self getMainWindow];
        if (!window) return results;
        
        // Sets for deduplication
        NSMutableSet<NSString *> *seenChatNames = [NSMutableSet set];
        NSMutableSet<NSString *> *seenMessageKeys = [NSMutableSet set];
        
        // 1. Find chat matches (ChatListSearchView_ChatResult)
        NSArray *chatResults = [self findElementsIn:window predicate:^BOOL(AXUIElementRef element, NSString *role, NSString *identifier) {
            return [identifier isEqualToString:@"ChatListSearchView_ChatResult"];
        } maxDepth:15];
        [allFoundElements addObjectsFromArray:chatResults];
        
        for (id chatBtn in chatResults) {
            AXUIElementRef button = (__bridge AXUIElementRef)chatBtn;
            
            NSString *chatName = [self descriptionOfElement:button];
            
            // Skip duplicates
            if (!chatName || [seenChatNames containsObject:chatName]) {
                continue;
            }
            [seenChatNames addObject:chatName];
            
            WASearchChatResult *chatResult = [[WASearchChatResult alloc] init];
            chatResult.chatName = chatName;
            chatResult.lastMessagePreview = [self valueOfElement:button];
            [chatMatches addObject:chatResult];
        }
        
        // 2. Find message matches (ChatListSearchView_MessageResult)
        NSArray *messageResults = [self findElementsIn:window predicate:^BOOL(AXUIElementRef element, NSString *role, NSString *identifier) {
            return [identifier isEqualToString:@"ChatListSearchView_MessageResult"];
        } maxDepth:15];
        [allFoundElements addObjectsFromArray:messageResults];
        
        for (id msgGroup in messageResults) {
            AXUIElementRef group = (__bridge AXUIElementRef)msgGroup;
            
            // The message info is in the child AXStaticText element's description
            // Format: "ChatName, ⁨Sender⁩‎: ‎message preview..."
            NSArray *textElements = [self findElementsIn:group predicate:^BOOL(AXUIElementRef element, NSString *role, NSString *identifier) {
                return [role isEqualToString:@"AXStaticText"];
            } maxDepth:3];
            [allFoundElements addObjectsFromArray:textElements];
            
            for (id textElem in textElements) {
                AXUIElementRef staticText = (__bridge AXUIElementRef)textElem;
                NSString *desc = [self descriptionOfElement:staticText];
                
                // Skip duplicates (use description as unique key)
                if (!desc || [seenMessageKeys containsObject:desc]) {
                    continue;
                }
                [seenMessageKeys addObject:desc];
                
                WASearchMessageResult *msgResult = [self parseSearchMessageDescription:desc];
                if (msgResult) {
                    [messageMatches addObject:msgResult];
                }
            }
        }
        
        results.chatMatches = chatMatches;
        results.messageMatches = messageMatches;
        
    } @catch (NSException *exception) {
        NSLog(@"WAAccessibility: Exception in globalSearch: %@", exception);
    }
    
    // Release all found elements
    for (id elem in allFoundElements) {
        if (elem && elem != [NSNull null]) {
            CFRelease((__bridge AXUIElementRef)elem);
        }
    }
    
    CFRelease(window);
    return results;
}

- (WASearchMessageResult *)parseSearchMessageDescription:(NSString *)desc {
    // Format: "ChatName, ⁨Sender⁩‎: ‎message preview text..."
    // Or: "ChatName, ⁨‎You⁩‎: ‎message preview text..."
    // After cleaning: "ChatName, Sender: message preview text..."
    
    if (!desc || desc.length == 0) return nil;
    
    WASearchMessageResult *result = [[WASearchMessageResult alloc] init];
    
    // Find the first comma to get chat name
    NSRange firstComma = [desc rangeOfString:@", "];
    if (firstComma.location == NSNotFound) {
        // No comma, use whole thing as chat name
        result.chatName = desc;
        return result;
    }
    
    result.chatName = [desc substringToIndex:firstComma.location];
    NSString *remainder = [desc substringFromIndex:firstComma.location + 2];
    
    // Find the colon to separate sender from message
    NSRange colonRange = [remainder rangeOfString:@": "];
    if (colonRange.location != NSNotFound) {
        result.sender = [remainder substringToIndex:colonRange.location];
        result.messagePreview = [remainder substringFromIndex:colonRange.location + 2];
        
        // Check if sender is "You" (outgoing message)
        if ([result.sender isEqualToString:@"You"]) {
            result.sender = nil; // Clear it for outgoing messages
        }
    } else {
        // No colon, just use remainder as message
        result.messagePreview = remainder;
    }
    
    return result;
}

- (BOOL)clearSearch {
    AXUIElementRef window = [self getMainWindow];
    if (!window) return NO;
    
    BOOL result = NO;
    AXUIElementRef clearButton = [self findElementWithIdentifier:@"TokenizedSearchBar_DeleteButton" inElement:window];
    if (clearButton) {
        result = [self pressElement:clearButton];
        CFRelease(clearButton);
    } else {
        // Fallback: press Escape key to clear search (no focus stealing)
        pid_t waPid = self.whatsappPID;
        if (waPid != 0) {
            [self pressKey:53 withFlags:0 toProcess:waPid];  // Escape
            result = YES;
        }
    }
    
    CFRelease(window);
    return result;
}

#pragma mark - Actions

- (BOOL)sendMessage:(NSString *)message {
    AXUIElementRef window = [self getMainWindow];
    if (!window) return NO;
    
    pid_t waPid = self.whatsappPID;
    if (waPid == 0) {
        CFRelease(window);
        return NO;
    }
    
    // Find the compose text area
    AXUIElementRef composeArea = [self findElementWithIdentifier:@"ChatBar_ComposerTextView" inElement:window];
    if (!composeArea) {
        CFRelease(window);
        return NO;
    }
    
    // Focus and set value via accessibility (no window activation needed)
    [self setFocusOnElement:composeArea];
    [NSThread sleepForTimeInterval:0.1];
    
    // Set the text value
    if (![self setValueOfElement:composeArea to:message]) {
        CFRelease(composeArea);
        CFRelease(window);
        return NO;
    }
    
    // Send Enter key directly to WhatsApp (no focus stealing)
    [self pressKey:36 withFlags:0 toProcess:waPid];  // 36 = Return key
    
    CFRelease(composeArea);
    CFRelease(window);
    return YES;
}

- (BOOL)searchFor:(NSString *)query {
    AXUIElementRef window = [self getMainWindow];
    if (!window) return NO;
    
    pid_t waPid = self.whatsappPID;
    if (waPid == 0) {
        CFRelease(window);
        return NO;
    }
    
    // Press Cmd+F to open search
    [self pressKey:3 withFlags:kCGEventFlagMaskCommand toProcess:waPid];
    [NSThread sleepForTimeInterval:0.5];
    
    // Type the query
    [self typeString:query toProcess:waPid];
    
    CFRelease(window);
    return YES;
}

#pragma mark - Navigation

- (BOOL)clickButtonWithIdentifier:(NSString *)identifier {
    AXUIElementRef window = [self getMainWindow];
    if (!window) return NO;
    
    BOOL result = NO;
    AXUIElementRef button = [self findElementWithIdentifier:identifier inElement:window];
    if (button) {
        result = [self pressElement:button];
        CFRelease(button);
    }
    
    CFRelease(window);
    return result;
}

- (BOOL)navigateToChats {
    return [self clickButtonWithIdentifier:@"TabBarButton_Chats"];
}

- (BOOL)navigateToCalls {
    return [self clickButtonWithIdentifier:@"TabBarButton_Calls"];
}

- (BOOL)navigateToArchived {
    return [self clickButtonWithIdentifier:@"TabBarButton_Archived"];
}

- (BOOL)navigateToSettings {
    return [self clickButtonWithIdentifier:@"TabBarButton_Settings"];
}

@end
