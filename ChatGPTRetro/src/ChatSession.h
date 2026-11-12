#import <Foundation/Foundation.h>

@interface ChatSession : NSObject

@property (nonatomic, copy) NSString *sessionId;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) NSDate *updatedAt;
@property (nonatomic, strong) NSMutableArray *messages; // Array of ChatMessage objects

+ (instancetype)sessionWithTitle:(NSString *)title;
- (NSDictionary *)dictionaryRepresentation;
+ (instancetype)sessionFromDictionary:(NSDictionary *)dict;

@end
