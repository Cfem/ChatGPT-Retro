#import "GeminiClient.h"
#import "ChatMessage.h"

static NSString *const kGeminiAuthModeKey = @"GeminiClientAuthMode";
static NSString *const kGeminiApiKeyDefaultsKey = @"GeminiClientApiKey";
static NSString *const kGeminiModelDefaultsKey = @"GeminiClientModel";
static NSString *const kGeminiCachedModelsKey = @"GeminiClientCachedModels";
static NSString *const kGeminiOAuthAccessTokenKey = @"GeminiOAuthAccessToken";
static NSString *const kGeminiOAuthRefreshTokenKey = @"GeminiOAuthRefreshToken";
static NSString *const kGeminiOAuthEmailKey = @"GeminiOAuthEmail";
static NSString *const kCustomPayloadTemplateKey = @"custom_request_payload";
static NSString *const kCustomEndpointKey = @"custom_api_endpoint";
static NSString *const kGoogleSearchEnabledKey = @"enable_google_search";
static NSString *const kDefaultModel = @"gemini-1.5-flash";

// Google OAuth 2.0 Standard Device Client Credentials
// (İsteğe bağlı olarak kullanıcı Settings.bundle'dan kendi Client ID'sini de tanımlayabilir)
static NSString *const kDefaultOAuthClientId = @"808796851608-n3g007h3s7g5aomftv1a07uhb3j58ncf.apps.googleusercontent.com";
static NSString *const kDefaultOAuthClientSecret = @"GOCSPX-LqE5i23Gg7d-6_B4wZvZ7wL5aA";

@interface GeminiClient ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSTimer *pollTimer;
@property (nonatomic, copy) GeminiTokenPollHandler activePollHandler;
@end

@implementation GeminiClient

+ (instancetype)sharedClient {
    static GeminiClient *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[GeminiClient alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        _authMode = [defaults integerForKey:kGeminiAuthModeKey];
        _apiKey = [defaults stringForKey:kGeminiApiKeyDefaultsKey] ?: @"";
        _selectedModel = [defaults stringForKey:kGeminiModelDefaultsKey] ?: kDefaultModel;
        _cachedModels = [defaults arrayForKey:kGeminiCachedModelsKey] ?: @[];
        _oauthAccessToken = [defaults stringForKey:kGeminiOAuthAccessTokenKey] ?: @"";
        _oauthRefreshToken = [defaults stringForKey:kGeminiOAuthRefreshTokenKey] ?: @"";
        _userEmail = [defaults stringForKey:kGeminiOAuthEmailKey] ?: @"";

        if ([defaults objectForKey:kGoogleSearchEnabledKey] == nil) {
            [defaults setBool:YES forKey:kGoogleSearchEnabledKey];
            [defaults synchronize];
        }

        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 60.0;
        config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        _session = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}

- (void)saveAuthMode:(GeminiAuthMode)mode {
    _authMode = mode;
    [[NSUserDefaults standardUserDefaults] setInteger:mode forKey:kGeminiAuthModeKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)saveApiKey:(NSString *)apiKey {
    _apiKey = [apiKey stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [[NSUserDefaults standardUserDefaults] setObject:_apiKey forKey:kGeminiApiKeyDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)saveSelectedModel:(NSString *)model {
    _selectedModel = model ?: kDefaultModel;
    [[NSUserDefaults standardUserDefaults] setObject:_selectedModel forKey:kGeminiModelDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)isAuthenticated {
    if (self.authMode == GeminiAuthModeApiKey) {
        return (self.apiKey && self.apiKey.length > 5);
    } else {
        return (self.oauthAccessToken && self.oauthAccessToken.length > 10);
    }
}

- (void)signOutGoogleAccount {
    _oauthAccessToken = @"";
    _oauthRefreshToken = @"";
    _userEmail = @"";
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kGeminiOAuthAccessTokenKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kGeminiOAuthRefreshTokenKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kGeminiOAuthEmailKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - Google OAuth 2.0 Device Flow

- (void)startDeviceAuthFlowWithCompletion:(GeminiDeviceAuthHandler)completion {
    NSURL *url = [NSURL URLWithString:@"https://oauth2.googleapis.com/device/code"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];

    NSString *scope = @"https://www.googleapis.com/auth/generative-language email profile";
    NSString *bodyStr = [NSString stringWithFormat:@"client_id=%@&scope=%@", kDefaultOAuthClientId, [scope stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    [request setHTTPBody:[bodyStr dataUsingEncoding:NSUTF8StringEncoding]];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, nil, nil, error);
            });
            return;
        }

        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *userCode = json[@"user_code"];
        NSString *verificationUrl = json[@"verification_url"] ?: @"https://www.google.com/device";
        NSString *deviceCode = json[@"device_code"];

        if (!userCode || !deviceCode) {
            NSString *errMsg = json[@"error_description"] ?: @"Google Device Flow başlatılamadı.";
            NSError *err = [NSError errorWithDomain:@"GeminiOAuth" code:400 userInfo:@{NSLocalizedDescriptionKey: errMsg}];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, nil, nil, err);
            });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(userCode, verificationUrl, deviceCode, nil);
        });
    }];
    [task resume];
}

- (void)pollDeviceTokenWithDeviceCode:(NSString *)deviceCode 
                             interval:(NSInteger)interval 
                           completion:(GeminiTokenPollHandler)completion {
    [self.pollTimer invalidate];
    self.activePollHandler = completion;

    NSInteger pollSec = (interval > 3) ? interval : 5;
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:pollSec
                                                      target:self
                                                    selector:@selector(checkTokenStatus:)
                                                    userInfo:deviceCode
                                                     repeats:YES];
}

- (void)checkTokenStatus:(NSTimer *)timer {
    NSString *deviceCode = timer.userInfo;
    NSURL *url = [NSURL URLWithString:@"https://oauth2.googleapis.com/token"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];

    NSString *bodyStr = [NSString stringWithFormat:@"client_id=%@&client_secret=%@&device_code=%@&grant_type=urn:ietf:params:oauth:grant-type:device_code",
                         kDefaultOAuthClientId, kDefaultOAuthClientSecret, deviceCode];
    [request setHTTPBody:[bodyStr dataUsingEncoding:NSUTF8StringEncoding]];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!data) return;

        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *accessToken = json[@"access_token"];
        NSString *refreshToken = json[@"refresh_token"];

        if (accessToken && accessToken.length > 0) {
            [timer invalidate];
            self.oauthAccessToken = accessToken;
            if (refreshToken) self.oauthRefreshToken = refreshToken;

            [[NSUserDefaults standardUserDefaults] setObject:self.oauthAccessToken forKey:kGeminiOAuthAccessTokenKey];
            if (refreshToken) [[NSUserDefaults standardUserDefaults] setObject:self.oauthRefreshToken forKey:kGeminiOAuthRefreshTokenKey];
            [[NSUserDefaults standardUserDefaults] synchronize];

            // Kullanıcı e-postasını al
            [self fetchUserEmail];

            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.activePollHandler) {
                    self.activePollHandler(YES, nil);
                    self.activePollHandler = nil;
                }
            });
            return;
        }

        NSString *err = json[@"error"];
        if ([err isEqualToString:@"authorization_pending"]) {
            // Kullanıcı henüz kodu onaylamadı, periyodik sorgulamaya devam
            return;
        } else if ([err isEqualToString:@"slow_down"]) {
            // Biraz daha yavaş sorgula
            return;
        } else {
            // Hata veya zaman aşımı
            [timer invalidate];
            NSString *desc = json[@"error_description"] ?: @"Giriş tamamlanamadı veya süresi doldu.";
            NSError *failErr = [NSError errorWithDomain:@"GeminiOAuth" code:400 userInfo:@{NSLocalizedDescriptionKey: desc}];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.activePollHandler) {
                    self.activePollHandler(NO, failErr);
                    self.activePollHandler = nil;
                }
            });
        }
    }];
    [task resume];
}

- (void)fetchUserEmail {
    if (!self.oauthAccessToken || self.oauthAccessToken.length == 0) return;
    NSURL *url = [NSURL URLWithString:@"https://www.googleapis.com/oauth2/v2/userinfo"];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setValue:[NSString stringWithFormat:@"Bearer %@", self.oauthAccessToken] forHTTPHeaderField:@"Authorization"];

    [[self.session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *res, NSError *err) {
        if (data) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (json[@"email"]) {
                self.userEmail = json[@"email"];
                [[NSUserDefaults standardUserDefaults] setObject:self.userEmail forKey:kGeminiOAuthEmailKey];
                [[NSUserDefaults standardUserDefaults] synchronize];
            }
        }
    }] resume];
}

- (NSString *)customRequestPayloadTemplate {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kCustomPayloadTemplateKey];
}

- (void)fetchAvailableModelsWithCompletion:(GeminiModelsHandler)completion {
    if (![self isAuthenticated]) {
        if (completion) {
            NSError *err = [NSError errorWithDomain:@"GeminiClient" code:401 userInfo:@{NSLocalizedDescriptionKey: @"Lütfen önce giriş yapın veya API Key girin."}];
            completion(nil, err);
        }
        return;
    }

    NSString *urlString;
    if (self.authMode == GeminiAuthModeApiKey) {
        urlString = [NSString stringWithFormat:@"https://generativelanguage.googleapis.com/v1beta/models?key=%@", self.apiKey];
    } else {
        urlString = @"https://generativelanguage.googleapis.com/v1beta/models";
    }

    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"GET"];

    if (self.authMode == GeminiAuthModeOAuth && self.oauthAccessToken.length > 0) {
        [request setValue:[NSString stringWithFormat:@"Bearer %@", self.oauthAccessToken] forHTTPHeaderField:@"Authorization"];
    }

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, error);
            });
            return;
        }

        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSArray *rawModels = json[@"models"];
        NSMutableArray *supported = [NSMutableArray array];

        for (NSDictionary *m in rawModels) {
            NSArray *methods = m[@"supportedGenerationMethods"];
            if ([methods containsObject:@"generateContent"]) {
                NSString *name = m[@"name"];
                if ([name hasPrefix:@"models/"]) {
                    name = [name substringFromIndex:7];
                }
                if (name.length > 0) {
                    [supported addObject:name];
                }
            }
        }

        self.cachedModels = supported;
        [[NSUserDefaults standardUserDefaults] setObject:supported forKey:kGeminiCachedModelsKey];
        [[NSUserDefaults standardUserDefaults] synchronize];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(supported, nil);
        });
    }];
    [task resume];
}

- (void)sendMessage:(NSString *)prompt 
            history:(NSArray *)historyMessages 
         completion:(GeminiCompletionHandler)completion {
    if (![self isAuthenticated]) {
        if (completion) {
            NSString *msg = (self.authMode == GeminiAuthModeApiKey) ? 
                @"API Key girilmedi. Ayarlar'dan API anahtarınızı girin." : 
                @"Google hesabınıza giriş yapılmadı. Ayarlar'dan Google ile giriş yapın.";
            NSError *err = [NSError errorWithDomain:@"GeminiClient" code:401 userInfo:@{NSLocalizedDescriptionKey: msg}];
            completion(nil, err);
        }
        return;
    }

    NSString *model = self.selectedModel.length > 0 ? self.selectedModel : kDefaultModel;
    if ([model hasPrefix:@"models/"]) {
        model = [model substringFromIndex:7];
    }

    NSString *customBaseUrl = [[NSUserDefaults standardUserDefaults] stringForKey:kCustomEndpointKey];
    NSString *baseUrl = (customBaseUrl && customBaseUrl.length > 5) ? customBaseUrl : @"https://generativelanguage.googleapis.com/v1beta";

    NSString *urlString;
    if (self.authMode == GeminiAuthModeApiKey) {
        urlString = [NSString stringWithFormat:@"%@/models/%@:generateContent?key=%@", baseUrl, model, self.apiKey];
    } else {
        urlString = [NSString stringWithFormat:@"%@/models/%@:generateContent", baseUrl, model];
    }

    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];

    if (self.authMode == GeminiAuthModeOAuth && self.oauthAccessToken.length > 0) {
        [request setValue:[NSString stringWithFormat:@"Bearer %@", self.oauthAccessToken] forHTTPHeaderField:@"Authorization"];
    }

    // Gerçek konuşma geçmişi (Hardcoded karşılama mesajlarını filtrele)
    NSMutableArray *contents = [NSMutableArray array];
    NSMutableArray *filteredHistory = [NSMutableArray array];
    for (ChatMessage *msg in historyMessages) {
        if ([msg.text containsString:@"iPad Mini 1 (iOS 8.4"] || [msg.text isEqualToString:@"..."]) {
            continue;
        }
        [filteredHistory addObject:msg];
    }

    NSInteger startIndex = 0;
    if (filteredHistory.count > 8) {
        startIndex = filteredHistory.count - 8;
    }

    for (NSInteger i = startIndex; i < filteredHistory.count; i++) {
        ChatMessage *msg = filteredHistory[i];
        NSString *role = (msg.sender == ChatMessageSenderUser) ? @"user" : @"model";
        [contents addObject:@{
            @"role": role,
            @"parts": @[ @{ @"text": msg.text ?: @"" } ]
        }];
    }

    [contents addObject:@{
        @"role": @"user",
        @"parts": @[ @{ @"text": prompt ?: @"" } ]
    }];

    NSMutableDictionary *payloadDict = [NSMutableDictionary dictionary];
    payloadDict[@"contents"] = contents;
    payloadDict[@"generationConfig"] = @{
        @"temperature": @0.7,
        @"maxOutputTokens": @4096
    };

    BOOL isGoogleSearchEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:kGoogleSearchEnabledKey];
    if (isGoogleSearchEnabled) {
        payloadDict[@"tools"] = @[
            @{ @"googleSearch": @{} }
        ];
    }

    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:payloadDict options:0 error:nil];
    
    NSString *rawJson = [[NSString alloc] initWithData:bodyData encoding:NSUTF8StringEncoding];
    [[NSUserDefaults standardUserDefaults] setObject:rawJson forKey:@"last_raw_request"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    NSString *customPayload = [self customRequestPayloadTemplate];
    if (customPayload && customPayload.length > 10) {
        NSString *filled = [customPayload stringByReplacingOccurrencesOfString:@"{PROMPT}" withString:prompt];
        NSData *customData = [filled dataUsingEncoding:NSUTF8StringEncoding];
        if (customData) bodyData = customData;
    }

    [request setHTTPBody:bodyData];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, error);
            });
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            NSString *errMsg = [NSString stringWithFormat:@"HTTP Hatası %ld", (long)httpResponse.statusCode];
            if (data.length > 0) {
                NSDictionary *errJson = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                if (errJson && errJson[@"error"] && errJson[@"error"][@"message"]) {
                    errMsg = errJson[@"error"][@"message"];
                }
            }
            NSError *apiErr = [NSError errorWithDomain:@"GeminiClient" code:httpResponse.statusCode userInfo:@{NSLocalizedDescriptionKey: errMsg}];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, apiErr);
            });
            return;
        }

        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSMutableString *fullText = [NSMutableString string];
        NSMutableArray *sourcesList = [NSMutableArray array];

        NSArray *candidates = json[@"candidates"];
        if (candidates.count > 0) {
            NSDictionary *candidate = candidates[0];
            NSArray *parts = candidate[@"content"][@"parts"];
            for (NSDictionary *part in parts) {
                if (part[@"text"]) {
                    [fullText appendString:part[@"text"]];
                }
            }

            NSDictionary *grounding = candidate[@"groundingMetadata"];
            if (grounding) {
                NSArray *chunks = grounding[@"groundingChunks"];
                for (NSDictionary *c in chunks) {
                    NSDictionary *web = c[@"web"];
                    if (web) {
                        NSString *title = web[@"title"] ?: @"Web Kaynağı";
                        NSString *uri = web[@"uri"] ?: @"";
                        if (uri.length > 0) {
                            [sourcesList addObject:[NSString stringWithFormat:@"• %@ (%@)", title, uri]];
                        }
                    }
                }
            }
        }

        if (sourcesList.count > 0) {
            [fullText appendString:@"\n\n---\nKaynaklar:\n"];
            for (NSString *s in sourcesList) {
                [fullText appendString:s];
                [fullText appendString:@"\n"];
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion([fullText copy], nil);
            }
        });
    }];

    [task resume];
}

@end
