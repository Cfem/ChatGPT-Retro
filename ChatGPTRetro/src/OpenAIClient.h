#import <Foundation/Foundation.h>

typedef void (^OpenAICompletionHandler)(NSString *response, NSError *error);
typedef void (^OpenAIModelsHandler)(NSArray *models, NSError *error);
typedef void (^OpenAISignInHandler)(BOOL success, NSError *error);

extern NSString *const kChatGPTAuthStateDidChangeNotification;

@interface OpenAIClient : NSObject

@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, copy) NSString *selectedModel;

// Sign in with ChatGPT (SIWC) OAuth 2.0 + PKCE Properties
@property (nonatomic, copy, readonly) NSString *hostId;
@property (nonatomic, copy, readonly) NSString *issuedClientId;
@property (nonatomic, copy, readonly) NSString *oauthAccessToken;
@property (nonatomic, copy, readonly) NSString *oauthRefreshToken;
@property (nonatomic, copy, readonly) NSString *userEmail;
@property (nonatomic, copy, readonly) NSString *userName;
@property (nonatomic, assign, readonly) BOOL isPlanSharingEnabled;

+ (instancetype)sharedClient;

- (void)saveApiKey:(NSString *)apiKey;
- (void)saveSelectedModel:(NSString *)model;

- (BOOL)isChatGPTAccountLinked;
- (BOOL)isAuthenticated;

// SIWC Direct Browser / Safari OAuth Methods
- (void)startSignInWithChatGPTInSafariWithCompletion:(OpenAISignInHandler)completion;
- (NSString *)currentAuthorizationURL;
- (void)handleIncomingCallbackURLString:(NSString *)urlString completion:(OpenAISignInHandler)completion;
- (void)disconnectChatGPTAccountWithCompletion:(void (^)(void))completion;

// API Methods
- (void)fetchAvailableModelsWithCompletion:(OpenAIModelsHandler)completion;

- (void)sendMessage:(NSString *)prompt 
            history:(NSArray *)historyMessages 
          webSearch:(BOOL)webSearch
         completion:(OpenAICompletionHandler)completion;

@end
