#import "ChatMessage.h"

@implementation ChatMessage

+ (instancetype)messageWithText:(NSString *)text sender:(ChatMessageSender)sender {
    ChatMessage *msg = [[ChatMessage alloc] init];
    msg.text = text;
    msg.sender = sender;
    msg.timestamp = [NSDate date];
    msg.cachedHeight = 0;
    return msg;
}

@end
