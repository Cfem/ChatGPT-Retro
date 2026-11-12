#import "ChatBubbleCell.h"

static const CGFloat kHorizontalMargin = 12.0;
static const CGFloat kVerticalMargin = 4.0;
static const CGFloat kInnerHorizontalPad = 14.0;
static const CGFloat kInnerVerticalPad = 10.0;
static const CGFloat kCornerRadius = 14.0;

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

        // UITextView for selectable, copyable text with rich Markdown formatting
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

#pragma mark - Markdown Parser

+ (NSAttributedString *)parseMarkdown:(NSString *)rawText isUser:(BOOL)isUser {
    if (!rawText || rawText.length == 0) {
        return [[NSAttributedString alloc] initWithString:@""];
    }

    UIColor *baseTextColor = isUser ? [UIColor whiteColor] : [UIColor colorWithRed:0.13 green:0.13 blue:0.14 alpha:1.0];
    UIColor *h1Color = isUser ? [UIColor whiteColor] : [UIColor colorWithRed:0.08 green:0.08 blue:0.09 alpha:1.0];
    UIColor *h2Color = isUser ? [UIColor whiteColor] : [UIColor colorWithRed:16.0/255.0 green:163.0/255.0 blue:127.0/255.0 alpha:1.0]; // OpenAI Green
    UIColor *h3Color = isUser ? [UIColor whiteColor] : [UIColor colorWithRed:0.25 green:0.25 blue:0.26 alpha:1.0];

    UIFont *bodyFont = [UIFont fontWithName:@"HelveticaNeue" size:16.0];
    UIFont *boldBodyFont = [UIFont fontWithName:@"HelveticaNeue-Bold" size:16.0];
    UIFont *h1Font = [UIFont fontWithName:@"HelveticaNeue-Bold" size:22.0];
    UIFont *h2Font = [UIFont fontWithName:@"HelveticaNeue-Bold" size:19.0];
    UIFont *h3Font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:17.0];

    NSMutableAttributedString *finalAttrString = [[NSMutableAttributedString alloc] init];
    NSArray *lines = [rawText componentsSeparatedByString:@"\n"];

    for (NSInteger i = 0; i < lines.count; i++) {
        NSString *line = lines[i];
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

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
        paraStyle.lineSpacing = 3.0;
        if (lineBaseFont == h1Font || lineBaseFont == h2Font) {
            paraStyle.paragraphSpacing = 6.0;
            paraStyle.paragraphSpacingBefore = 4.0;
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
    CGFloat bubbleWidth = width - (kHorizontalMargin * 2);
    CGFloat textWidth = bubbleWidth - (kInnerHorizontalPad * 2);

    CGSize textSize = [self sizeForAttributedText:attr maxWidth:textWidth];
    CGFloat totalH = textSize.height + (kInnerVerticalPad * 2) + (kVerticalMargin * 2) + 2.0;

    if (totalH < 48.0) totalH = 48.0;
    message.cachedHeight = totalH;
    return totalH;
}

#pragma mark - Configure Cell

- (void)configureWithMessage:(ChatMessage *)message containerWidth:(CGFloat)width {
    _message = message;
    NSAttributedString *attr = [[self class] attributedTextForMessage:message];
    _messageTextView.attributedText = attr;

    // Full screen width from left margin to right margin
    CGFloat bubbleX = kHorizontalMargin;
    CGFloat bubbleWidth = width - (kHorizontalMargin * 2);
    CGFloat textWidth = bubbleWidth - (kInnerHorizontalPad * 2);

    CGSize textSize = [[self class] sizeForAttributedText:attr maxWidth:textWidth];
    CGFloat bubbleHeight = textSize.height + (kInnerVerticalPad * 2);

    _bubbleBackgroundView.frame = CGRectMake(bubbleX, kVerticalMargin, bubbleWidth, bubbleHeight);
    _messageTextView.frame = CGRectMake(kInnerHorizontalPad, kInnerVerticalPad, textWidth, textSize.height);

    if (message.sender == ChatMessageSenderUser) {
        // User: OpenAI Deep Green Accent
        _bubbleBackgroundView.backgroundColor = [UIColor colorWithRed:16.0/255.0 green:163.0/255.0 blue:127.0/255.0 alpha:0.96];
        _bubbleBackgroundView.layer.borderColor = [UIColor colorWithRed:14.0/255.0 green:140.0/255.0 blue:110.0/255.0 alpha:1.0].CGColor;
        _bubbleBackgroundView.layer.borderWidth = 0.5;
    } else {
        // Assistant: Clean Modern Neutral Off-White Card
        _bubbleBackgroundView.backgroundColor = [UIColor whiteColor];
        _bubbleBackgroundView.layer.borderColor = [UIColor colorWithWhite:0.86 alpha:1.0].CGColor;
        _bubbleBackgroundView.layer.borderWidth = 0.8;
    }
}

@end
