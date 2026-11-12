#import "ChatBubbleCell.h"

static const CGFloat kHorizontalMargin = 12.0;
static const CGFloat kVerticalMargin = 4.0;
static const CGFloat kInnerHorizontalPad = 14.0;
static const CGFloat kInnerVerticalPad = 10.0;
static const CGFloat kCornerRadius = 18.0;
static const CGFloat kMaxBubbleWidthRatio = 0.92; // Geniş ve ekranı dolduran modern iMessage balonu

@implementation ChatBubbleCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];

        _bubbleBackgroundView = [[UIView alloc] initWithFrame:CGRectZero];
        _bubbleBackgroundView.layer.cornerRadius = kCornerRadius;
        _bubbleBackgroundView.layer.masksToBounds = YES;
        [self.contentView addSubview:_bubbleBackgroundView];

        _messageTextView = [[UITextView alloc] initWithFrame:CGRectZero];
        _messageTextView.editable = NO;
        _messageTextView.selectable = YES;
        _messageTextView.scrollEnabled = NO;
        _messageTextView.backgroundColor = [UIColor clearColor];
        _messageTextView.textContainerInset = UIEdgeInsetsZero;
        _messageTextView.textContainer.lineFragmentPadding = 0;
        _messageTextView.dataDetectorTypes = UIDataDetectorTypeLink | UIDataDetectorTypePhoneNumber;
        [_bubbleBackgroundView addSubview:_messageTextView];
    }
    return self;
}

#pragma mark - Markdown & GFM Table Parser

+ (BOOL)isTableSeparatorRow:(NSString *)trimmed {
    if (![trimmed containsString:@"-"]) return NO;
    NSString *cleaned = [trimmed stringByReplacingOccurrencesOfString:@"|" withString:@""];
    cleaned = [cleaned stringByReplacingOccurrencesOfString:@":" withString:@""];
    cleaned = [cleaned stringByReplacingOccurrencesOfString:@"-" withString:@""];
    cleaned = [cleaned stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    return (cleaned.length == 0);
}

+ (NSArray *)splitTableRow:(NSString *)row {
    NSString *trimmed = [row stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([trimmed hasPrefix:@"|"]) trimmed = [trimmed substringFromIndex:1];
    if ([trimmed hasSuffix:@"|"]) trimmed = [trimmed substringToIndex:trimmed.length - 1];

    NSArray *rawParts = [trimmed componentsSeparatedByString:@"|"];
    NSMutableArray *cleaned = [NSMutableArray array];
    for (NSString *p in rawParts) {
        [cleaned addObject:[p stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
    }
    return cleaned;
}

+ (NSAttributedString *)formatTableRows:(NSArray *)tableRows isUser:(BOOL)isUser {
    if (tableRows.count == 0) return [[NSAttributedString alloc] initWithString:@""];

    UIFont *headerFont = [UIFont fontWithName:@"HelveticaNeue-Bold" size:14.5];
    UIFont *cellFont = [UIFont fontWithName:@"HelveticaNeue" size:14.0];
    UIColor *textColor = isUser ? [UIColor whiteColor] : [UIColor colorWithRed:0.12 green:0.12 blue:0.13 alpha:1.0];
    UIColor *boxColor = isUser ? [UIColor colorWithWhite:1.0 alpha:0.45] : [UIColor colorWithRed:16.0/255.0 green:163.0/255.0 blue:127.0/255.0 alpha:0.65];

    // Sütun sayısını ve genişliklerini hesapla
    NSInteger maxCols = 0;
    NSMutableArray *parsedRows = [NSMutableArray array];
    for (NSString *rowStr in tableRows) {
        NSArray *cells = [self splitTableRow:rowStr];
        if (cells.count > maxCols) maxCols = cells.count;
        [parsedRows addObject:cells];
    }

    if (maxCols == 0) return [[NSAttributedString alloc] initWithString:@""];

    NSMutableArray *colWidths = [NSMutableArray array];
    for (NSInteger c = 0; c < maxCols; c++) {
        NSInteger maxLen = 4; // minimum sütun genişliği
        for (NSArray *row in parsedRows) {
            if (c < row.count) {
                NSString *val = row[c];
                if (val.length > maxLen) maxLen = val.length;
            }
        }
        if (maxLen > 24) maxLen = 24; // çok uzun metinlerin tabloyu taşırmaması için sınır
        [colWidths addObject:@(maxLen)];
    }

    NSMutableAttributedString *tableAttr = [[NSMutableAttributedString alloc] init];
    NSMutableParagraphStyle *tablePara = [[NSMutableParagraphStyle alloc] init];
    tablePara.lineSpacing = 2.0;

    // Üst Çizgi: ┌────────┬────────┐
    NSMutableString *topBorder = [NSMutableString stringWithString:@"┌"];
    for (NSInteger c = 0; c < maxCols; c++) {
        NSInteger w = [colWidths[c] integerValue];
        for (NSInteger k = 0; k < w + 2; k++) [topBorder appendString:@"─"];
        [topBorder appendString:(c == maxCols - 1) ? @"┐\n" : @"┬"];
    }
    [tableAttr appendAttributedString:[[NSAttributedString alloc] initWithString:topBorder attributes:@{
        NSFontAttributeName: [UIFont fontWithName:@"Courier" size:12.5] ?: [UIFont systemFontOfSize:12.5],
        NSForegroundColorAttributeName: boxColor,
        NSParagraphStyleAttributeName: tablePara
    }]];

    for (NSInteger r = 0; r < parsedRows.count; r++) {
        NSArray *row = parsedRows[r];
        BOOL isHeader = (r == 0);

        NSMutableString *rowText = [NSMutableString stringWithString:@"│"];
        for (NSInteger c = 0; c < maxCols; c++) {
            NSString *cellVal = (c < row.count) ? row[c] : @"";
            NSInteger w = [colWidths[c] integerValue];
            if (cellVal.length > w) {
                cellVal = [[cellVal substringToIndex:w - 1] stringByAppendingString:@"…"];
            }
            NSInteger pad = w - cellVal.length;
            [rowText appendFormat:@" %@%*s │", cellVal, (int)pad, ""];
        }
        [rowText appendString:@"\n"];

        NSDictionary *rowAttrs = @{
            NSFontAttributeName: isHeader ? headerFont : cellFont,
            NSForegroundColorAttributeName: textColor,
            NSParagraphStyleAttributeName: tablePara
        };
        [tableAttr appendAttributedString:[[NSAttributedString alloc] initWithString:rowText attributes:rowAttrs]];

        // Başlık altı ayracı: ├────────┼────────┤
        if (isHeader) {
            NSMutableString *midBorder = [NSMutableString stringWithString:@"├"];
            for (NSInteger c = 0; c < maxCols; c++) {
                NSInteger w = [colWidths[c] integerValue];
                for (NSInteger k = 0; k < w + 2; k++) [midBorder appendString:@"─"];
                [midBorder appendString:(c == maxCols - 1) ? @"┤\n" : @"┼"];
            }
            [tableAttr appendAttributedString:[[NSAttributedString alloc] initWithString:midBorder attributes:@{
                NSFontAttributeName: [UIFont fontWithName:@"Courier" size:12.5] ?: [UIFont systemFontOfSize:12.5],
                NSForegroundColorAttributeName: boxColor,
                NSParagraphStyleAttributeName: tablePara
            }]];
        }
    }

    // Alt Çizgi: └────────┴────────┘
    NSMutableString *botBorder = [NSMutableString stringWithString:@"└"];
    for (NSInteger c = 0; c < maxCols; c++) {
        NSInteger w = [colWidths[c] integerValue];
        for (NSInteger k = 0; k < w + 2; k++) [botBorder appendString:@"─"];
        [botBorder appendString:(c == maxCols - 1) ? @"┘\n" : @"┴"];
    }
    [tableAttr appendAttributedString:[[NSAttributedString alloc] initWithString:botBorder attributes:@{
        NSFontAttributeName: [UIFont fontWithName:@"Courier" size:12.5] ?: [UIFont systemFontOfSize:12.5],
        NSForegroundColorAttributeName: boxColor,
        NSParagraphStyleAttributeName: tablePara
    }]];

    return tableAttr;
}

+ (NSAttributedString *)parseMarkdown:(NSString *)rawText isUser:(BOOL)isUser {
    if (!rawText || rawText.length == 0) {
        return [[NSAttributedString alloc] initWithString:@""];
    }

    UIColor *baseTextColor = isUser ? [UIColor whiteColor] : [UIColor colorWithRed:0.13 green:0.13 blue:0.14 alpha:1.0];
    UIColor *h1Color = isUser ? [UIColor whiteColor] : [UIColor colorWithRed:0.08 green:0.08 blue:0.09 alpha:1.0];
    UIColor *h2Color = isUser ? [UIColor whiteColor] : [UIColor colorWithRed:16.0/255.0 green:163.0/255.0 blue:127.0/255.0 alpha:1.0]; // OpenAI Teal
    UIColor *h3Color = isUser ? [UIColor whiteColor] : [UIColor colorWithRed:0.25 green:0.25 blue:0.26 alpha:1.0];

    UIFont *bodyFont = [UIFont fontWithName:@"HelveticaNeue" size:16.0];
    UIFont *boldBodyFont = [UIFont fontWithName:@"HelveticaNeue-Bold" size:16.0];
    UIFont *h1Font = [UIFont fontWithName:@"HelveticaNeue-Bold" size:21.0];
    UIFont *h2Font = [UIFont fontWithName:@"HelveticaNeue-Bold" size:18.5];
    UIFont *h3Font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:16.5];

    NSMutableAttributedString *finalAttrString = [[NSMutableAttributedString alloc] init];
    NSArray *lines = [rawText componentsSeparatedByString:@"\n"];

    for (NSInteger i = 0; i < lines.count; i++) {
        NSString *line = lines[i];
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

        // GFM Tablo Algılama: Satırda | varsa ve sonraki satır |---| içeriyorsa
        if ([trimmed containsString:@"|"]) {
            // Sonraki satır tablo ayıracı mı? (Header ayracı)
            if (i + 1 < lines.count && [self isTableSeparatorRow:lines[i + 1]]) {
                NSMutableArray *tableRows = [NSMutableArray array];
                [tableRows addObject:line]; // Header
                i++; // separator satırını atla

                // Kalan tablo satırlarını topla
                while (i + 1 < lines.count) {
                    NSString *nextRow = lines[i + 1];
                    NSString *nextTrimmed = [nextRow stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    if ([nextTrimmed containsString:@"|"] && ![self isTableSeparatorRow:nextTrimmed]) {
                        [tableRows addObject:nextRow];
                        i++;
                    } else {
                        break;
                    }
                }

                NSAttributedString *renderedTable = [self formatTableRows:tableRows isUser:isUser];
                [finalAttrString appendAttributedString:renderedTable];
                continue;
            }
        }

        UIFont *lineBaseFont = bodyFont;
        UIFont *lineBoldFont = boldBodyFont;
        UIColor *lineColor = baseTextColor;
        NSString *lineContent = line;

        // 1. Headers Check (# H1, ## H2, ### H3, #### H4)
        if ([trimmed hasPrefix:@"### "]) {
            lineBaseFont = h3Font;
            lineBoldFont = h3Font;
            lineColor = h3Color;
            lineContent = [trimmed substringFromIndex:4];
        } else if ([trimmed hasPrefix:@"## "]) {
            lineBaseFont = h2Font;
            lineBoldFont = h2Font;
            lineColor = h2Color;
            lineContent = [trimmed substringFromIndex:3];
        } else if ([trimmed hasPrefix:@"# "]) {
            lineBaseFont = h1Font;
            lineBoldFont = h1Font;
            lineColor = h1Color;
            lineContent = [trimmed substringFromIndex:2];
        } else if ([trimmed hasPrefix:@"#### "]) {
            lineBaseFont = h3Font;
            lineBoldFont = h3Font;
            lineColor = h3Color;
            lineContent = [trimmed substringFromIndex:5];
        }

        NSMutableParagraphStyle *paraStyle = [[NSMutableParagraphStyle alloc] init];
        paraStyle.lineSpacing = 2.5;
        if (lineBaseFont == h1Font || lineBaseFont == h2Font) {
            paraStyle.paragraphSpacing = 5.0;
            paraStyle.paragraphSpacingBefore = 3.0;
        } else {
            paraStyle.paragraphSpacing = 2.0;
        }

        // 2. Parse inline **bold** text in the line
        NSMutableAttributedString *lineAttr = [[NSMutableAttributedString alloc] init];
        NSArray *boldParts = [lineContent componentsSeparatedByString:@"**"];

        for (NSInteger p = 0; p < boldParts.count; p++) {
            NSString *part = boldParts[p];
            if (part.length == 0) continue;

            BOOL isBold = (p % 2 == 1);
            UIFont *partFont = isBold ? lineBoldFont : lineBaseFont;

            NSDictionary *attrs = @{
                NSFontAttributeName: partFont,
                NSForegroundColorAttributeName: lineColor,
                NSParagraphStyleAttributeName: paraStyle
            };
            [lineAttr appendAttributedString:[[NSAttributedString alloc] initWithString:part attributes:attrs]];
        }

        [finalAttrString appendAttributedString:lineAttr];

        if (i < lines.count - 1) {
            [finalAttrString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"
                                                                                    attributes:@{
                                                                                        NSFontAttributeName: lineBaseFont,
                                                                                        NSParagraphStyleAttributeName: paraStyle
                                                                                    }]];
        }
    }

    return finalAttrString;
}

#pragma mark - Sizing & Height

+ (NSAttributedString *)attributedTextForMessage:(ChatMessage *)message {
    if (!message.attributedText) {
        BOOL isUser = (message.sender == ChatMessageSenderUser);
        message.attributedText = [self parseMarkdown:message.text isUser:isUser];
    }
    return message.attributedText;
}

+ (CGSize)sizeForAttributedText:(NSAttributedString *)attrString maxWidth:(CGFloat)maxWidth {
    if (!attrString || attrString.length == 0) return CGSizeZero;

    CGRect rect = [attrString boundingRectWithSize:CGSizeMake(maxWidth, CGFLOAT_MAX)
                                           options:(NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading)
                                           context:nil];
    return CGSizeMake(ceil(rect.size.width), ceil(rect.size.height) + 4.0);
}

+ (CGFloat)heightForMessage:(ChatMessage *)message containerWidth:(CGFloat)width {
    if (message.cachedHeight > 0) {
        return message.cachedHeight;
    }

    NSAttributedString *attr = [self attributedTextForMessage:message];
    CGFloat maxBubbleW = width * kMaxBubbleWidthRatio;
    CGFloat maxTextW = maxBubbleW - (kInnerHorizontalPad * 2);

    CGSize textSize = [self sizeForAttributedText:attr maxWidth:maxTextW];
    CGFloat totalH = textSize.height + (kInnerVerticalPad * 2) + (kVerticalMargin * 2) + 2.0;

    if (totalH < 44.0) totalH = 44.0;
    message.cachedHeight = totalH;
    return totalH;
}

#pragma mark - Configure Cell (Classic iMessage Bubble Alignment with Expanded Width)

- (void)configureWithMessage:(ChatMessage *)message containerWidth:(CGFloat)width {
    _message = message;
    NSAttributedString *attr = [[self class] attributedTextForMessage:message];
    _messageTextView.attributedText = attr;

    CGFloat maxBubbleW = width * kMaxBubbleWidthRatio;
    CGFloat maxTextW = maxBubbleW - (kInnerHorizontalPad * 2);

    CGSize textSize = [[self class] sizeForAttributedText:attr maxWidth:maxTextW];
    CGFloat bubbleWidth = textSize.width + (kInnerHorizontalPad * 2);
    if (bubbleWidth > maxBubbleW) bubbleWidth = maxBubbleW;
    CGFloat bubbleHeight = textSize.height + (kInnerVerticalPad * 2);

    if (message.sender == ChatMessageSenderUser) {
        // Kullanıcı: Sağ tarafa yaslı iMessage balonu (OpenAI Yeşili)
        _bubbleBackgroundView.backgroundColor = [UIColor colorWithRed:16.0/255.0 green:163.0/255.0 blue:127.0/255.0 alpha:1.0];
        _bubbleBackgroundView.layer.borderWidth = 0.0;
        CGFloat x = width - bubbleWidth - kHorizontalMargin;
        _bubbleBackgroundView.frame = CGRectMake(x, kVerticalMargin, bubbleWidth, bubbleHeight);
    } else {
        // Asistan: Sol tarafa yaslı iMessage balonu (Şık Açık Gri Balon)
        _bubbleBackgroundView.backgroundColor = [UIColor colorWithRed:0.91 green:0.91 blue:0.93 alpha:1.0];
        _bubbleBackgroundView.layer.borderColor = [UIColor colorWithWhite:0.84 alpha:1.0].CGColor;
        _bubbleBackgroundView.layer.borderWidth = 0.5;
        CGFloat x = kHorizontalMargin;
        _bubbleBackgroundView.frame = CGRectMake(x, kVerticalMargin, bubbleWidth, bubbleHeight);
    }

    _messageTextView.frame = CGRectMake(kInnerHorizontalPad, kInnerVerticalPad, textSize.width, textSize.height);
}

@end
