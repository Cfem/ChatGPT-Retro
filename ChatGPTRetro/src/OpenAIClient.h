#import <Foundation/Foundation.h>

typedef void (^OpenAICompletionHandler)(NSString *response, NSError *error);
typedef void (^OpenAIModelsHandler)(NSArray *models, NSError *error);
typedef void (^OpenAISignInHandler)(BOOL success, NSError *error);

extern NSString *const kChatGPTAuthStateDidChangeNotification;

@interface OpenAIClient : NSObject

@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, copy) NSString *selectedModel;
@property (nonatomic, copy) NSString *customSystemInstruction;

// Model Capabilities & Extra Request Parameters (Per OpenAI Responses/Completions Docs)
// reasoningEffortLevel: 0=none, 1=minimal, 2=low, 3=medium, 4=high, 5=xhigh, 6=max
@property (nonatomic, assign) NSInteger reasoningEffortLevel;
@property (nonatomic, assign) BOOL enableReasoningSummary;
@property (nonatomic, assign) BOOL enableWebSearch;
@property (nonatomic, assign) BOOL enableCodeInterpreter;
@property (nonatomic, assign) float modelTemperature;

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
- (void)saveCustomSystemInstruction:(NSString *)instruction;

// Model Capability Inspection (Dynamic UI Helpers)
- (BOOL)supportsReasoningEffortForModel:(NSString *)model;
- (BOOL)supportsWebSearchForModel:(NSString *)model;
- (BOOL)supportsCodeInterpreterForModel:(NSString *)model;
- (BOOL)supportsTemperatureForModel:(NSString *)model;
- (NSString *)reasoningEffortApiValueForLevel:(NSInteger)level;

- (BOOL)isChatGPTAccountLinked;
- (BOOL)isAuthenticated;

// SIWC Direct Browser / Safari OAuth Methods
- (void)startSignInWithChatGPTInSafariWithCompletion:(OpenAISignInHandler)completion;
- (NSString *)prepareOAuthAuthorizationURL;
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
