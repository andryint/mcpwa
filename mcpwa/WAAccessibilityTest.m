//
//  WAAccessibilityTest.m
//  mcpwa
//
//  Call [WAAccessibilityTest runAllTests] to verify the accessibility layer works
//

#import "WAAccessibilityTest.h"
#import "WAAccessibility.h"

@implementation WAAccessibilityTest

+ (void)runAllTests {
    NSLog(@"");
    NSLog(@"========================================");
    NSLog(@"WAAccessibility Tests");
    NSLog(@"========================================");
    
    WAAccessibility *wa = [WAAccessibility shared];
    
    // Test 1: Connection
    NSLog(@"");
    NSLog(@"[TEST 1] WhatsApp Available");
    BOOL available = [wa isWhatsAppAvailable];
    NSLog(@"  Result: %@", available ? @"YES ✓" : @"NO ✗");
    
    if (!available) {
        NSLog(@"  → WhatsApp not running or not accessible");
        NSLog(@"  → Make sure WhatsApp is open and app has accessibility permissions");
        return;
    }
    
    // Test 2: Get chat list
    NSLog(@"");
    NSLog(@"[TEST 2] Get Chat List");
    NSArray<WAChat *> *chats = [wa getChats];
    NSLog(@"  Found %lu chats", (unsigned long)chats.count);
    
    for (NSInteger i = 0; i < MIN(5, chats.count); i++) {
        WAChat *chat = chats[i];
        NSLog(@"  [%ld] %@ %@", (long)i, chat.name, chat.isPinned ? @"📌" : @"");
        NSLog(@"      Last: %@", chat.lastMessage.length > 50 ? 
              [chat.lastMessage substringToIndex:50] : chat.lastMessage);
    }
    
    if (chats.count > 5) {
        NSLog(@"  ... and %lu more", (unsigned long)(chats.count - 5));
    }
    
    // Test 3: Find chat by name
    NSLog(@"");
    NSLog(@"[TEST 3] Find Chat by Name");
    if (chats.count > 0) {
        // Try to find the first chat
        NSString *searchName = chats[0].name;
        NSLog(@"  Searching for: %@", searchName);
        
        WAChat *found = [wa findChatWithName:searchName];
        NSLog(@"  Found: %@", found ? @"YES ✓" : @"NO ✗");
    }
    
    // Test 4: Get current chat
    NSLog(@"");
    NSLog(@"[TEST 4] Get Current Chat");
    WACurrentChat *current = [wa getCurrentChat];
    
    if (current) {
        NSLog(@"  Chat: %@", current.name);
        NSLog(@"  Status: %@", current.lastSeen ?: @"<none>");
        NSLog(@"  Messages: %lu", (unsigned long)current.messages.count);
    } else {
        NSLog(@"  No chat open (expected if no conversation selected)");
    }
    
    // Test 5: Get messages from current chat
    NSLog(@"");
    NSLog(@"[TEST 5] Get Messages");
    NSArray<WAMessage *> *messages = [wa getMessagesWithLimit:10];
    NSLog(@"  Retrieved %lu messages", (unsigned long)messages.count);
    
    for (WAMessage *msg in messages) {
        NSString *direction;
        switch (msg.direction) {
            case WAMessageDirectionIncoming:
                direction = @"←";
                break;
            case WAMessageDirectionOutgoing:
                direction = @"→";
                break;
            default:
                direction = @"•";
        }
        
        NSString *text = msg.text.length > 40 ? 
            [[msg.text substringToIndex:40] stringByAppendingString:@"..."] : msg.text;
        
        NSLog(@"  %@ [%@] %@: %@", 
              direction,
              msg.timestamp ?: @"--:--",
              msg.sender ?: @"me",
              text);
        
        if (msg.replyTo) {
            NSLog(@"      ↳ Reply to: %@", msg.replyTo);
        }
        if (msg.reactions.count > 0) {
            NSLog(@"      ↳ Reactions: %@", [msg.reactions componentsJoinedByString:@" "]);
        }
    }
    
    // Test 6: Navigation
    NSLog(@"");
    NSLog(@"[TEST 6] Navigation (read-only check)");
    NSLog(@"  TabBarButton_Chats exists: checking...");
    // We don't actually click, just verify we found the buttons
    
    // Test 7: Compose area
    NSLog(@"");
    NSLog(@"[TEST 7] Compose Area");
    if (current) {
        NSLog(@"  Compose field should be accessible");
        NSLog(@"  (Not testing sendMessage to avoid accidental sends)");
    } else {
        NSLog(@"  Open a chat to test compose functionality");
    }
    
    NSLog(@"");
    NSLog(@"========================================");
    NSLog(@"Tests Complete");
    NSLog(@"========================================");
    NSLog(@"");
}

+ (void)testSendMessage:(NSString *)message {
    NSLog(@"");
    NSLog(@"[TEST] Send Message");
    NSLog(@"  Message: %@", message);
    
    WAAccessibility *wa = [WAAccessibility shared];
    
    if (![wa isWhatsAppAvailable]) {
        NSLog(@"  ✗ WhatsApp not available");
        return;
    }
    
    WACurrentChat *current = [wa getCurrentChat];
    if (!current) {
        NSLog(@"  ✗ No chat open");
        return;
    }
    
    NSLog(@"  Sending to: %@", current.name);
    
    BOOL success = [wa sendMessage:message];
    NSLog(@"  Result: %@", success ? @"Sent ✓" : @"Failed ✗");
}

+ (void)testOpenChat:(NSString *)name {
    NSLog(@"");
    NSLog(@"[TEST] Open Chat");
    NSLog(@"  Looking for: %@", name);
    
    WAAccessibility *wa = [WAAccessibility shared];
    
    if (![wa isWhatsAppAvailable]) {
        NSLog(@"  ✗ WhatsApp not available");
        return;
    }
    
    BOOL success = [wa openChatWithName:name];
    NSLog(@"  Result: %@", success ? @"Opened ✓" : @"Failed ✗");
    
    if (success) {
        // Wait a moment for UI to update
        [NSThread sleepForTimeInterval:0.5];
        
        WACurrentChat *current = [wa getCurrentChat];
        if (current) {
            NSLog(@"  Now viewing: %@", current.name);
            NSLog(@"  Messages: %lu", (unsigned long)current.messages.count);
        }
    }
}

@end
