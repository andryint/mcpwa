// WASearchResult.m
// Implementation with parsing logic for WhatsApp search results

#import "WASearchResult.h"

@implementation WASearchResult

- (instancetype)init {
    self = [super init];
    if (self) {
        _type = WASearchResultTypeMessage;
        _index = -1;
        _isOutgoing = NO;
        _attachmentType = WASearchResultAttachmentNone;
        _elementRef = NULL;
    }
    return self;
}

/**
 * Parse the AXDescription field from ChatListSearchView_MessageResult
 *
 * Observed patterns:
 *   "ChatName, ‎messageSnippet..."
 *   "ChatName, ⁨‎You⁩‎: ‎messageSnippet..."
 *   "ChatName, ‎messageSnippet..., DD/MM/YYYY"
 *   "ChatName, ⁨‎You⁩‎: ‎…partial snippet with ellipsis"
 *
 * Unicode considerations:
 *   - ⁨ (U+2068) LEFT-TO-RIGHT ISOLATE
 *   - ⁩ (U+2069) POP DIRECTIONAL ISOLATE  
 *   - ‎ (U+200E) LEFT-TO-RIGHT MARK
 *   - ‏ (U+200F) RIGHT-TO-LEFT MARK
 */
+ (nullable WASearchResult *)parseFromDescription:(NSString *)desc 
                                        withIndex:(NSInteger)index {
    if (!desc || desc.length == 0) {
        return nil;
    }
    
    WASearchResult *result = [[WASearchResult alloc] init];
    result.index = index;
    result.type = WASearchResultTypeMessage;
    
    // Clean up directional control characters for easier parsing
    NSMutableString *cleaned = [desc mutableCopy];
    
    // Remove common Unicode directional markers
    NSArray *controlChars = @[
        @"\u2068",  // LEFT-TO-RIGHT ISOLATE
        @"\u2069",  // POP DIRECTIONAL ISOLATE
        @"\u200E",  // LEFT-TO-RIGHT MARK
        @"\u200F",  // RIGHT-TO-LEFT MARK
        @"\u202A",  // LEFT-TO-RIGHT EMBEDDING
        @"\u202C",  // POP DIRECTIONAL FORMATTING
    ];
    
    for (NSString *ctrl in controlChars) {
        [cleaned replaceOccurrencesOfString:ctrl 
                                 withString:@"" 
                                    options:0 
                                      range:NSMakeRange(0, cleaned.length)];
    }
    
    NSString *workingStr = [cleaned copy];
    
    // Step 1: Extract chat name (everything before first ", ")
    NSRange firstComma = [workingStr rangeOfString:@", "];
    if (firstComma.location == NSNotFound) {
        // Malformed, use whole string as chat name
        result.chatName = workingStr;
        return result;
    }
    
    result.chatName = [workingStr substringToIndex:firstComma.location];
    NSString *remainder = [workingStr substringFromIndex:firstComma.location + 2];
    
    // Step 2: Check for "You:" prefix (outgoing message indicator)
    if ([remainder hasPrefix:@"You:"] || [remainder hasPrefix:@"You: "]) {
        result.isOutgoing = YES;
        // Skip "You:" or "You: "
        NSRange youRange = [remainder rangeOfString:@"You:"];
        remainder = [remainder substringFromIndex:youRange.location + youRange.length];
        // Trim leading whitespace/marks
        remainder = [remainder stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceCharacterSet]];
    }
    
    // Step 3: Try to extract date from end (pattern: ", DD/MM/YYYY" or ", D/MM/YYYY")
    NSRegularExpression *dateRegex = [NSRegularExpression 
        regularExpressionWithPattern:@", (\\d{1,2}/\\d{1,2}/\\d{4})$"
                             options:0 
                               error:nil];
    
    NSTextCheckingResult *dateMatch = [dateRegex 
        firstMatchInString:remainder 
                   options:0 
                     range:NSMakeRange(0, remainder.length)];
    
    if (dateMatch && dateMatch.numberOfRanges >= 2) {
        result.date = [remainder substringWithRange:[dateMatch rangeAtIndex:1]];
        // Remove date from remainder to get snippet
        remainder = [remainder substringToIndex:dateMatch.range.location];
    }
    
    // Step 4: What remains is the snippet
    // Clean up leading ellipsis if present
    if ([remainder hasPrefix:@"…"] || [remainder hasPrefix:@"..."]) {
        remainder = [remainder substringFromIndex:1];
        remainder = [remainder stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceCharacterSet]];
    }
    
    result.snippet = remainder;
    
    return result;
}

/**
 * Parse attachment info from child button element
 * 
 * Patterns observed:
 *   id:SearchResultsMessageRow_VisualMedia desc:"‎image"
 *   id:SearchResultsMessageRow_NonvisualMedia desc:"docs.google.com https://..."
 *   id:SearchResultsMessageRow_NonvisualMedia desc:"Title …description"
 */
- (void)parseAttachmentFromDescription:(NSString *)attachDesc 
                          withIdentifier:(NSString *)identifier {
    if (!identifier) return;
    
    if ([identifier containsString:@"VisualMedia"]) {
        self.attachmentType = WASearchResultAttachmentImage;
        self.attachmentDescription = @"image";
    } else if ([identifier containsString:@"NonvisualMedia"]) {
        // Could be link or document
        if ([attachDesc containsString:@"http"] || 
            [attachDesc containsString:@".com"] ||
            [attachDesc containsString:@".org"]) {
            self.attachmentType = WASearchResultAttachmentLink;
        } else {
            self.attachmentType = WASearchResultAttachmentDocument;
        }
        self.attachmentDescription = attachDesc;
    }
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    
    dict[@"index"] = @(self.index);
    dict[@"type"] = [self typeString];
    
    if (self.chatName) dict[@"chat_name"] = self.chatName;
    if (self.snippet) dict[@"snippet"] = self.snippet;
    if (self.date) dict[@"date"] = self.date;
    dict[@"is_outgoing"] = @(self.isOutgoing);
    
    if (self.attachmentType != WASearchResultAttachmentNone) {
        dict[@"attachment"] = @{
            @"type": [self attachmentTypeString],
            @"description": self.attachmentDescription ?: @""
        };
    }
    
    return [dict copy];
}

- (NSString *)typeString {
    switch (self.type) {
        case WASearchResultTypeMessage: return @"message";
        case WASearchResultTypeChat: return @"chat";
        case WASearchResultTypePhoto: return @"photo";
        case WASearchResultTypeLink: return @"link";
    }
}

- (NSString *)attachmentTypeString {
    switch (self.attachmentType) {
        case WASearchResultAttachmentNone: return @"none";
        case WASearchResultAttachmentImage: return @"image";
        case WASearchResultAttachmentLink: return @"link";
        case WASearchResultAttachmentDocument: return @"document";
    }
}

@end
