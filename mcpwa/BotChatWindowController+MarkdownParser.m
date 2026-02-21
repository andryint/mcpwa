//
//  BotChatWindowController+MarkdownParser.m
//  mcpwa
//
//  Markdown to NSAttributedString conversion
//

#import "BotChatWindowController+MarkdownParser.h"
#import "BotChatWindowController+ThemeHandling.h"

@implementation BotChatWindowController (MarkdownParser)

- (NSAttributedString *)attributedStringFromMarkdown:(NSString *)markdown textColor:(NSColor *)textColor {
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];

    CGFloat fontSize = self.currentFontSize;
    NSFont *regularFont = [NSFont systemFontOfSize:fontSize];
    NSFont *boldFont = [NSFont boldSystemFontOfSize:fontSize];
    NSFont *italicFont = [NSFont fontWithDescriptor:[[regularFont fontDescriptor] fontDescriptorWithSymbolicTraits:NSFontDescriptorTraitItalic] size:fontSize];
    if (!italicFont) italicFont = regularFont;
    NSFont *h3Font = [NSFont boldSystemFontOfSize:fontSize + 2];
    NSFont *h2Font = [NSFont boldSystemFontOfSize:fontSize + 4];
    NSFont *h1Font = [NSFont boldSystemFontOfSize:fontSize + 6];

    NSDictionary *defaultAttrs = @{
        NSFontAttributeName: regularFont,
        NSForegroundColorAttributeName: textColor
    };

    NSArray *lines = [markdown componentsSeparatedByString:@"\n"];

    for (NSUInteger lineIdx = 0; lineIdx < lines.count; lineIdx++) {
        NSString *line = lines[lineIdx];

        // Handle headers
        NSFont *lineFont = regularFont;
        if ([line hasPrefix:@"### "]) {
            line = [line substringFromIndex:4];
            lineFont = h3Font;
        } else if ([line hasPrefix:@"## "]) {
            line = [line substringFromIndex:3];
            lineFont = h2Font;
        } else if ([line hasPrefix:@"# "]) {
            line = [line substringFromIndex:2];
            lineFont = h1Font;
        }

        // Handle bullet points - detect and set up paragraph style
        BOOL isBulletPoint = NO;
        if ([line hasPrefix:@"* "] || [line hasPrefix:@"- "]) {
            // Use a medium bullet character (BULLET OPERATOR U+2219) with proper spacing
            line = [NSString stringWithFormat:@"\u2022  %@", [line substringFromIndex:2]];
            isBulletPoint = YES;
        }

        // Parse inline formatting character by character
        NSMutableAttributedString *lineAttr = [[NSMutableAttributedString alloc] init];
        NSUInteger i = 0;
        NSUInteger len = line.length;

        while (i < len) {
            unichar c = [line characterAtIndex:i];

            // Check for markdown link [text](url) or source reference [N] / [N, M, ...]
            if (c == '[') {
                NSUInteger textStart = i + 1;
                NSUInteger textEnd = textStart;
                // Find closing ]
                while (textEnd < len && [line characterAtIndex:textEnd] != ']') {
                    textEnd++;
                }
                // Check for ( immediately after ] → markdown link [text](url)
                if (textEnd < len && textEnd + 1 < len && [line characterAtIndex:textEnd + 1] == '(') {
                    NSUInteger urlStart = textEnd + 2;
                    NSUInteger urlEnd = urlStart;
                    // Find closing )
                    while (urlEnd < len && [line characterAtIndex:urlEnd] != ')') {
                        urlEnd++;
                    }
                    if (urlEnd < len && urlEnd > urlStart && textEnd > textStart) {
                        // Valid markdown link found
                        NSString *linkText = [line substringWithRange:NSMakeRange(textStart, textEnd - textStart)];
                        NSString *urlString = [line substringWithRange:NSMakeRange(urlStart, urlEnd - urlStart)];
                        NSURL *url = [NSURL URLWithString:urlString];
                        if (url) {
                            NSMutableDictionary *linkAttrs = [NSMutableDictionary dictionaryWithDictionary:@{
                                NSFontAttributeName: lineFont,
                                NSForegroundColorAttributeName: [NSColor linkColor],
                                NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
                                NSLinkAttributeName: url
                            }];
                            NSAttributedString *linkAttr = [[NSAttributedString alloc] initWithString:linkText attributes:linkAttrs];
                            [lineAttr appendAttributedString:linkAttr];
                            i = urlEnd + 1;
                            continue;
                        }
                    }
                }

                // Check for source reference [N] or [N, M, ...] (digits separated by ", ")
                if (textEnd < len && textEnd > textStart) {
                    NSString *bracketContent = [line substringWithRange:NSMakeRange(textStart, textEnd - textStart)];
                    // Parse comma-separated numbers: "1" or "2, 3" or "1, 2, 3"
                    NSArray *parts = [bracketContent componentsSeparatedByString:@", "];
                    BOOL allNumbers = (parts.count > 0);
                    NSMutableArray<NSNumber *> *sourceNumbers = [NSMutableArray array];
                    for (NSString *part in parts) {
                        NSString *trimmed = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                        if (trimmed.length == 0 || trimmed.length > 3) { allNumbers = NO; break; }
                        NSInteger num = [trimmed integerValue];
                        if (num <= 0 || ![trimmed isEqualToString:[NSString stringWithFormat:@"%ld", (long)num]]) {
                            allNumbers = NO; break;
                        }
                        [sourceNumbers addObject:@(num)];
                    }

                    if (allNumbers && sourceNumbers.count > 0) {
                        // Source reference link color (warm brown to match app accent)
                        NSColor *sourceColor = isDarkMode() ?
                            [NSColor colorWithRed:0.85 green:0.75 blue:0.65 alpha:1.0] :
                            [NSColor colorWithRed:0.45 green:0.38 blue:0.32 alpha:1.0];

                        // Check if this is a source list line: [N] at start of line followed by text
                        // e.g., "[1] Chatbots [2025-12-15 22:12]"
                        // In that case, make the entire line a single clickable link.
                        BOOL isSourceListLine = (i == 0 && sourceNumbers.count == 1
                            && textEnd + 1 < len && [line characterAtIndex:textEnd + 1] == ' ');

                        if (isSourceListLine) {
                            NSString *numStr = [sourceNumbers[0] stringValue];
                            NSURL *sourceURL = [NSURL URLWithString:[NSString stringWithFormat:@"wasource://%@", numStr]];
                            NSDictionary *linkAttrs = @{
                                NSFontAttributeName: lineFont,
                                NSForegroundColorAttributeName: sourceColor,
                                NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
                                NSLinkAttributeName: sourceURL,
                                NSCursorAttributeName: [NSCursor pointingHandCursor]
                            };
                            // Render entire line as one clickable link
                            [lineAttr appendAttributedString:[[NSAttributedString alloc] initWithString:line attributes:linkAttrs]];
                            i = len; // Skip rest of line
                            continue;
                        }

                        NSDictionary *plainAttrs = @{
                            NSFontAttributeName: lineFont,
                            NSForegroundColorAttributeName: sourceColor
                        };

                        // Opening bracket
                        [lineAttr appendAttributedString:[[NSAttributedString alloc] initWithString:@"[" attributes:plainAttrs]];

                        for (NSUInteger si = 0; si < sourceNumbers.count; si++) {
                            if (si > 0) {
                                // Comma separator
                                [lineAttr appendAttributedString:[[NSAttributedString alloc] initWithString:@", " attributes:plainAttrs]];
                            }
                            // Clickable number
                            NSString *numStr = [sourceNumbers[si] stringValue];
                            NSURL *sourceURL = [NSURL URLWithString:[NSString stringWithFormat:@"wasource://%@", numStr]];
                            NSDictionary *linkAttrs = @{
                                NSFontAttributeName: lineFont,
                                NSForegroundColorAttributeName: sourceColor,
                                NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
                                NSLinkAttributeName: sourceURL,
                                NSCursorAttributeName: [NSCursor pointingHandCursor]
                            };
                            [lineAttr appendAttributedString:[[NSAttributedString alloc] initWithString:numStr attributes:linkAttrs]];
                        }

                        // Closing bracket
                        [lineAttr appendAttributedString:[[NSAttributedString alloc] initWithString:@"]" attributes:plainAttrs]];

                        i = textEnd + 1; // Skip past the ]
                        continue;
                    }
                }
                // Not a valid markdown link or source reference, treat [ as regular character
            }

            // Check for bare URL (https:// or http://)
            if (c == 'h' && i + 7 < len) {
                NSString *remaining = [line substringFromIndex:i];
                if ([remaining hasPrefix:@"https://"] || [remaining hasPrefix:@"http://"]) {
                    // Find end of URL (space, newline, or end of string)
                    NSUInteger urlEnd = i;
                    while (urlEnd < len) {
                        unichar uc = [line characterAtIndex:urlEnd];
                        if (uc == ' ' || uc == '\t' || uc == '\n' || uc == ')' || uc == ']' || uc == '>' || uc == '"' || uc == '\'') {
                            break;
                        }
                        urlEnd++;
                    }
                    // Remove trailing punctuation that's likely not part of URL
                    while (urlEnd > i) {
                        unichar lastChar = [line characterAtIndex:urlEnd - 1];
                        if (lastChar == '.' || lastChar == ',' || lastChar == ';' || lastChar == ':' || lastChar == '!' || lastChar == '?') {
                            urlEnd--;
                        } else {
                            break;
                        }
                    }
                    if (urlEnd > i) {
                        NSString *urlString = [line substringWithRange:NSMakeRange(i, urlEnd - i)];
                        NSURL *url = [NSURL URLWithString:urlString];
                        if (url) {
                            NSMutableDictionary *linkAttrs = [NSMutableDictionary dictionaryWithDictionary:@{
                                NSFontAttributeName: lineFont,
                                NSForegroundColorAttributeName: [NSColor linkColor],
                                NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
                                NSLinkAttributeName: url
                            }];
                            NSAttributedString *linkAttr = [[NSAttributedString alloc] initWithString:urlString attributes:linkAttrs];
                            [lineAttr appendAttributedString:linkAttr];
                            i = urlEnd;
                            continue;
                        }
                    }
                }
            }

            // Check for bold (**) or italic (*)
            if (c == '*') {
                // Check for bold **
                if (i + 1 < len && [line characterAtIndex:i + 1] == '*') {
                    // Look for closing **
                    NSUInteger start = i + 2;
                    NSUInteger end = start;
                    BOOL foundClosing = NO;
                    while (end + 1 < len) {
                        if ([line characterAtIndex:end] == '*' && [line characterAtIndex:end + 1] == '*') {
                            foundClosing = YES;
                            break;
                        }
                        end++;
                    }
                    if (foundClosing && end > start) {
                        // Found closing **
                        NSString *boldText = [line substringWithRange:NSMakeRange(start, end - start)];
                        NSFont *font = (lineFont == regularFont) ? boldFont : [NSFont boldSystemFontOfSize:lineFont.pointSize];
                        NSAttributedString *boldAttr = [[NSAttributedString alloc] initWithString:boldText attributes:@{
                            NSFontAttributeName: font,
                            NSForegroundColorAttributeName: textColor
                        }];
                        [lineAttr appendAttributedString:boldAttr];
                        i = end + 2;
                        continue;
                    }
                    // No closing ** found - treat as literal text and advance past both *
                    NSAttributedString *literalAttr = [[NSAttributedString alloc] initWithString:@"**" attributes:@{
                        NSFontAttributeName: lineFont,
                        NSForegroundColorAttributeName: textColor
                    }];
                    [lineAttr appendAttributedString:literalAttr];
                    i += 2;
                    continue;
                }

                // Check for single italic *
                NSUInteger start = i + 1;
                NSUInteger end = start;
                while (end < len && [line characterAtIndex:end] != '*') {
                    end++;
                }
                if (end < len && end > start) {
                    // Found closing *
                    NSString *italicText = [line substringWithRange:NSMakeRange(start, end - start)];
                    NSAttributedString *italicAttr = [[NSAttributedString alloc] initWithString:italicText attributes:@{
                        NSFontAttributeName: italicFont,
                        NSForegroundColorAttributeName: textColor
                    }];
                    [lineAttr appendAttributedString:italicAttr];
                    i = end + 1;
                    continue;
                }

                // No closing * found - treat as literal *
                NSAttributedString *literalAttr = [[NSAttributedString alloc] initWithString:@"*" attributes:@{
                    NSFontAttributeName: lineFont,
                    NSForegroundColorAttributeName: textColor
                }];
                [lineAttr appendAttributedString:literalAttr];
                i++;
                continue;
            }

            // Regular character - collect consecutive regular chars for efficiency
            // Stop at formatting characters: *, [, and h (for potential URLs)
            NSUInteger start = i;
            while (i < len) {
                unichar rc = [line characterAtIndex:i];
                if (rc == '*' || rc == '[') break;
                // Check for potential URL start
                if (rc == 'h' && i + 7 < len) {
                    NSString *potentialUrl = [line substringFromIndex:i];
                    if ([potentialUrl hasPrefix:@"https://"] || [potentialUrl hasPrefix:@"http://"]) {
                        break;
                    }
                }
                i++;
            }
            if (i > start) {
                NSString *regularText = [line substringWithRange:NSMakeRange(start, i - start)];
                NSAttributedString *regularAttr = [[NSAttributedString alloc] initWithString:regularText attributes:@{
                    NSFontAttributeName: lineFont,
                    NSForegroundColorAttributeName: textColor
                }];
                [lineAttr appendAttributedString:regularAttr];
            } else {
                // No progress made - this means we hit a special char that wasn't handled
                // (e.g., [ that doesn't form a valid link). Output it as literal and advance.
                NSString *literal = [NSString stringWithCharacters:&c length:1];
                NSAttributedString *literalAttr = [[NSAttributedString alloc] initWithString:literal attributes:@{
                    NSFontAttributeName: lineFont,
                    NSForegroundColorAttributeName: textColor
                }];
                [lineAttr appendAttributedString:literalAttr];
                i++;
            }
        }

        // Apply paragraph style for bullet points (hanging indent)
        if (isBulletPoint && lineAttr.length > 0) {
            NSMutableParagraphStyle *bulletStyle = [[NSMutableParagraphStyle alloc] init];
            bulletStyle.headIndent = 24;         // Indent for wrapped lines (aligned with text after bullet)
            bulletStyle.firstLineHeadIndent = 0; // Bullet starts at left margin
            bulletStyle.paragraphSpacingBefore = 8;  // Space before each bullet item
            bulletStyle.paragraphSpacing = 4;    // Space after each bullet item
            [lineAttr addAttribute:NSParagraphStyleAttributeName value:bulletStyle range:NSMakeRange(0, lineAttr.length)];
        }

        [result appendAttributedString:lineAttr];

        // Add newline between lines (except last)
        if (lineIdx < lines.count - 1) {
            [result appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:defaultAttrs]];
        }
    }

    return result;
}

@end
