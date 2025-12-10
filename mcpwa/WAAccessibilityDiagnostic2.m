//
//  WAAccessibilityDiagnostic2.m
//  mcpwa
//

#import "WAAccessibilityDiagnostic2.h"
#import <ApplicationServices/ApplicationServices.h>

@implementation WAAccessibilityDiagnostic2

+ (void)runDiagnostics {
    NSLog(@"");
    NSLog(@"====== DEEP AX DIAGNOSTICS ======");
    NSLog(@"");
    
    // 1. Test AX with Finder (should always work)
    NSLog(@"[1] TESTING AX WITH FINDER (control test)");
    NSArray *apps = [[NSWorkspace sharedWorkspace] runningApplications];
    NSRunningApplication *finder = nil;
    for (NSRunningApplication *app in apps) {
        if ([app.bundleIdentifier isEqualToString:@"com.apple.finder"]) {
            finder = app;
            break;
        }
    }
    
    if (finder) {
        AXUIElementRef finderElement = AXUIElementCreateApplication(finder.processIdentifier);
        CFTypeRef roleValue = NULL;
        AXError err = AXUIElementCopyAttributeValue(finderElement, kAXRoleAttribute, &roleValue);
        
        if (err == kAXErrorSuccess) {
            NSLog(@"    Finder AXRole: %@ ✓", (__bridge NSString *)roleValue);
            NSLog(@"    → AX system is working correctly");
            CFRelease(roleValue);
        } else {
            NSLog(@"    Finder query FAILED with error %d", (int)err);
            NSLog(@"    → Something is wrong with AX system itself!");
        }
        CFRelease(finderElement);
    }
    
    // 2. Test with System-wide element
    NSLog(@"");
    NSLog(@"[2] TESTING SYSTEM-WIDE ELEMENT");
    AXUIElementRef systemWide = AXUIElementCreateSystemWide();
    
    CFTypeRef focusedApp = NULL;
    AXError err = AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute, &focusedApp);
    
    if (err == kAXErrorSuccess && focusedApp) {
        CFTypeRef appRole = NULL;
        AXUIElementCopyAttributeValue((AXUIElementRef)focusedApp, kAXRoleAttribute, &appRole);
        
        CFTypeRef appTitle = NULL;
        AXUIElementCopyAttributeValue((AXUIElementRef)focusedApp, kAXTitleAttribute, &appTitle);
        
        NSLog(@"    Focused app: %@ (role: %@)", 
              appTitle ? (__bridge NSString *)appTitle : @"<none>",
              appRole ? (__bridge NSString *)appRole : @"<none>");
        
        if (appTitle) CFRelease(appTitle);
        if (appRole) CFRelease(appRole);
        CFRelease(focusedApp);
    } else {
        NSLog(@"    Failed to get focused app: %d", (int)err);
    }
    
    // Get focused element
    CFTypeRef focusedElement = NULL;
    err = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute, &focusedElement);
    if (err == kAXErrorSuccess && focusedElement) {
        CFTypeRef elemRole = NULL;
        AXUIElementCopyAttributeValue((AXUIElementRef)focusedElement, kAXRoleAttribute, &elemRole);
        NSLog(@"    Focused element role: %@", elemRole ? (__bridge NSString *)elemRole : @"<none>");
        if (elemRole) CFRelease(elemRole);
        CFRelease(focusedElement);
    }
    
    CFRelease(systemWide);
    
    // 3. Find WhatsApp and try different approaches
    NSLog(@"");
    NSLog(@"[3] FINDING WHATSAPP");
    
    NSRunningApplication *whatsapp = nil;
    for (NSRunningApplication *app in apps) {
        if ([app.bundleIdentifier isEqualToString:@"net.whatsapp.WhatsApp"]) {
            whatsapp = app;
            break;
        }
    }
    
    if (!whatsapp) {
        NSLog(@"    WhatsApp not found!");
        return;
    }
    
    NSLog(@"    Found: PID=%d", whatsapp.processIdentifier);
    
    // 4. Activate WhatsApp and wait
    NSLog(@"");
    NSLog(@"[4] ACTIVATING WHATSAPP");
    [whatsapp activateWithOptions:NSApplicationActivateIgnoringOtherApps];
    
    // Wait for activation
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
    
    NSLog(@"    WhatsApp isActive: %@", whatsapp.isActive ? @"YES" : @"NO");
    
    // 5. Now try via system-wide focused app
    NSLog(@"");
    NSLog(@"[5] GETTING WHATSAPP VIA SYSTEM-WIDE FOCUSED APP");
    
    systemWide = AXUIElementCreateSystemWide();
    focusedApp = NULL;
    err = AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute, &focusedApp);
    
    if (err == kAXErrorSuccess && focusedApp) {
        CFTypeRef appTitle = NULL;
        AXUIElementCopyAttributeValue((AXUIElementRef)focusedApp, kAXTitleAttribute, &appTitle);
        NSLog(@"    Focused app title: %@", appTitle ? (__bridge NSString *)appTitle : @"<none>");
        if (appTitle) CFRelease(appTitle);
        
        // Try to get children from this reference
        CFTypeRef children = NULL;
        err = AXUIElementCopyAttributeValue((AXUIElementRef)focusedApp, kAXChildrenAttribute, &children);
        NSLog(@"    AXChildren via focused app: error=%d", (int)err);
        
        if (err == kAXErrorSuccess && children) {
            NSArray *childArray = (__bridge_transfer NSArray *)children;
            NSLog(@"    → Got %lu children!", (unsigned long)childArray.count);
            
            // Dump first few
            for (int i = 0; i < MIN(5, childArray.count); i++) {
                AXUIElementRef child = (__bridge AXUIElementRef)childArray[i];
                CFTypeRef childRole = NULL;
                AXUIElementCopyAttributeValue(child, kAXRoleAttribute, &childRole);
                NSLog(@"      Child %d: %@", i, childRole ? (__bridge NSString *)childRole : @"?");
                if (childRole) CFRelease(childRole);
            }
        }
        
        // Try windows
        CFTypeRef windows = NULL;
        err = AXUIElementCopyAttributeValue((AXUIElementRef)focusedApp, kAXWindowsAttribute, &windows);
        NSLog(@"    AXWindows via focused app: error=%d", (int)err);
        
        if (err == kAXErrorSuccess && windows) {
            NSArray *windowArray = (__bridge_transfer NSArray *)windows;
            NSLog(@"    → Got %lu windows!", (unsigned long)windowArray.count);
        }
        
        CFRelease(focusedApp);
    } else {
        NSLog(@"    Failed to get focused app: %d", (int)err);
    }
    
    CFRelease(systemWide);
    
    // 6. Try direct PID approach again after activation
    NSLog(@"");
    NSLog(@"[6] DIRECT PID APPROACH (after activation)");
    
    AXUIElementRef appElement = AXUIElementCreateApplication(whatsapp.processIdentifier);
    
    CFTypeRef role = NULL;
    err = AXUIElementCopyAttributeValue(appElement, kAXRoleAttribute, &role);
    NSLog(@"    AXRole: error=%d", (int)err);
    if (err == kAXErrorSuccess && role) {
        NSLog(@"    → Role: %@", (__bridge NSString *)role);
        CFRelease(role);
    }
    
    CFRelease(appElement);
    
    // 7. Check process info via different method
    NSLog(@"");
    NSLog(@"[7] PROCESS INFO VIA NSRUNNINGAPPLICATION");
    NSLog(@"    executableArchitecture: %ld", (long)whatsapp.executableArchitecture);
    NSLog(@"    launchDate: %@", whatsapp.launchDate);
    NSLog(@"    ownsMenuBar: %@", whatsapp.ownsMenuBar ? @"YES" : @"NO");
    NSLog(@"    activationPolicy: %ld", (long)whatsapp.activationPolicy);
    // 0 = regular, 1 = accessory, 2 = prohibited
    
    // 8. Try using element at mouse position (if cursor is over WhatsApp)
    NSLog(@"");
    NSLog(@"[8] ELEMENT AT MOUSE POSITION");
    NSLog(@"    → Move mouse over WhatsApp window and run again to test");
    
    NSPoint mouseLoc = [NSEvent mouseLocation];
    NSLog(@"    Mouse at: (%.0f, %.0f)", mouseLoc.x, mouseLoc.y);
    
    // Convert to global coordinates
    CGPoint cgPoint = CGPointMake(mouseLoc.x, [[NSScreen mainScreen] frame].size.height - mouseLoc.y);
    
    AXUIElementRef elementAtPoint = NULL;
    systemWide = AXUIElementCreateSystemWide();
    err = AXUIElementCopyElementAtPosition(systemWide, cgPoint.x, cgPoint.y, &elementAtPoint);
    
    NSLog(@"    AXUIElementCopyElementAtPosition: error=%d", (int)err);
    
    if (err == kAXErrorSuccess && elementAtPoint) {
        CFTypeRef elemRole = NULL;
        AXUIElementCopyAttributeValue(elementAtPoint, kAXRoleAttribute, &elemRole);
        
        CFTypeRef elemDesc = NULL;
        AXUIElementCopyAttributeValue(elementAtPoint, kAXDescriptionAttribute, &elemDesc);
        
        NSLog(@"    → Element role: %@", elemRole ? (__bridge NSString *)elemRole : @"?");
        NSLog(@"    → Element desc: %@", elemDesc ? (__bridge NSString *)elemDesc : @"<none>");
        
        // Get PID of this element
        pid_t elementPid = 0;
        AXUIElementGetPid(elementAtPoint, &elementPid);
        NSLog(@"    → Element PID: %d (WhatsApp PID: %d)", elementPid, whatsapp.processIdentifier);
        
        if (elemRole) CFRelease(elemRole);
        if (elemDesc) CFRelease(elemDesc);
        CFRelease(elementAtPoint);
    }
    
    CFRelease(systemWide);
    
    // 9. Check if maybe it's a helper process issue
    NSLog(@"");
    NSLog(@"[9] ALL WHATSAPP-RELATED PROCESSES");
    for (NSRunningApplication *app in apps) {
        NSString *name = app.localizedName ?: @"";
        NSString *bundle = app.bundleIdentifier ?: @"";
        
        if ([name.lowercaseString containsString:@"whatsapp"] ||
            [bundle.lowercaseString containsString:@"whatsapp"]) {
            
            NSLog(@"    PID %d: %@ (%@)", 
                  app.processIdentifier, 
                  name,
                  bundle);
            
            // Try AX on each
            AXUIElementRef elem = AXUIElementCreateApplication(app.processIdentifier);
            CFTypeRef r = NULL;
            AXError e = AXUIElementCopyAttributeValue(elem, kAXRoleAttribute, &r);
            NSLog(@"      → AXRole query: %d %@", (int)e, r ? (__bridge NSString *)r : @"");
            if (r) CFRelease(r);
            CFRelease(elem);
        }
    }
    
    NSLog(@"");
    NSLog(@"====== DIAGNOSTICS COMPLETE ======");
    NSLog(@"");
}

@end
