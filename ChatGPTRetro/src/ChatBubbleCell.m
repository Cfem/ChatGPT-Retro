#import "ChatBubbleCell.h"

static const CGFloat kHorizontalPadding = 14.0;
static const CGFloat kVerticalPadding = 9.0;
static const CGFloat kMaxBubbleWidthRatio = 0.72;
static const CGFloat kCornerRadius = 16.0;

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

        _messageLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _messageLabel.numberOfLines = 0;
        _messageLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:16.0];
        _messageLabel.lineBreakMode = NSLineBreakByWordWrapping;
        _messageLabel.backgroundColor = [UIColor clearColor];
        [_bubbleBackgroundView addSubview:_messageLabel];
    }
    return self;
}

+ (UIFont *)messageFont {
    return [UIFont fontWithName:@"HelveticaNeue" size:16.0];
}

+ (CGSize)sizeForText:(NSString *)text maxWidth:(CGFloat)maxWidth {
    if (!text || text.length == 0) return CGSizeZero;
    
    CGRect rect = [text boundingRectWithSize:CGSizeMake(maxWidth, CGFLOAT_MAX)
                                     options:(NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading)
                                  attributes:@{NSFontAttributeName: [self messageFont]}
                                     context:nil];
    return CGSizeMake(ceil(rect.size.width), ceil(rect.size.height));
}

+ (CGFloat)heightForMessage:(ChatMessage *)message containerWidth:(CGFloat)width {
    if (message.cachedHeight > 0) {
        return message.cachedHeight;
    }

    CGFloat maxBubbleW = width * kMaxBubbleWidthRatio;
    CGFloat maxTextW = maxBubbleW - (kHorizontalPadding * 2);
    CGSize textSize = [self sizeForText:message.text maxWidth:maxTextW];

    CGFloat totalH = textSize.height + (kVerticalPadding * 2) + 8.0;
    if (totalH < 44.0) totalH = 44.0;
    message.cachedHeight = totalH;
    return totalH;
}

- (void)configureWithMessage:(ChatMessage *)message containerWidth:(CGFloat)width {
    _message = message;
    _messageLabel.text = message.text;

    CGFloat maxBubbleW = width * kMaxBubbleWidthRatio;
    CGFloat maxTextW = maxBubbleW - (kHorizontalPadding * 2);
    CGSize textSize = [[self class] sizeForText:message.text maxWidth:maxTextW];

    CGFloat bubbleW = textSize.width + (kHorizontalPadding * 2);
    CGFloat bubbleH = textSize.height + (kVerticalPadding * 2);

    if (message.sender == ChatMessageSenderUser) {
        // OpenAI Teal/Green accent for user bubble or iOS Blue
        _bubbleBackgroundView.backgroundColor = [UIColor colorWithRed:16.0/255.0 green:163.0/255.0 blue:127.0/255.0 alpha:1.0];
        _messageLabel.textColor = [UIColor whiteColor];
        CGFloat x = width - bubbleW - 14.0;
        _bubbleBackgroundView.frame = CGRectMake(x, 4.0, bubbleW, bubbleH);
    } else {
        // Soft Neutral Gray Bubble
        _bubbleBackgroundView.backgroundColor = [UIColor colorWithRed:0.92 green:0.92 blue:0.93 alpha:1.0];
        _messageLabel.textColor = [UIColor blackColor];
        CGFloat x = 14.0;
        _bubbleBackgroundView.frame = CGRectMake(x, 4.0, bubbleW, bubbleH);
    }

    _messageLabel.frame = CGRectMake(kHorizontalPadding, kVerticalPadding, textSize.width, textSize.height);
}

@end
