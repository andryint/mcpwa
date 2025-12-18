// WASearchResultsAccessor.m
// Implementation for collecting and navigating WhatsApp search results

#import <Cocoa/Cocoa.h>
#import "WASearchResultsAccessor.h"

@interface WASearchResultsAccessor ()
@property (nonatomic, assign) AXUIElementRef whatsAppApp;
@property (nonatomic, strong) NSMutableArray<WASearchResult *> *cachedResults;
@end

@implementation WASearchResultsAccessor

- (instancetype)init {
    self = [super init];
    if (self) {
        _cachedResults = [NSMutableArray array];
        [self findWhatsApp];
    }
    return self;
}

- (void)dealloc {
    if (_whatsAppApp) {
        CFRelease(_whatsAppApp);
    }
}

#pragma mark - WhatsApp Discovery

- (BOOL)findWhatsApp {
    if (_whatsAppApp) {
        CFRelease(_whatsAppApp);
        _whatsAppApp = NULL;
    }
    
    NSArray *apps = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"net.whatsapp.WhatsApp"];
    if (apps.count == 0) {
        return NO;
    }
    
    NSRunningApplication *app = apps.firstObject;
    _whatsAppApp = AXUIElementCreateApplication(app.processIdentifier);
    return (_whatsAppApp != NULL);
}

#pragma mark - AX Helpers

- (NSString *)getStringAttribute:(CFStringRef)attribute fromElement:(AXUIElementRef)element {
    CFTypeRef value = NULL;
    AXError error = AXUIElementCopyAttributeValue(element, attribute, &value);
    if (error != kAXErrorSuccess || !value) {
        return nil;
    }
    
    NSString *result = nil;
    if (CFGetTypeID(value) == CFStringGetTypeID()) {
        result = [(__bridge NSString *)value copy];
    }
    CFRelease(value);
    return result;
}

- (NSArray *)getChildren:(AXUIElementRef)element {
    CFTypeRef children = NULL;
    AXError error = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute, &children);
    if (error != kAXErrorSuccess || !children) {
        return @[];
    }
    
    NSArray *result = [(__bridge NSArray *)children copy];
    CFRelease(children);
    return result;
}

#pragma mark - Search Results Discovery

/**
 * Find the "Search results" group in WhatsApp's UI hierarchy
 * Path: AXWindow → AXGroup(iOSContentGroup) → ... → AXGroup desc:"Search results"
 */
- (AXUIElementRef)findSearchResultsContainer {
    if (!_whatsAppApp) {
        if (![self findWhatsApp]) {
            return NULL;
        }
    }
    
    // Get main window
    CFTypeRef windowValue = NULL;
    AXUIElementCopyAttributeValue(_whatsAppApp, kAXMainWindowAttribute, &windowValue);
    if (!windowValue) {
        return NULL;
    }
    
    AXUIElementRef window = (AXUIElementRef)windowValue;
    AXUIElementRef result = [self findElementWithDescription:@"Search results" 
                                                  startingFrom:window 
                                                     maxDepth:8];
    
    CFRelease(window);
    return result;
}

/**
 * Recursive search for element with matching AXDescription
 */
- (AXUIElementRef)findElementWithDescription:(NSString *)targetDesc 
                                startingFrom:(AXUIElementRef)element 
                                    maxDepth:(int)depth {
    if (depth <= 0 || !element) {
        return NULL;
    }
    
    NSString *desc = [self getStringAttribute:kAXDescriptionAttribute fromElement:element];
    if ([desc isEqualToString:targetDesc]) {
        CFRetain(element);
        return element;
    }
    
    NSArray *children = [self getChildren:element];
    for (id child in children) {
        AXUIElementRef childElement = (__bridge AXUIElementRef)child;
        AXUIElementRef found = [self findElementWithDescription:targetDesc 
                                                    startingFrom:childElement 
                                                        maxDepth:depth - 1];
        if (found) {
            return found;
        }
    }
    
    return NULL;
}

#pragma mark - Public Methods

- (NSArray<WASearchResult *> *)getSearchResults {
    [_cachedResults removeAllObjects];
    
    AXUIElementRef container = [self findSearchResultsContainer];
    if (!container) {
        return @[];
    }
    
    NSInteger resultIndex = 0;
    NSArray *children = [self getChildren:container];
    
    for (id child in children) {
        AXUIElementRef childElement = (__bridge AXUIElementRef)child;
        
        // Check if this is a message result
        NSString *identifier = [self getStringAttribute:CFSTR("AXIdentifier") fromElement:childElement];
        
        if ([identifier isEqualToString:@"ChatListSearchView_MessageResult"]) {
            WASearchResult *result = [self parseSearchResultElement:childElement 
                                                          atIndex:resultIndex];
            if (result) {
                [_cachedResults addObject:result];
                resultIndex++;
            }
        }
    }
    
    CFRelease(container);
    return [_cachedResults copy];
}

/**
 * Parse a single search result element
 * Structure:
 *   AXGroup id:ChatListSearchView_MessageResult [1-2 children]
 *     AXStaticText id:ChatListSearchView_MessageResult desc:"ChatName, snippet..."
 *     AXButton id:SearchResultsMessageRow_VisualMedia/NonvisualMedia (optional)
 */
- (WASearchResult *)parseSearchResultElement:(AXUIElementRef)element 
                                     atIndex:(NSInteger)index {
    NSArray *children = [self getChildren:element];
    if (children.count == 0) {
        return nil;
    }
    
    // First child is the static text with message info
    AXUIElementRef textElement = (__bridge AXUIElementRef)children.firstObject;
    NSString *desc = [self getStringAttribute:kAXDescriptionAttribute fromElement:textElement];
    
    WASearchResult *result = [WASearchResult parseFromDescription:desc withIndex:index];
    if (!result) {
        return nil;
    }
    
    // Store element ref for clicking (caller must use immediately, not retained)
    result.elementRef = element;
    
    // Check for attachment button
    if (children.count > 1) {
        AXUIElementRef attachButton = (__bridge AXUIElementRef)children[1];
        NSString *attachId = [self getStringAttribute:CFSTR("AXIdentifier") fromElement:attachButton];
        NSString *attachDesc = [self getStringAttribute:kAXDescriptionAttribute fromElement:attachButton];
        [result parseAttachmentFromDescription:attachDesc withIdentifier:attachId];
    }
    
    return result;
}

- (NSArray<NSDictionary *> *)getSearchResultsAsDictionaries {
    NSArray<WASearchResult *> *results = [self getSearchResults];
    NSMutableArray<NSDictionary *> *dictionaries = [NSMutableArray arrayWithCapacity:results.count];

    for (WASearchResult *result in results) {
        [dictionaries addObject:[result toDictionary]];
    }

    return [dictionaries copy];
}

- (BOOL)clickSearchResultAtIndex:(NSInteger)index {
    // Get fresh reference - don't use cached
    AXUIElementRef container = [self findSearchResultsContainer];
    if (!container) {
        NSLog(@"Could not find search results container");
        return NO;
    }
    
    NSArray *children = [self getChildren:container];
    NSInteger resultIndex = 0;
    BOOL success = NO;
    
    NSLog(@"Scanning %lu children for MessageResult...", (unsigned long)children.count);
    
    for (id child in children) {
        AXUIElementRef childElement = (__bridge AXUIElementRef)child;
        NSString *identifier = [self getStringAttribute:CFSTR("AXIdentifier") fromElement:childElement];
        
        if ([identifier isEqualToString:@"ChatListSearchView_MessageResult"]) {
            NSLog(@"Found MessageResult at position %ld (looking for %ld)", (long)resultIndex, (long)index);
            
            if (resultIndex == index) {
                AXUIElementRef clickTarget = childElement;
                NSArray *grandchildren = nil;  // Declare outside the if

                NSString *role = [self getStringAttribute:kAXRoleAttribute fromElement:childElement];
                NSLog(@"Element role: %@", role);

                if ([role isEqualToString:@"AXGroup"]) {
                    grandchildren = [self getChildren:childElement];  // Stays alive
                    NSLog(@"Group has %lu children", (unsigned long)grandchildren.count);
                    
                    if (grandchildren.count > 0) {
                        clickTarget = (__bridge AXUIElementRef)grandchildren.firstObject;
                        NSString *childRole = [self getStringAttribute:kAXRoleAttribute fromElement:clickTarget];
                        NSLog(@"Using child element (role: %@) instead of Group", childRole);
                    }
                }
                
                // Debug: show available actions
                CFArrayRef actions = NULL;
                AXUIElementCopyActionNames(clickTarget, &actions);
                NSLog(@"Actions on click target: %@", actions);
                if (actions) CFRelease(actions);
                
                // Perform the click
                AXError error = AXUIElementPerformAction(clickTarget, kAXPressAction);
                NSLog(@"AXPress result: %d (0 = success)", (int)error);
                success = (error == kAXErrorSuccess);
                break;
            }
            resultIndex++;
        }
    }
    
    NSLog(@"Scanned %ld MessageResults total", (long)resultIndex);
    CFRelease(container);
    return success;
}
@end
