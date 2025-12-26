//
//  WAAccessibilityTest.h
//  mcpwa
//

#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>
#import "WAAccessibility.h"

@interface WAAccessibilityTest : NSObject

/// Run all basic tests
+ (void)runAllTests;

/// Test global search with a query
+ (void)testGlobalSearch:(NSString *)query;

/// Test global search with a query and filter
+ (void)testGlobalSearchWithFilter:(NSString *)query filter:(NSString *)filter;

/// Test sending a message (use with caution!)
+ (void)testSendMessage:(NSString *)message;

/// Test opening a chat by name
+ (void)testOpenChat:(NSString *)name;

/// Test clearing search
+ (void)testClearSearch;

/// Test clipboard paste approach for text input
+ (void)testClipboardPaste:(NSString *)text;

/// Test character-by-character typing approach
+ (void)testCharacterTyping:(NSString *)text;

#pragma mark - Search Results Tests (NEW)

/// Test parsing search results after a search is performed
/// Call this AFTER testGlobalSearch: with results visible
+ (void)testGetSearchResults;

/// Test the full search-and-parse workflow
+ (void)testSearchAndParseResults:(NSString *)query;

/// Test clicking on a search result by index
+ (void)testClickSearchResult:(NSInteger)index;

/// Test parsing a single description string (unit test style)
+ (void)testParseSearchResultDescription:(NSString *)desc;

+ (void)testPressEsc;
+ (void)testPressCmdF;
+ (void)testPressA;
+ (void)testPressX;
+ (void)testTypeInABC;
+ (void)testGetCurrentChat;
+ (void)testReadChatList;
+ (void)testParsingUnitTests;

#pragma mark - Chat Filter Tests

/// Test getting the currently selected chat filter
+ (void)testGetChatFilter;

/// Test setting a chat filter
+ (void)testSetChatFilter:(NSString *)filterName;

/// Test listing chats with a specific filter
+ (void)testListChatsWithFilter:(NSString *)filterName;

#pragma mark - Scroll Tests

/// Test scrolling the chat list down by one page
+ (void)testScrollChatsDown;

/// Test scrolling the chat list up by one page
+ (void)testScrollChatsUp;

@end
