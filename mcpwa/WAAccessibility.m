//
//  WAAccessibility.m
//  mcpwa
//
//  Accessibility interface for WhatsApp Desktop
//

#import "WAAccessibility.h"
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
    
    // Remove LTR mark (U+200E) and other direction marks
    NSMutableString *clean = [str mutableCopy];
    [clean replaceOccurrencesOfString:@"\u200E" withString:@"" options:0 range:NSMakeRange(0, clean.length)];
    [clean replaceOccurrencesOfString:@"\u200F" withString:@"" options:0 range:NSMakeRange(0, clean.length)];
    [clean replaceOccurrencesOfString:@"\u200B" withString:@"" options:0 range:NSMakeRange(0, clean.length)];
    
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
            return [app activateWithOptions:NSApplicationActivateIgnoringOtherApps];
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

#pragma mark - Chat List

- (NSArray<WAChat *> *)getChats {
    AXUIElementRef window = [self getMainWindow];
    if (!window) return @[];
    
    NSMutableArray<WAChat *> *chats = [NSMutableArray array];
    
    // Find all ChatSessionCell buttons (returns retained elements)
    NSArray *buttons = [self findElementsIn:window predicate:^BOOL(AXUIElementRef element, NSString *role, NSString *identifier) {
        return [role isEqualToString:@"AXButton"] && 
               [identifier hasPrefix:@"ChatSessionCell_"];
    } maxDepth:15];
    
    NSInteger index = 0;
    for (id btn in buttons) {
        AXUIElementRef button = (__bridge AXUIElementRef)btn;
        
        WAChat *chat = [[WAChat alloc] init];
        chat.index = index++;
        
        // Name is in AXDescription
        chat.name = [self descriptionOfElement:button] ?: @"Unknown";
        
        // Preview info is in AXValue
        NSString *value = [self valueOfElement:button];
        if (value) {
            [self parseChatValue:value intoChat:chat];
        }
        
        [chats addObject:chat];
    }
    
    // Release all elements in the buttons array
    for (id btn in buttons) {
        CFRelease((__bridge AXUIElementRef)btn);
    }
    
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
    
    // Try to extract timestamp - look for patterns like "12:23" or "6Decemberat"
    NSRegularExpression *timeRegex = [NSRegularExpression regularExpressionWithPattern:@"(\\d{1,2}:\\d{2})" options:0 error:nil];
    NSTextCheckingResult *match = [timeRegex firstMatchInString:value options:0 range:NSMakeRange(0, value.length)];
    if (match) {
        chat.timestamp = [value substringWithRange:match.range];
    }
}

- (WAChat *)findChatWithName:(NSString *)name {
    NSArray<WAChat *> *chats = [self getChats];
    NSString *lowercaseName = [name lowercaseString];
    
    // First try exact match
    for (WAChat *chat in chats) {
        if ([[chat.name lowercaseString] isEqualToString:lowercaseName]) {
            return chat;
        }
    }
    
    // Then try contains match
    for (WAChat *chat in chats) {
        if ([[chat.name lowercaseString] containsString:lowercaseName]) {
            return chat;
        }
    }
    
    return nil;
}

- (BOOL)openChat:(WAChat *)chat {
    AXUIElementRef window = [self getMainWindow];
    if (!window) return NO;
    
    BOOL result = NO;
    
    // Find the specific chat button (returns retained elements)
    NSArray *buttons = [self findElementsIn:window predicate:^BOOL(AXUIElementRef element, NSString *role, NSString *identifier) {
        return [role isEqualToString:@"AXButton"] && 
               [identifier hasPrefix:@"ChatSessionCell_"];
    } maxDepth:15];
    
    for (id btn in buttons) {
        AXUIElementRef button = (__bridge AXUIElementRef)btn;
        NSString *desc = [self descriptionOfElement:button];
        
        if ([desc isEqualToString:chat.name]) {
            result = [self pressElement:button];
            break;
        }
    }
    
    // Release all elements in the buttons array
    for (id btn in buttons) {
        CFRelease((__bridge AXUIElementRef)btn);
    }
    
    CFRelease(window);
    return result;
}

- (BOOL)openChatWithName:(NSString *)name {
    WAChat *chat = [self findChatWithName:name];
    if (chat) {
        return [self openChat:chat];
    }
    return NO;
}

#pragma mark - Current Chat

- (WACurrentChat *)getCurrentChat {
    AXUIElementRef window = [self getMainWindow];
    if (!window) return nil;
    
    // Find the header with NavigationBar_HeaderViewButton
    AXUIElementRef header = [self findElementWithIdentifier:@"NavigationBar_HeaderViewButton" inElement:window];
    if (!header) {
        CFRelease(window);
        return nil;
    }
    
    WACurrentChat *current = [[WACurrentChat alloc] init];
    current.name = [self descriptionOfElement:header];
    current.lastSeen = [self valueOfElement:header];
    
    CFRelease(header);  // Release retained header
    
    current.messages = [self getMessages];
    
    CFRelease(window);
    return current;
}

- (NSArray<WAMessage *> *)getMessages {
    return [self getMessagesWithLimit:100];
}

- (NSArray<WAMessage *> *)getMessagesWithLimit:(NSInteger)limit {
    AXUIElementRef window = [self getMainWindow];
    if (!window) return @[];
    
    // Find ChatMessagesTableView
    AXUIElementRef messagesTable = [self findElementWithIdentifier:@"ChatMessagesTableView" inElement:window];
    if (!messagesTable) {
        CFRelease(window);
        return @[];
    }
    
    NSMutableArray<WAMessage *> *messages = [NSMutableArray array];
    NSMutableArray *allFoundElements = [NSMutableArray array];  // Track all found elements for release
    
    @try {
        // Find all message bubbles
        NSArray *bubbles = [self findElementsIn:messagesTable predicate:^BOOL(AXUIElementRef element, NSString *role, NSString *identifier) {
            return identifier && [identifier isEqualToString:@"WAMessageBubbleTableViewCell"];
        } maxDepth:5];
        [allFoundElements addObjectsFromArray:bubbles];
        
        for (id bubble in bubbles) {
            if (messages.count >= limit) break;
            if (!bubble || bubble == [NSNull null]) continue;
            
            AXUIElementRef bubbleElement = (__bridge AXUIElementRef)bubble;
            if (!bubbleElement) continue;
            
            // Validate bubble is still valid
            CFTypeRef testVal = NULL;
            if (AXUIElementCopyAttributeValue(bubbleElement, kAXRoleAttribute, &testVal) != kAXErrorSuccess) {
                continue;  // Element is stale
            }
            if (testVal) CFRelease(testVal);
            
            // Find the AXGenericElement inside with the message content
            NSArray *generics = [self findElementsIn:bubbleElement predicate:^BOOL(AXUIElementRef element, NSString *role, NSString *identifier) {
                return role && [role isEqualToString:@"AXGenericElement"];
            } maxDepth:3];
            [allFoundElements addObjectsFromArray:generics];
            
            for (id gen in generics) {
                if (!gen || gen == [NSNull null]) continue;
                
                AXUIElementRef generic = (__bridge AXUIElementRef)gen;
                if (!generic) continue;
                
                NSString *desc = [self descriptionOfElement:generic];
                
                if (desc.length > 0) {
                    WAMessage *message = [self parseMessageDescription:desc];
                    if (message) {
                        // Check for reactions in the same bubble
                        NSArray *reactionButtons = [self findElementsIn:bubbleElement predicate:^BOOL(AXUIElementRef element, NSString *role, NSString *identifier) {
                            return identifier && [identifier isEqualToString:@"WAMessageReactionsSliceView"];
                        } maxDepth:3];
                        [allFoundElements addObjectsFromArray:reactionButtons];
                        
                        if (reactionButtons.count > 0) {
                            NSMutableArray *reactions = [NSMutableArray array];
                            for (id rb in reactionButtons) {
                                if (!rb || rb == [NSNull null]) continue;
                                NSString *reactionDesc = [self descriptionOfElement:(__bridge AXUIElementRef)rb];
                                // Format: "Reaction: 👍"
                                if (reactionDesc && [reactionDesc hasPrefix:@"Reaction: "]) {
                                    [reactions addObject:[reactionDesc substringFromIndex:10]];
                                }
                            }
                            message.reactions = reactions;
                        }
                        
                        [messages addObject:message];
                    }
                }
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"WAAccessibility: Exception in getMessagesWithLimit: %@", exception);
    }
    
    // Release all found elements
    for (id elem in allFoundElements) {
        if (elem && elem != [NSNull null]) {
            CFRelease((__bridge AXUIElementRef)elem);
        }
    }
    
    CFRelease(messagesTable);  // Release retained messagesTable
    CFRelease(window);
    return messages;
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

#pragma mark - Actions

- (BOOL)sendMessage:(NSString *)message {
    AXUIElementRef window = [self getMainWindow];
    if (!window) return NO;
    
    // Find the compose text area
    AXUIElementRef composeArea = [self findElementWithIdentifier:@"ChatBar_ComposerTextView" inElement:window];
    if (!composeArea) {
        CFRelease(window);
        return NO;
    }
    
    // Focus and set value
    [self setFocusOnElement:composeArea];
    
    // Small delay for focus
    [NSThread sleepForTimeInterval:0.1];
    
    // Set the text value
    if (![self setValueOfElement:composeArea to:message]) {
        CFRelease(composeArea);
        CFRelease(window);
        return NO;
    }
    
    // Need to simulate Enter key to send
    // AX doesn't directly support this, we'll use CGEvent
    CGEventRef keyDown = CGEventCreateKeyboardEvent(NULL, 36, true);  // 36 = Return key
    CGEventRef keyUp = CGEventCreateKeyboardEvent(NULL, 36, false);
    
    CGEventPost(kCGHIDEventTap, keyDown);
    CGEventPost(kCGHIDEventTap, keyUp);
    
    CFRelease(keyDown);
    CFRelease(keyUp);
    
    CFRelease(composeArea);
    CFRelease(window);
    return YES;
}

- (BOOL)searchFor:(NSString *)query {
    AXUIElementRef window = [self getMainWindow];
    if (!window) return NO;
    
    BOOL result = NO;
    AXUIElementRef searchField = NULL;
    
    // Find search field
    searchField = [self findElementWithIdentifier:@"TokenizedSearchBar_TextView" inElement:window];
    if (!searchField) {
        // Try the search button first
        AXUIElementRef searchButton = [self findFirstElementIn:window predicate:^BOOL(AXUIElementRef element, NSString *role, NSString *identifier) {
            NSString *desc = [self descriptionOfElement:element];
            return role && desc && [role isEqualToString:@"AXButton"] && [desc isEqualToString:@"Search"];
        } maxDepth:15];
        
        if (searchButton) {
            [self pressElement:searchButton];
            CFRelease(searchButton);
            [NSThread sleepForTimeInterval:0.3];
            
            // Try to find search field again
            searchField = [self findElementWithIdentifier:@"TokenizedSearchBar_TextView" inElement:window];
        }
    }
    
    if (searchField) {
        [self setFocusOnElement:searchField];
        [NSThread sleepForTimeInterval:0.1];
        result = [self setValueOfElement:searchField to:query];
        CFRelease(searchField);
    }
    
    CFRelease(window);
    return result;
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
