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

- (NSDictionary *)dictionaryRepresentation {
    return @{
        @"text": self.text ?: @"",
        @"sender": @(self.sender),
        @"timestamp": @([self.timestamp timeIntervalSince1970])
    };
}

+ (instancetype)messageFromDictionary:(NSDictionary *)dict {
    if (!dict || ![dict isKindOfClass:[NSDictionary class]]) return nil;
    NSString *text = dict[@"text"] ?: @"";
    ChatMessageSender sender = [dict[@"sender"] integerValue];
    ChatMessage *msg = [ChatMessage messageWithText:text sender:sender];
    if (dict[@"timestamp"]) {
        msg.timestamp = [NSDate dateWithTimeIntervalSince1970:[dict[@"timestamp"] doubleValue]];
    }
    return msg;
}

@end
