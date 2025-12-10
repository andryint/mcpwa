//
//  WAAccessibilityExplorer.h
//  mcpwa
//
//  Standalone explorer for WhatsApp's accessibility tree
//  Usage: Call [WAAccessibilityExplorer explore] from anywhere (e.g., applicationDidFinishLaunching)
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface WAAccessibilityExplorer : NSObject

/// Run full exploration and print to console
+ (void)explore;

/// Explore with output to file
+ (void)exploreToFile:(NSString *)path;

/// Dump tree starting from app element
+ (void)dumpTree:(AXUIElementRef)element maxDepth:(int)maxDepth;

/// Find and dump elements matching a role
+ (void)findElementsWithRole:(NSString *)role inElement:(AXUIElementRef)root;

/// Dump all attributes of a single element
+ (void)dumpAttributes:(AXUIElementRef)element label:(NSString *)label;

@end

NS_ASSUME_NONNULL_END
