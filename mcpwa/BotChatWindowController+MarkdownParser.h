//
//  BotChatWindowController+MarkdownParser.h
//  mcpwa
//
//  Markdown to NSAttributedString conversion
//

#import "BotChatWindowController.h"

NS_ASSUME_NONNULL_BEGIN

@interface BotChatWindowController (MarkdownParser)

/// Create attributed string from markdown text
- (NSAttributedString *)attributedStringFromMarkdown:(NSString *)markdown textColor:(NSColor *)textColor;

@end

NS_ASSUME_NONNULL_END
