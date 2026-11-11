#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, ChatMessageSender) {
    ChatMessageSenderUser,
    ChatMessageSenderAssistant
};

@interface ChatMessage : NSObject

@property (nonatomic, copy) NSString *text;
@property (nonatomic, assign) ChatMessageSender sender;
@property (nonatomic, strong) NSDate *timestamp;
@property (nonatomic, assign) CGFloat cachedHeight;

+ (instancetype)messageWithText:(NSString *)text sender:(ChatMessageSender)sender;

@end
