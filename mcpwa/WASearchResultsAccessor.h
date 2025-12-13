// WASearchResultsAccessor.h
// Methods for collecting and navigating WhatsApp search results

#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>
#import "WASearchResult.h"

NS_ASSUME_NONNULL_BEGIN

@interface WASearchResultsAccessor : NSObject

/**
 * Get all visible search results from WhatsApp's search panel
 * Call this after performing a search and waiting for results
 */
- (NSArray<WASearchResult *> *)getSearchResults;

/**
 * Click on a search result to navigate to that message in context
 * @param index The 0-based index of the result to click
 * @return YES if click was successful
 */
- (BOOL)clickSearchResultAtIndex:(NSInteger)index;

/**
 * Get search results as JSON-ready array
 */
- (NSArray<NSDictionary *> *)getSearchResultsAsDictionaries;

@end

NS_ASSUME_NONNULL_END
