#import <Foundation/Foundation.h>

typedef void (^GeminiCompletionHandler)(NSString *response, NSError *error);
typedef void (^GeminiModelsHandler)(NSArray *models, NSError *error);
typedef void (^GeminiDeviceAuthHandler)(NSString *userCode, NSString *verificationUrl, NSString *deviceCode, NSError *error);
typedef void (^GeminiTokenPollHandler)(BOOL success, NSError *error);
typedef void (^GeminiExchangeCodeHandler)(BOOL success, NSError *error);

@interface GeminiClient : NSObject

@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, copy) NSString *selectedModel;
@property (nonatomic, copy) NSString *oauthClientId;
@property (nonatomic, copy) NSString *oauthClientSecret;
@property (nonatomic, copy) NSString *oauthAccessToken;
@property (nonatomic, copy) NSString *userEmail;

+ (instancetype)sharedClient;

- (void)saveOAuthClientId:(NSString *)clientId secret:(NSString *)secret;
- (void)saveApiKey:(NSString *)apiKey;
- (void)saveSelectedModel:(NSString *)model;
- (void)signOutGoogleAccount;

- (BOOL)isAuthenticated;
- (BOOL)hasOAuthCredentials;
- (BOOL)isGoogleAccountLinked;

// Out-of-band / Standard OAuth (Gemini only scope)
- (NSString *)standardOAuthAuthorizationURL;
- (void)exchangeAuthCode:(NSString *)rawInput completion:(GeminiExchangeCodeHandler)completion;

// Device Flow (RFC 8628 fallback)
- (void)startDeviceAuthFlowWithCompletion:(GeminiDeviceAuthHandler)completion;
- (void)pollDeviceTokenWithDeviceCode:(NSString *)deviceCode 
                             interval:(NSInteger)interval 
                           completion:(GeminiTokenPollHandler)completion;

- (void)fetchAvailableModelsWithCompletion:(GeminiModelsHandler)completion;

- (void)sendMessage:(NSString *)prompt 
            history:(NSArray *)historyMessages 
         completion:(GeminiCompletionHandler)completion;

@end
