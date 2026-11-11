#import <Foundation/Foundation.h>

typedef void (^GeminiCompletionHandler)(NSString *response, NSError *error);
typedef void (^GeminiModelsHandler)(NSArray *models, NSError *error);
typedef void (^GeminiDeviceAuthHandler)(NSString *userCode, NSString *verificationUrl, NSString *deviceCode, NSError *error);
typedef void (^GeminiTokenPollHandler)(BOOL success, NSError *error);

@interface GeminiClient : NSObject

@property (nonatomic, readonly) NSString *apiKey;
@property (nonatomic, readonly) NSString *selectedModel;
@property (nonatomic, readonly) NSString *oauthAccessToken;
@property (nonatomic, readonly) NSString *oauthClientId;
@property (nonatomic, readonly) NSString *oauthClientSecret;
@property (nonatomic, readonly) NSString *userEmail;

+ (instancetype)sharedClient;

- (BOOL)isAuthenticated;
- (BOOL)hasOAuthCredentials;
- (BOOL)isGoogleAccountLinked;
- (void)signOutGoogleAccount;

- (void)startDeviceAuthFlowWithCompletion:(GeminiDeviceAuthHandler)completion;
- (void)pollDeviceTokenWithDeviceCode:(NSString *)deviceCode 
                             interval:(NSInteger)interval 
                           completion:(GeminiTokenPollHandler)completion;

- (void)fetchAvailableModelsWithCompletion:(GeminiModelsHandler)completion;
- (NSString *)customRequestPayloadTemplate;

- (void)sendMessage:(NSString *)prompt 
            history:(NSArray *)historyMessages 
         completion:(GeminiCompletionHandler)completion;

@end
