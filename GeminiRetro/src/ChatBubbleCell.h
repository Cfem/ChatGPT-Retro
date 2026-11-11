#import <UIKit/UIKit.h>
#import "ChatMessage.h"

@interface ChatBubbleCell : UITableViewCell

@property (nonatomic, strong) UIView *bubbleBackgroundView;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) ChatMessage *message;

- (void)configureWithMessage:(ChatMessage *)message containerWidth:(CGFloat)width;
+ (CGFloat)heightForMessage:(ChatMessage *)message containerWidth:(CGFloat)width;

@end
