//
//  WAAccessibilityTest.h
//  mcpwa
//

#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>

@interface WAAccessibilityTest : NSObject

/// Run all basic tests
+ (void)runAllTests;

/// Test global search with a query
+ (void)testGlobalSearch:(NSString *)query;

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

+(void) testPressEsc;
+(void) testPressCmdF;
+(void) testPressA;
+(void) testPressX;
+(void) testTypeInABC;




@end
