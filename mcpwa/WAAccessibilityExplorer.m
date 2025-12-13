//
//  WAAccessibilityExplorer.m
//  mcpwa
//
//  Usage:
//    #import "WAAccessibilityExplorer.h"
//    [WAAccessibilityExplorer explore];
//
//  Or in AppDelegate.m applicationDidFinishLaunching:
//    [WAAccessibilityExplorer exploreToFile:@"/tmp/whatsapp_ax_tree.txt"];
//

#import "WAAccessibilityExplorer.h"
#import <ApplicationServices/ApplicationServices.h>

@implementation WAAccessibilityExplorer

#pragma mark - AX Helpers

+ (NSString *)stringAttribute:(CFStringRef)attr fromElement:(AXUIElementRef)element {
    CFTypeRef value = NULL;
    AXError err = AXUIElementCopyAttributeValue(element, attr, &value);
    if (err == kAXErrorSuccess && value) {
        NSString *str = (__bridge_transfer NSString *)value;
        return str;
    }
    return nil;
}

+ (NSArray *)childrenOfElement:(AXUIElementRef)element {
    CFTypeRef value = NULL;
    AXError err = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute, &value);
    if (err == kAXErrorSuccess && value) {
        return (__bridge_transfer NSArray *)value;
    }
    return @[];
}

+ (NSArray *)attributeNamesOfElement:(AXUIElementRef)element {
    CFArrayRef names = NULL;
    AXError err = AXUIElementCopyAttributeNames(element, &names);
    if (err == kAXErrorSuccess && names) {
        return (__bridge_transfer NSArray *)names;
    }
    return @[];
}

+ (NSString *)roleOfElement:(AXUIElementRef)element {
    return [self stringAttribute:kAXRoleAttribute fromElement:element] ?: @"?";
}

+ (NSString *)subroleOfElement:(AXUIElementRef)element {
    return [self stringAttribute:kAXSubroleAttribute fromElement:element];
}

+ (NSString *)titleOfElement:(AXUIElementRef)element {
    return [self stringAttribute:kAXTitleAttribute fromElement:element];
}

+ (NSString *)descriptionOfElement:(AXUIElementRef)element {
    return [self stringAttribute:kAXDescriptionAttribute fromElement:element];
}

+ (NSString *)valueOfElement:(AXUIElementRef)element {
    return [self stringAttribute:kAXValueAttribute fromElement:element];
}

+ (NSString *)identifierOfElement:(AXUIElementRef)element {
    return [self stringAttribute:CFSTR("AXIdentifier") fromElement:element];
}

#pragma mark - Output

static NSFileHandle *outputHandle = nil;

+ (void)log:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2) {
    va_list args;
    va_start(args, format);
    NSString *str = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    if (outputHandle) {
        [outputHandle writeData:[[str stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
    } else {
        NSLog(@"%@", str);
    }
}

#pragma mark - Tree Walking

+ (void)printElement:(AXUIElementRef)element depth:(int)depth {
    NSString *indent = [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0];
    
    NSString *role = [self roleOfElement:element];
    NSString *subrole = [self subroleOfElement:element];
    NSString *title = [self titleOfElement:element];
    NSString *desc = [self descriptionOfElement:element];
    id  value = [self valueOfElement:element];
    NSString *identifier = [self identifierOfElement:element];
    NSArray *children = [self childrenOfElement:element];
    
    NSMutableArray *parts = [NSMutableArray arrayWithObject:role];
    
    if (subrole) [parts addObject:[NSString stringWithFormat:@"(%@)", subrole]];
    if (identifier) [parts addObject:[NSString stringWithFormat:@"id:%@", identifier]];
    if (title.length > 0) {
        NSString *t = title.length > 50 ? [title substringToIndex:50] : title;
        [parts addObject:[NSString stringWithFormat:@"title:\"%@\"", t]];
    }
    if (desc.length > 0) {
        NSString *d = desc.length > 80 ? [desc substringToIndex:80] : desc;
        [parts addObject:[NSString stringWithFormat:@"desc:\"%@\"", d]];
    }
    if (value) {
        NSString *v;
        if ([value isKindOfClass:[NSString class]]) {
            v = [(NSString *)value length] > 50 ? [(NSString *)value substringToIndex:50] : (NSString *)value;
        } else {
            v = [value description];  // Convert NSNumber or other types to string
        }
        [parts addObject:[NSString stringWithFormat:@"val:\"%@\"", v]];
    }
    [parts addObject:[NSString stringWithFormat:@"[%lu children]", (unsigned long)children.count]];
    
    [self log:@"%@%@", indent, [parts componentsJoinedByString:@" "]];
}

+ (void)dumpTree:(AXUIElementRef)element maxDepth:(int)maxDepth {
    [self walkElement:element depth:0 maxDepth:maxDepth];
}

+ (void)walkElement:(AXUIElementRef)element depth:(int)depth maxDepth:(int)maxDepth {
    if (depth >= maxDepth) {
        NSString *indent = [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0];
        [self log:@"%@... (max depth)", indent];
        return;
    }
    
    [self printElement:element depth:depth];
    
    NSArray *children = [self childrenOfElement:element];
    for (id child in children) {
        AXUIElementRef childRef = (__bridge AXUIElementRef)child;
        [self walkElement:childRef depth:depth + 1 maxDepth:maxDepth];
    }
}

#pragma mark - Element Finding

+ (void)findElements:(AXUIElementRef)root
           predicate:(BOOL(^)(AXUIElementRef element, NSString *role, int depth))predicate
            maxDepth:(int)maxDepth
             results:(NSMutableArray *)results {
    
    [self searchElement:root predicate:predicate depth:0 maxDepth:maxDepth results:results];
}

+ (void)searchElement:(AXUIElementRef)element
            predicate:(BOOL(^)(AXUIElementRef, NSString *, int))predicate
                depth:(int)depth
             maxDepth:(int)maxDepth
              results:(NSMutableArray *)results {
    
    if (depth >= maxDepth) return;
    
    NSString *role = [self roleOfElement:element];
    if (predicate(element, role, depth)) {
        [results addObject:@{
            @"element": (__bridge id)element,
            @"role": role,
            @"depth": @(depth)
        }];
    }
    
    NSArray *children = [self childrenOfElement:element];
    for (id child in children) {
        [self searchElement:(__bridge AXUIElementRef)child
                  predicate:predicate
                      depth:depth + 1
                   maxDepth:maxDepth
                    results:results];
    }
}

+ (void)findElementsWithRole:(NSString *)targetRole inElement:(AXUIElementRef)root {
    NSMutableArray *results = [NSMutableArray array];
    
    [self findElements:root predicate:^BOOL(AXUIElementRef elem, NSString *role, int depth) {
        return [role isEqualToString:targetRole];
    } maxDepth:15 results:results];
    
    [self log:@"\n=== Found %lu elements with role %@ ===", (unsigned long)results.count, targetRole];
    
    for (NSDictionary *result in results) {
        AXUIElementRef elem = (__bridge AXUIElementRef)result[@"element"];
        int depth = [result[@"depth"] intValue];
        [self log:@"\ndepth=%d", depth];
        [self printElement:elem depth:0];
    }
}

#pragma mark - Attribute Dumping

+ (void)dumpAttributes:(AXUIElementRef)element label:(NSString *)label {
    [self log:@"\n=== All attributes for: %@ ===", label];
    
    NSArray *attrNames = [self attributeNamesOfElement:element];
    NSArray *sorted = [attrNames sortedArrayUsingSelector:@selector(compare:)];
    
    for (NSString *attr in sorted) {
        CFTypeRef value = NULL;
        AXError err = AXUIElementCopyAttributeValue(element, (__bridge CFStringRef)attr, &value);
        
        if (err == kAXErrorSuccess && value) {
            NSString *valStr = [NSString stringWithFormat:@"%@", (__bridge id)value];
            if (valStr.length > 100) {
                valStr = [valStr substringToIndex:100];
            }
            [self log:@"  %@: %@", attr, valStr];
            CFRelease(value);
        } else {
            [self log:@"  %@: <unavailable: %d>", attr, (int)err];
        }
    }
}

#pragma mark - WhatsApp Discovery

+ (AXUIElementRef)findWhatsApp {
    NSArray *apps = [[NSWorkspace sharedWorkspace] runningApplications];
    
    for (NSRunningApplication *app in apps) {
        if ([app.bundleIdentifier isEqualToString:@"net.whatsapp.WhatsApp"] ||
            [app.localizedName isEqualToString:@"WhatsApp"]) {
            [self log:@"Found WhatsApp: pid=%d name=%@", app.processIdentifier, app.localizedName];
            return AXUIElementCreateApplication(app.processIdentifier);
        }
    }
    return NULL;
}

#pragma mark - Main Exploration

+ (void)exploreApp:(AXUIElementRef)app {
    [self log:@"\n%@", [@"" stringByPaddingToLength:60 withString:@"=" startingAtIndex:0]];
    [self log:@"WHATSAPP ACCESSIBILITY TREE EXPLORER"];
    [self log:@"%@", [@"" stringByPaddingToLength:60 withString:@"=" startingAtIndex:0]];
    
    // 1. Full tree overview
    [self log:@"\n### FULL TREE (depth=6) ###\n"];
    [self dumpTree:app maxDepth:20];
    
    // 2. Windows
    [self log:@"\n### WINDOWS ###"];
    NSMutableArray *windows = [NSMutableArray array];
    [self findElements:app predicate:^BOOL(AXUIElementRef elem, NSString *role, int depth) {
        return [role isEqualToString:@"AXWindow"];
    } maxDepth:20 results:windows];
    
    for (NSDictionary *w in windows) {
        AXUIElementRef win = (__bridge AXUIElementRef)w[@"element"];
        NSString *title = [self titleOfElement:win] ?: @"<untitled>";
        [self log:@"\nWindow: %@", title];
        [self dumpAttributes:win label:@"Window"];
    }
    
    // 3. Buttons (potential chat items)
    [self log:@"\n### BUTTONS (potential chat items) ###"];
    NSMutableArray *buttons = [NSMutableArray array];
    [self findElements:app predicate:^BOOL(AXUIElementRef elem, NSString *role, int depth) {
        return [role isEqualToString:@"AXButton"];
    } maxDepth:25 results:buttons];
    
    [self log:@"Found %lu buttons", (unsigned long)buttons.count];
    
    int btnIdx = 0;
    for (NSDictionary *b in buttons) {
        if (btnIdx >= 20) break;
        
        AXUIElementRef btn = (__bridge AXUIElementRef)b[@"element"];
        int depth = [b[@"depth"] intValue];
        NSString *desc = [self descriptionOfElement:btn];
        
        [self log:@"\n[%d] depth=%d", btnIdx, depth];
        [self printElement:btn depth:0];
        
        // If description contains ":" likely a chat/message - dump all
        if (desc && [desc containsString:@":"]) {
            [self dumpAttributes:btn label:[NSString stringWithFormat:@"Button %d", btnIdx]];
        }
        btnIdx++;
    }
    
    // 4. Text areas
    [self log:@"\n### TEXT AREAS ###"];
    NSMutableArray *textAreas = [NSMutableArray array];
    [self findElements:app predicate:^BOOL(AXUIElementRef elem, NSString *role, int depth) {
        return [role isEqualToString:@"AXTextArea"] || [role isEqualToString:@"AXTextField"];
    } maxDepth:25 results:textAreas];
    
    for (NSDictionary *t in textAreas) {
        AXUIElementRef ta = (__bridge AXUIElementRef)t[@"element"];
        int depth = [t[@"depth"] intValue];
        [self log:@"\ndepth=%d", depth];
        [self printElement:ta depth:0];
        [self dumpAttributes:ta label:@"TextArea"];
    }
    
    // 5. Static text sample
    [self log:@"\n### STATIC TEXT (sample) ###"];
    NSMutableArray *staticTexts = [NSMutableArray array];
    [self findElements:app predicate:^BOOL(AXUIElementRef elem, NSString *role, int depth) {
        return [role isEqualToString:@"AXStaticText"];
    } maxDepth:25 results:staticTexts];
    
    [self log:@"Found %lu static text elements", (unsigned long)staticTexts.count];
    
    int stIdx = 0;
    for (NSDictionary *st in staticTexts) {
        if (stIdx >= 15) break;
        AXUIElementRef elem = (__bridge AXUIElementRef)st[@"element"];
        int depth = [st[@"depth"] intValue];
        NSString *val = [self valueOfElement:elem] ?: [self titleOfElement:elem] ?: [self descriptionOfElement:elem] ?: @"?";
        [self log:@"  depth=%d: %@", depth, val];
        stIdx++;
    }
    
    // 6. Groups with identifiers
    [self log:@"\n### GROUPS WITH IDENTIFIERS ###"];
    NSMutableArray *groups = [NSMutableArray array];
    [self findElements:app predicate:^BOOL(AXUIElementRef elem, NSString *role, int depth) {
        if (![role isEqualToString:@"AXGroup"]) return NO;
        NSString *ident = [WAAccessibilityExplorer identifierOfElement:elem];
        return ident != nil;
    } maxDepth:25 results:groups];
    
    int grpIdx = 0;
    for (NSDictionary *g in groups) {
        if (grpIdx >= 20) break;
        AXUIElementRef grp = (__bridge AXUIElementRef)g[@"element"];
        int depth = [g[@"depth"] intValue];
        NSString *ident = [self identifierOfElement:grp];
        NSArray *children = [self childrenOfElement:grp];
        
        [self log:@"depth=%d id:%@ children:%lu", depth, ident, (unsigned long)children.count];
        
        // Dump interesting groups
        NSString *identLower = [ident lowercaseString];
        if ([identLower containsString:@"chat"] || 
            [identLower containsString:@"message"] || 
            [identLower containsString:@"list"]) {
            [self dumpAttributes:grp label:[NSString stringWithFormat:@"Group %@", ident]];
        }
        grpIdx++;
    }
    
    // 7. Scroll areas
    [self log:@"\n### SCROLL AREAS ###"];
    NSMutableArray *scrollAreas = [NSMutableArray array];
    [self findElements:app predicate:^BOOL(AXUIElementRef elem, NSString *role, int depth) {
        return [role isEqualToString:@"AXScrollArea"];
    } maxDepth:15 results:scrollAreas];
    
    for (NSDictionary *s in scrollAreas) {
        AXUIElementRef sa = (__bridge AXUIElementRef)s[@"element"];
        int depth = [s[@"depth"] intValue];
        NSArray *children = [self childrenOfElement:sa];
        [self log:@"\ndepth=%d children:%lu", depth, (unsigned long)children.count];
        [self dumpAttributes:sa label:@"ScrollArea"];
    }
    
    // 8. Generic elements with descriptions
    [self log:@"\n### GENERIC ELEMENTS WITH DESCRIPTIONS ###"];
    NSMutableArray *generics = [NSMutableArray array];
    [self findElements:app predicate:^BOOL(AXUIElementRef elem, NSString *role, int depth) {
        if (![role isEqualToString:@"AXGenericElement"]) return NO;
        NSString *desc = [WAAccessibilityExplorer descriptionOfElement:elem];
        return desc.length > 0;
    } maxDepth:25 results:generics];
    
    [self log:@"Found %lu generic elements with descriptions", (unsigned long)generics.count];
    
    int genIdx = 0;
    for (NSDictionary *g in generics) {
        if (genIdx >= 30) break;
        AXUIElementRef elem = (__bridge AXUIElementRef)g[@"element"];
        int depth = [g[@"depth"] intValue];
        NSString *desc = [self descriptionOfElement:elem];
        NSString *shortDesc = desc.length > 120 ? [desc substringToIndex:120] : desc;
        [self log:@"  depth=%d: %@", depth, shortDesc];
        genIdx++;
    }
    
    // 9. Cells
    [self log:@"\n### CELLS ###"];
    NSMutableArray *cells = [NSMutableArray array];
    [self findElements:app predicate:^BOOL(AXUIElementRef elem, NSString *role, int depth) {
        return [role isEqualToString:@"AXCell"] || [role isEqualToString:@"AXRow"];
    } maxDepth:15 results:cells];
    
    [self log:@"Found %lu cells/rows", (unsigned long)cells.count];
    
    int cellIdx = 0;
    for (NSDictionary *c in cells) {
        if (cellIdx >= 10) break;
        AXUIElementRef cell = (__bridge AXUIElementRef)c[@"element"];
        int depth = [c[@"depth"] intValue];
        [self log:@"\ndepth=%d", depth];
        [self printElement:cell depth:0];
        [self dumpAttributes:cell label:@"Cell"];
        cellIdx++;
    }
    
    // 10. Deep dive on first window
    if (windows.count > 0) {
        AXUIElementRef firstWindow = (__bridge AXUIElementRef)windows[0][@"element"];
        [self log:@"\n### FIRST WINDOW DEEP TREE (depth=12) ###\n"];
        [self dumpTree:firstWindow maxDepth:22];
    }
    
    [self log:@"\n%@", [@"" stringByPaddingToLength:60 withString:@"=" startingAtIndex:0]];
    [self log:@"EXPLORATION COMPLETE"];
    [self log:@"%@", [@"" stringByPaddingToLength:60 withString:@"=" startingAtIndex:0]];
}

#pragma mark - Public Interface

+ (void)explore {
    // Check accessibility
    NSDictionary *options = @{(__bridge id)kAXTrustedCheckOptionPrompt: @YES};
    if (!AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options)) {
        NSLog(@"ERROR: Accessibility permissions required!");
        NSLog(@"Go to System Settings > Privacy & Security > Accessibility");
        return;
    }
    
    AXUIElementRef app = [self findWhatsApp];
    if (!app) {
        NSLog(@"ERROR: WhatsApp is not running!");
        return;
    }
    
    [self exploreApp:app];
    CFRelease(app);
}

+ (void)exploreToFile:(NSString *)path {
    [NSThread sleepForTimeInterval:5.0];
    
    [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
    outputHandle = [NSFileHandle fileHandleForWritingAtPath:path];
    
    [self explore];
    
    [outputHandle closeFile];
    outputHandle = nil;
    
    NSLog(@"Exploration written to: %@", path);
}

@end
