
#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>

#import "WAAccessibilityTest.h"
#import "WAAccessibility.h"
#import "WASearchResult.h"
#import "WASearchResultsAccessor.h"
#import "WALogger.h"

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
    NSArray<WAChat *> *chats = [wa getRecentChats];
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

+ (void)testGlobalSearch:(NSString *)query {
    NSLog(@"");
    NSLog(@"========================================");
    NSLog(@"[TEST] Global Search");
    NSLog(@"========================================");
    NSLog(@"  Query: \"%@\"", query);
    
    WAAccessibility *wa = [WAAccessibility shared];
    
    if (![wa isWhatsAppAvailable]) {
        NSLog(@"  ✗ WhatsApp not available");
        return;
    }
    
    NSLog(@"  Executing search...");
    NSDate *startTime = [NSDate date];
    
    WASearchResults *results = [wa globalSearch:query];
    
    NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:startTime];
    NSLog(@"  Completed in %.2f seconds", elapsed);
    
    if (!results) {
        NSLog(@"  ✗ Search returned nil");
        return;
    }
    
    NSLog(@"");
    NSLog(@"  === RESULTS ===");
    NSLog(@"  Chat matches: %lu", (unsigned long)results.chatMatches.count);
    NSLog(@"  Message matches: %lu", (unsigned long)results.messageMatches.count);
    
    // Show chat matches
    if (results.chatMatches.count > 0) {
        NSLog(@"");
        NSLog(@"  --- Chat Matches ---");
        for (WASearchChatResult *chat in results.chatMatches) {
            NSLog(@"  🔍 %@", chat.chatName);
            if (chat.lastMessagePreview) {
                NSString *preview = chat.lastMessagePreview.length > 50 ?
                    [[chat.lastMessagePreview substringToIndex:50] stringByAppendingString:@"..."] :
                    chat.lastMessagePreview;
                NSLog(@"     Last: %@", preview);
            }
        }
    }
    
    // Show message matches
    if (results.messageMatches.count > 0) {
        NSLog(@"");
        NSLog(@"  --- Message Matches ---");
        for (WASearchMessageResult *msg in results.messageMatches) {
            NSLog(@"  💬 [%@] %@", msg.chatName, msg.sender ?: @"You");
            NSString *preview = msg.messagePreview.length > 60 ?
                [[msg.messagePreview substringToIndex:60] stringByAppendingString:@"..."] :
                msg.messagePreview;
            NSLog(@"     \"%@\"", preview);
        }
    }
    
    if (results.chatMatches.count == 0 && results.messageMatches.count == 0) {
        NSLog(@"");
        NSLog(@"  ⚠️  No results found");
        NSLog(@"     This could mean:");
        NSLog(@"     - No matches exist for \"%@\"", query);
        NSLog(@"     - Search text wasn't entered (check AXTextArea detection)");
        NSLog(@"     - Results weren't scraped (timing issue?)");
    }
    
    NSLog(@"");
    NSLog(@"========================================");
}

+ (void)testClearSearch {
    NSLog(@"");
    NSLog(@"[TEST] Clear Search");
    
    WAAccessibility *wa = [WAAccessibility shared];
    
    if (![wa isWhatsAppAvailable]) {
        NSLog(@"  ✗ WhatsApp not available");
        return;
    }
    
    BOOL success = [wa clearSearch];
    NSLog(@"  Result: %@", success ? @"Cleared ✓" : @"Failed ✗");
}

+ (void)testClipboardPaste:(NSString *)text {
    NSLog(@"");
    NSLog(@"========================================");
    NSLog(@"[TEST] Clipboard Paste");
    NSLog(@"========================================");
    NSLog(@"  Text: \"%@\"", text);
    
    WAAccessibility *wa = [WAAccessibility shared];
    
    if (![wa isWhatsAppAvailable]) {
        NSLog(@"  ✗ WhatsApp not available");
        return;
    }
    
    // Get WhatsApp PID
    NSArray *apps = [[NSWorkspace sharedWorkspace] runningApplications];
    pid_t waPid = 0;
    for (NSRunningApplication *app in apps) {
        if ([app.bundleIdentifier isEqualToString:@"net.whatsapp.WhatsApp"]) {
            waPid = app.processIdentifier;
            break;
        }
    }
    
    if (waPid == 0) {
        NSLog(@"  ✗ WhatsApp PID not found");
        return;
    }
    
    NSLog(@"  WhatsApp PID: %d", waPid);
    
    // Press Cmd+F to open search
    NSLog(@"  Sending Cmd+F...");
    [self sendKey:3 withFlags:kCGEventFlagMaskCommand toProcess:waPid];
    [NSThread sleepForTimeInterval:0.5];
    
    // Put text on clipboard
    NSLog(@"  Setting clipboard...");
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:text forType:NSPasteboardTypeString];
    
    // Single Cmd+V paste
    NSLog(@"  Sending single Cmd+V...");
    [self sendKey:9 withFlags:kCGEventFlagMaskCommand toProcess:waPid];
    
    NSLog(@"  Done - check WhatsApp search field");
    NSLog(@"========================================");
}

+ (void)testCharacterTyping:(NSString *)text {
    NSLog(@"");
    NSLog(@"========================================");
    NSLog(@"[TEST] Character Typing");
    NSLog(@"========================================");
    NSLog(@"  Text: \"%@\"", text);
    
    WAAccessibility *wa = [WAAccessibility shared];
    
    if (![wa isWhatsAppAvailable]) {
        NSLog(@"  ✗ WhatsApp not available");
        return;
    }
    
    // Get WhatsApp PID
    NSArray *apps = [[NSWorkspace sharedWorkspace] runningApplications];
    pid_t waPid = 0;
    for (NSRunningApplication *app in apps) {
        if ([app.bundleIdentifier isEqualToString:@"net.whatsapp.WhatsApp"]) {
            waPid = app.processIdentifier;
            break;
        }
    }
    
    if (waPid == 0) {
        NSLog(@"  ✗ WhatsApp PID not found");
        return;
    }
    
    NSLog(@"  WhatsApp PID: %d", waPid);
    
    // Press Cmd+F to open search
    NSLog(@"  Sending Cmd+F...");
    [self sendKey:3 withFlags:kCGEventFlagMaskCommand toProcess:waPid];
    [NSThread sleepForTimeInterval:0.5];
    
    // Type characters one by one
    NSLog(@"  Typing characters...");
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar character = [text characterAtIndex:i];
        NSLog(@"    Typing: %C", character);
        
        CGEventRef keyDown = CGEventCreateKeyboardEvent(source, 0, true);
        CGEventRef keyUp = CGEventCreateKeyboardEvent(source, 0, false);
        
        UniChar chars[1] = { character };
        CGEventKeyboardSetUnicodeString(keyDown, 1, chars);
        CGEventKeyboardSetUnicodeString(keyUp, 1, chars);
        
        CGEventPostToPid(waPid, keyDown);
        [NSThread sleepForTimeInterval:0.05];
        CGEventPostToPid(waPid, keyUp);
        [NSThread sleepForTimeInterval:0.05];
        
        CFRelease(keyDown);
        CFRelease(keyUp);
    }
    
    if (source) CFRelease(source);
    
    NSLog(@"  Done - check WhatsApp search field");
    NSLog(@"========================================");
}

#pragma mark - Search Results Tests (NEW)

+ (void)testGetSearchResults {
    NSLog(@"");
    NSLog(@"========================================");
    NSLog(@"[TEST] Get Search Results (Parsed)");
    NSLog(@"========================================");
    NSLog(@"  NOTE: Run this AFTER a search is visible in WhatsApp");
    
    WASearchResultsAccessor *accessor = [[WASearchResultsAccessor alloc] init];
    NSArray<WASearchResult *> *results = [accessor getSearchResults];
    
    NSLog(@"");
    NSLog(@"  Found %lu parsed results", (unsigned long)results.count);
    
    if (results.count == 0) {
        NSLog(@"");
        NSLog(@"  ⚠️  No results found. Possible causes:");
        NSLog(@"     - No search is currently active");
        NSLog(@"     - Search panel is not visible");
        NSLog(@"     - 'Search results' container not found in AX tree");
        return;
    }
    
    NSLog(@"");
    NSLog(@"  --- Parsed Results ---");
    for (WASearchResult *result in results) {
        NSLog(@"");
        NSLog(@"  [%ld] %@ %@", 
              (long)result.index,
              result.isOutgoing ? @"→" : @"←",
              result.chatName ?: @"<no chat name>");
        
        if (result.snippet) {
            NSString *snippet = result.snippet.length > 60 ?
                [[result.snippet substringToIndex:60] stringByAppendingString:@"..."] :
                result.snippet;
            NSLog(@"      Snippet: \"%@\"", snippet);
        }
        
        if (result.date) {
            NSLog(@"      Date: %@", result.date);
        }
        
        if (result.attachmentType != WASearchResultAttachmentNone) {
            NSLog(@"      Attachment: %@ - %@", 
                  [self attachmentTypeName:result.attachmentType],
                  result.attachmentDescription ?: @"");
        }
        
        NSLog(@"      ElementRef: %@", result.elementRef ? @"valid" : @"NULL");
    }
    
    NSLog(@"");
    NSLog(@"========================================");
}

+ (void)testSearchAndParseResults:(NSString *)query {
    NSLog(@"");
    NSLog(@"========================================");
    NSLog(@"[TEST] Search And Parse Results");
    NSLog(@"========================================");
    NSLog(@"  Query: \"%@\"", query);
    
    WAAccessibility *wa = [WAAccessibility shared];
    
    if (![wa isWhatsAppAvailable]) {
        NSLog(@"  ✗ WhatsApp not available");
        return;
    }
    
    // Step 1: Execute search
    NSLog(@"");
    NSLog(@"  Step 1: Executing search...");
    NSDate *startTime = [NSDate date];
    
    WASearchResults *rawResults = [wa globalSearch:query];
    
    NSTimeInterval searchElapsed = [[NSDate date] timeIntervalSinceDate:startTime];
    NSLog(@"  Search completed in %.2f seconds", searchElapsed);
    NSLog(@"  Raw results: %lu chat matches, %lu message matches",
          (unsigned long)rawResults.chatMatches.count,
          (unsigned long)rawResults.messageMatches.count);
    
    // Step 2: Parse with new accessor
    NSLog(@"");
    NSLog(@"  Step 2: Parsing with WASearchResultsAccessor...");
    
    WASearchResultsAccessor *accessor = [[WASearchResultsAccessor alloc] init];
    NSArray<WASearchResult *> *parsedResults = [accessor getSearchResults];
    
    NSLog(@"  Parsed results: %lu", (unsigned long)parsedResults.count);
    
    // Step 3: Show comparison
    NSLog(@"");
    NSLog(@"  Step 3: Comparison");
    NSLog(@"  ┌─────────────────────────────────────────────────────────┐");
    NSLog(@"  │ Index │ Chat Name              │ Outgoing │ Has Date   │");
    NSLog(@"  ├─────────────────────────────────────────────────────────┤");
    
    for (WASearchResult *result in parsedResults) {
        NSString *chatName = result.chatName ?: @"<unknown>";
        if (chatName.length > 20) {
            chatName = [[chatName substringToIndex:17] stringByAppendingString:@"..."];
        }
        
        NSLog(@"  │ %5ld │ %-22@ │ %8@ │ %10@ │",
              (long)result.index,
              chatName,
              result.isOutgoing ? @"Yes" : @"No",
              result.date ? result.date : @"—");
    }
    
    NSLog(@"  └─────────────────────────────────────────────────────────┘");
    
    // Step 4: JSON output
    NSLog(@"");
    NSLog(@"  Step 4: JSON Output (for MCP)");
    NSArray<NSDictionary *> *jsonResults = [accessor getSearchResultsAsDictionaries];
    
    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonResults
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:&jsonError];
    if (jsonData) {
        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        NSLog(@"%@", jsonString);
    } else {
        NSLog(@"  ✗ JSON serialization failed: %@", jsonError);
    }
    
    NSLog(@"");
    NSLog(@"========================================");
}

+ (void)testClickSearchResult:(NSInteger)index {
    NSLog(@"");
    NSLog(@"========================================");
    NSLog(@"[TEST] Click Search Result");
    NSLog(@"========================================");
    NSLog(@"  Index: %ld", (long)index);
    NSLog(@"  NOTE: Search results must be visible");
    
    WASearchResultsAccessor *accessor = [[WASearchResultsAccessor alloc] init];
    
    // First, show what we're about to click
    NSArray<WASearchResult *> *results = [accessor getSearchResults];
    
    if (results.count == 0) {
        NSLog(@"  ✗ No search results found");
        return;
    }
    
    if (index < 0 || index >= results.count) {
        NSLog(@"  ✗ Index out of range (0-%lu)", (unsigned long)(results.count - 1));
        return;
    }
    
    WASearchResult *target = results[index];
    NSLog(@"  Target: %@ - \"%@\"", 
          target.chatName ?: @"<unknown>",
          target.snippet.length > 40 ? 
              [[target.snippet substringToIndex:40] stringByAppendingString:@"..."] :
              target.snippet);
    
    // Perform click
    NSLog(@"");
    NSLog(@"  Clicking...");
    BOOL success = [accessor clickSearchResultAtIndex:index];
    
    if (success) {
        NSLog(@"  ✓ Click sent successfully");
        NSLog(@"  Waiting for navigation...");
        [NSThread sleepForTimeInterval:0.8];
        
        // Check what chat is now open
        WAAccessibility *wa = [WAAccessibility shared];
        WACurrentChat *current = [wa getCurrentChat];
        
        if (current) {
            NSLog(@"");
            NSLog(@"  Now viewing: %@", current.name);
            NSLog(@"  Messages visible: %lu", (unsigned long)current.messages.count);
            
            // Show a few messages around where we landed
            NSLog(@"");
            NSLog(@"  --- Visible Messages ---");
            NSArray<WAMessage *> *messages = [wa getMessagesWithLimit:5];
            for (WAMessage *msg in messages) {
                NSString *text = msg.text.length > 50 ?
                    [[msg.text substringToIndex:50] stringByAppendingString:@"..."] :
                    msg.text;
                NSLog(@"  [%@] %@: %@", 
                      msg.timestamp ?: @"--:--",
                      msg.sender ?: @"You",
                      text);
            }
        } else {
            NSLog(@"  ⚠️  No chat open after click");
        }
    } else {
        NSLog(@"  ✗ Click failed");
        NSLog(@"     - ElementRef may be stale");
        NSLog(@"     - Search results may have changed");
    }
    
    NSLog(@"");
    NSLog(@"========================================");
}

+ (void)testParseSearchResultDescription:(NSString *)desc {
    NSLog(@"");
    NSLog(@"========================================");
    NSLog(@"[TEST] Parse Search Result Description");
    NSLog(@"========================================");
    NSLog(@"  Input: \"%@\"", desc);
    
    WASearchResult *result = [WASearchResult parseFromDescription:desc withIndex:0];
    
    if (!result) {
        NSLog(@"  ✗ Parsing returned nil");
        return;
    }
    
    NSLog(@"");
    NSLog(@"  Parsed fields:");
    NSLog(@"    chatName:   %@", result.chatName ?: @"<nil>");
    NSLog(@"    snippet:    %@", result.snippet ?: @"<nil>");
    NSLog(@"    date:       %@", result.date ?: @"<nil>");
    NSLog(@"    isOutgoing: %@", result.isOutgoing ? @"YES" : @"NO");
    
    NSLog(@"");
    NSLog(@"  As dictionary:");
    NSDictionary *dict = [result toDictionary];
    for (NSString *key in dict) {
        NSLog(@"    %@: %@", key, dict[key]);
    }
    
    NSLog(@"");
    NSLog(@"========================================");
}

#pragma mark - Helper Methods

+ (void)sendKey:(CGKeyCode)keyCode withFlags:(CGEventFlags)flags toProcess:(pid_t)pid {
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    CGEventRef keyDown = CGEventCreateKeyboardEvent(source, keyCode, true);
    CGEventRef keyUp = CGEventCreateKeyboardEvent(source, keyCode, false);
    
    if (flags) {
        CGEventSetFlags(keyDown, flags);
        CGEventSetFlags(keyUp, flags);
    }
    
    CGEventPostToPid(pid, keyDown);
    [NSThread sleepForTimeInterval:0.05];
    CGEventPostToPid(pid, keyUp);
    
    CFRelease(keyDown);
    CFRelease(keyUp);
    if (source) CFRelease(source);
}

+ (NSString *)attachmentTypeName:(WASearchResultAttachment)type {
    switch (type) {
        case WASearchResultAttachmentNone: return @"none";
        case WASearchResultAttachmentImage: return @"image";
        case WASearchResultAttachmentLink: return @"link";
        case WASearchResultAttachmentDocument: return @"document";
    }
}


+(void) testPressEsc
{
    AXUIElementRef window = [[WAAccessibility shared] getMainWindow];
    if (!window) {
        NSLog(@"ERROR: can't get the WhatsApp main window");
        return;
    }

    pid_t waPid = [WAAccessibility shared].whatsappPID;
    
    if (waPid == 0) {
        NSLog(@"ERROR: can't get the WhatsApp PID");
        CFRelease(window);
        return;
    }

    @try {
        
        [[WAAccessibility shared] pressKey:53 withFlags:0 toProcess:waPid];  // Escape
        NSLog(@"Sent pressKey: ESC");
//        [NSThread sleepForTimeInterval:1.0];
        
    } @catch (NSException *exception) {
        NSLog(@"WAAccessibility: Exception in globalSearch: %@", exception);
    }
        
    CFRelease(window);
}

+(void) testPressCmdF
{
    AXUIElementRef window = [[WAAccessibility shared] getMainWindow];
    if (!window) {
        NSLog(@"ERROR: can't get the WhatsApp main window");
        return;
    }

    pid_t waPid = [WAAccessibility shared].whatsappPID;
    
    if (waPid == 0) {
        NSLog(@"ERROR: can't get the WhatsApp PID");
        CFRelease(window);
        return;
    }

    @try {
        [[WAAccessibility shared] pressKey:3 withFlags:kCGEventFlagMaskCommand toProcess:waPid];
        NSLog(@"Sent pressKey: Command+F");
//        [NSThread sleepForTimeInterval:1.0];
        
    } @catch (NSException *exception) {
        NSLog(@"WAAccessibility: Exception in globalSearch: %@", exception);
    }
        
    CFRelease(window);
}

+(void) testPressCmdV
{
    AXUIElementRef window = [[WAAccessibility shared] getMainWindow];
    if (!window) {
        NSLog(@"ERROR: can't get the WhatsApp main window");
        return;
    }

    pid_t waPid = [WAAccessibility shared].whatsappPID;
    
    if (waPid == 0) {
        NSLog(@"ERROR: can't get the WhatsApp PID");
        CFRelease(window);
        return;
    }

    @try {
        [[WAAccessibility shared] pressKey:9 withFlags:kCGEventFlagMaskCommand toProcess:waPid];
        NSLog(@"Sent pressKey: Command+V");
//        [NSThread sleepForTimeInterval:1.0];
        
    } @catch (NSException *exception) {
        NSLog(@"WAAccessibility: Exception in globalSearch: %@", exception);
    }
        
    CFRelease(window);
}

+(void) testPressA
{
    AXUIElementRef window = [[WAAccessibility shared] getMainWindow];
    if (!window) {
        NSLog(@"ERROR: can't get the WhatsApp main window");
        return;
    }

    pid_t waPid = [WAAccessibility shared].whatsappPID;
    
    if (waPid == 0) {
        NSLog(@"ERROR: can't get the WhatsApp PID");
        CFRelease(window);
        return;
    }

    @try {
        [[WAAccessibility shared] pressKey:0 withFlags:0 toProcess:waPid];
        NSLog(@"Sent pressKey: Command+V");
//        [NSThread sleepForTimeInterval:1.0];
        
    } @catch (NSException *exception) {
        NSLog(@"WAAccessibility: Exception in globalSearch: %@", exception);
    }
        
    CFRelease(window);
}

+(void) testPressX
{
    AXUIElementRef window = [[WAAccessibility shared] getMainWindow];
    if (!window) {
        NSLog(@"ERROR: can't get the WhatsApp main window");
        return;
    }

    pid_t waPid = [WAAccessibility shared].whatsappPID;
    
    if (waPid == 0) {
        NSLog(@"ERROR: can't get the WhatsApp PID");
        CFRelease(window);
        return;
    }

    @try {
        [[WAAccessibility shared] pressKey:7 withFlags:0 toProcess:waPid];
        NSLog(@"Sent pressKey: Command+V");
//        [NSThread sleepForTimeInterval:1.0];
        
    } @catch (NSException *exception) {
        NSLog(@"WAAccessibility: Exception in globalSearch: %@", exception);
    }
        
    CFRelease(window);
}

+(void) testTypeInABC
{
    AXUIElementRef window = [[WAAccessibility shared] getMainWindow];
    if (!window) {
        NSLog(@"ERROR: can't get the WhatsApp main window");
        return;
    }

    pid_t waPid = [WAAccessibility shared].whatsappPID;
    
    if (waPid == 0) {
        NSLog(@"ERROR: can't get the WhatsApp PID");
        CFRelease(window);
        return;
    }

    @try {
        [[NSPasteboard generalPasteboard] clearContents];
        [[NSPasteboard generalPasteboard] setString:@"ABC" forType:NSPasteboardTypeString];
        [[WAAccessibility shared] pressKey:kVK_ANSI_V withFlags:kCGEventFlagMaskCommand toProcess:waPid];
        
        [[WAAccessibility shared] pressKey:36 withFlags:kCGEventFlagMaskCommand toProcess:waPid];


        NSLog(@"Send string: ABC");
        
    } @catch (NSException *exception) {
        NSLog(@"WAAccessibility: Exception in globalSearch: %@", exception);
    }
        
    CFRelease(window);
}

+ (void)testGetCurrentChat {
    WAAccessibility *wa = [WAAccessibility shared];

    WACurrentChat *current = [wa getCurrentChat];

    if (!current) {
        [WALogger error:@"   No chat open"];
        return;
    }

    for (WAMessage *msg in current.messages) {
        [WALogger error:@"\t %@", msg.text];
    }
}

+ (void)testReadChatList {
    NSLog(@"");
    NSLog(@"========================================");
    NSLog(@"[TEST] Read Chat List");
    NSLog(@"========================================");

    WAAccessibility *wa = [WAAccessibility shared];

    if (![wa isWhatsAppAvailable]) {
        NSLog(@"  ✗ WhatsApp not available");
        return;
    }

    NSArray<WAChat *> *chats = [wa getRecentChats];
    NSLog(@"  Found %lu chats", (unsigned long)chats.count);

    for (NSInteger i = 0; i < chats.count; i++) {
        WAChat *chat = chats[i];
        NSLog(@"  [%ld] %@ %@", (long)i, chat.name, chat.isPinned ? @"📌" : @"");
        if (chat.lastMessage.length > 0) {
            NSString *preview = chat.lastMessage.length > 50 ?
                [[chat.lastMessage substringToIndex:50] stringByAppendingString:@"..."] :
                chat.lastMessage;
            NSLog(@"      Last: %@", preview);
        }
    }

    NSLog(@"");
    NSLog(@"========================================");
}

+ (void)testParsingUnitTests {
    NSLog(@"\n\n=== PARSING UNIT TESTS ===\n");

    // Test case 1: Simple incoming
    [self testParseSearchResultDescription:
        @"Igor Berezovsky, это необязательно. как раз второе предложение"];

    // Test case 2: Outgoing with You:
    [self testParseSearchResultDescription:
        @"Igor Berezovsky, ⁨You⁩: …multiple AI services (ChatGPT, Claude, Gemini"];

    // Test case 3: With date
    [self testParseSearchResultDescription:
        @"Igor Berezovsky, Here Evren used ChatGPT to some extent as well:, 29/11/2025"];

    // Test case 4: Group chat
    [self testParseSearchResultDescription:
        @"Chess club Monaco 🇲🇨 ♟, Bonjour! pour Grasse, 13 et 14 decembre"];

    // Test case 5: Cyrillic
    [self testParseSearchResultDescription:
        @"Tania Melamed ( Chess, Шахматы ), Я не с ним - он в Grasse с мамой"];

    NSLog(@"\n=== END PARSING TESTS ===\n");
}

@end
