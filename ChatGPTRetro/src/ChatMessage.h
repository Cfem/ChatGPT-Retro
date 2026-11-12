#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, ChatMessageSender) {
    ChatMessageSenderUser,
    ChatMessageSenderAssistant
};

@interface ChatMessage : NSObject

@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) NSAttributedString *attributedText;
@property (nonatomic, assign) ChatMessageSender sender;
@property (nonatomic, strong) NSDate *timestamp;
@property (nonatomic, assign) CGFloat cachedHeight;
@property (nonatomic, assign) BOOL isLoading;

+ (instancetype)messageWithText:(NSString *)text sender:(ChatMessageSender)sender;

- (NSDictionary *)dictionaryRepresentation;
+ (instancetype)messageFromDictionary:(NSDictionary *)dict;

@end
