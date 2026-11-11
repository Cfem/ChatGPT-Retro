#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, GeminiAuthMode) {
    GeminiAuthModeApiKey = 0,
    GeminiAuthModeOAuth  = 1
};

typedef void (^GeminiCompletionHandler)(NSString *response, NSError *error);
typedef void (^GeminiModelsHandler)(NSArray *models, NSError *error);
typedef void (^GeminiDeviceAuthHandler)(NSString *userCode, NSString *verificationUrl, NSString *deviceCode, NSError *error);
typedef void (^GeminiTokenPollHandler)(BOOL success, NSError *error);

@interface GeminiClient : NSObject

@property (nonatomic, assign) GeminiAuthMode authMode;
@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, copy) NSString *selectedModel;
@property (nonatomic, strong) NSArray *cachedModels;

// OAuth Bilgileri
@property (nonatomic, copy) NSString *oauthAccessToken;
@property (nonatomic, copy) NSString *oauthRefreshToken;
@property (nonatomic, copy) NSString *userEmail;

+ (instancetype)sharedClient;

- (void)saveAuthMode:(GeminiAuthMode)mode;
- (void)saveApiKey:(NSString *)apiKey;
- (void)saveSelectedModel:(NSString *)model;
- (BOOL)isAuthenticated;

// Google OAuth 2.0 Device Flow (google.com/device)
- (void)startDeviceAuthFlowWithCompletion:(GeminiDeviceAuthHandler)completion;
- (void)pollDeviceTokenWithDeviceCode:(NSString *)deviceCode 
                             interval:(NSInteger)interval 
                           completion:(GeminiTokenPollHandler)completion;
- (void)signOutGoogleAccount;

- (void)fetchAvailableModelsWithCompletion:(GeminiModelsHandler)completion;
- (NSString *)customRequestPayloadTemplate;

- (void)sendMessage:(NSString *)prompt 
            history:(NSArray *)historyMessages 
         completion:(GeminiCompletionHandler)completion;

@end
