// WASearchResult.h
// Data model for WhatsApp global search results

#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, WASearchResultType) {
    WASearchResultTypeMessage,
    WASearchResultTypeChat,
    WASearchResultTypePhoto,
    WASearchResultTypeLink
};

typedef NS_ENUM(NSInteger, WASearchResultAttachment) {
    WASearchResultAttachmentNone,
    WASearchResultAttachmentImage,
    WASearchResultAttachmentLink,
    WASearchResultAttachmentDocument
};

@interface WASearchResult : NSObject

@property (nonatomic, assign) WASearchResultType type;
@property (nonatomic, assign) NSInteger index;  // Position in search results list (for clicking)

// Parsed from AXDescription
@property (nonatomic, copy, nullable) NSString *chatName;
@property (nonatomic, copy, nullable) NSString *snippet;
@property (nonatomic, copy, nullable) NSString *date;
@property (nonatomic, assign) BOOL isOutgoing;  // "You:" prefix present

// Attachment info (from child button if present)
@property (nonatomic, assign) WASearchResultAttachment attachmentType;
@property (nonatomic, copy, nullable) NSString *attachmentDescription;  // Link URL or image label

// The raw AXUIElementRef for clicking (not retained across calls)
@property (nonatomic, assign) AXUIElementRef elementRef;

#pragma mark - Parsing

/**
 * Parse a search result from its AXDescription string
 * @param desc The AXDescription from ChatListSearchView_MessageResult element
 * @param index The 0-based position in the search results list
 * @return Parsed result, or nil if parsing failed
 */
+ (nullable WASearchResult *)parseFromDescription:(NSString *)desc 
                                        withIndex:(NSInteger)index;

/**
 * Parse attachment info from a child button element
 * @param attachDesc The AXDescription of the attachment button
 * @param identifier The AXIdentifier (VisualMedia or NonvisualMedia)
 */
- (void)parseAttachmentFromDescription:(nullable NSString *)attachDesc 
                        withIdentifier:(nullable NSString *)identifier;

#pragma mark - Serialization

- (NSDictionary *)toDictionary;

@end

NS_ASSUME_NONNULL_END
