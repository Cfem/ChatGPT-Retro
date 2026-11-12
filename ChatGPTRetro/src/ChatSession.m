#import "ChatSession.h"
#import "ChatMessage.h"
#import "LocalizationManager.h"

@implementation ChatSession

+ (instancetype)sessionWithTitle:(NSString *)title {
    ChatSession *s = [[ChatSession alloc] init];
    s.sessionId = [[NSUUID UUID] UUIDString];
    s.title = (title && title.length > 0) ? title : LocalizedString(@"new_chat_title");
    s.updatedAt = [NSDate date];
    s.messages = [NSMutableArray array];
    return s;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableArray *msgDicts = [NSMutableArray array];
    for (ChatMessage *m in self.messages) {
        if ([m.text containsString:@"iPad Mini 1 (iOS 8.4)"]) continue;
        [msgDicts addObject:[m dictionaryRepresentation]];
    }
    return @{
        @"sessionId": self.sessionId ?: @"",
        @"title": self.title ?: @"Yeni Sohbet",
        @"updatedAt": @([self.updatedAt timeIntervalSince1970]),
        @"messages": msgDicts
    };
}

+ (instancetype)sessionFromDictionary:(NSDictionary *)dict {
    if (!dict || ![dict isKindOfClass:[NSDictionary class]]) return nil;
    ChatSession *s = [[ChatSession alloc] init];
    s.sessionId = dict[@"sessionId"] ?: [[NSUUID UUID] UUIDString];
    s.title = dict[@"title"] ?: @"Sohbet";
    if (dict[@"updatedAt"]) {
        s.updatedAt = [NSDate dateWithTimeIntervalSince1970:[dict[@"updatedAt"] doubleValue]];
    } else {
        s.updatedAt = [NSDate date];
    }
    s.messages = [NSMutableArray array];
    NSArray *rawMsgs = dict[@"messages"];
    if (rawMsgs && [rawMsgs isKindOfClass:[NSArray class]]) {
        for (NSDictionary *mDict in rawMsgs) {
            ChatMessage *m = [ChatMessage messageFromDictionary:mDict];
            if (m) {
                [s.messages addObject:m];
            }
        }
    }
    return s;
}

@end
