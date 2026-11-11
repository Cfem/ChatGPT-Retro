#import <Foundation/Foundation.h>

typedef void (^GeminiCompletionHandler)(NSString *response, NSError *error);

@interface GeminiClient : NSObject

@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, copy) NSString *selectedModel;

+ (instancetype)sharedClient;

- (void)saveApiKey:(NSString *)apiKey;
- (void)saveSelectedModel:(NSString *)model;
- (BOOL)hasApiKey;

- (void)sendMessage:(NSString *)prompt 
            history:(NSArray *)historyMessages 
         completion:(GeminiCompletionHandler)completion;

@end
