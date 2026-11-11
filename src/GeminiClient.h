#import <Foundation/Foundation.h>

typedef void (^GeminiCompletionHandler)(NSString *response, NSError *error);

@interface GeminiClient : NSObject

@property (nonatomic, readonly) NSString *apiKey;
@property (nonatomic, readonly) NSString *selectedModel;
@property (nonatomic, readonly) NSString *oauthAccessToken;

+ (instancetype)sharedClient;

- (BOOL)isAuthenticated;
- (NSString *)customRequestPayloadTemplate;

- (void)sendMessage:(NSString *)prompt 
            history:(NSArray *)historyMessages 
         completion:(GeminiCompletionHandler)completion;

@end
