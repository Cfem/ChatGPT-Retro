#import "GeminiClient.h"
#import "ChatMessage.h"

static NSString *const kGeminiApiKeyDefaultsKey = @"GeminiClientApiKey";
static NSString *const kGeminiModelDefaultsKey = @"GeminiClientModel";
static NSString *const kGeminiCachedModelsKey = @"GeminiClientCachedModels";
static NSString *const kGeminiOAuthClientIdKey = @"google_oauth_client_id";
static NSString *const kGeminiOAuthClientSecretKey = @"google_oauth_client_secret";
static NSString *const kGeminiOAuthAccessTokenKey = @"GeminiOAuthAccessToken";
static NSString *const kGeminiOAuthRefreshTokenKey = @"GeminiOAuthRefreshToken";
static NSString *const kGeminiOAuthEmailKey = @"GeminiOAuthEmail";
static NSString *const kCustomPayloadTemplateKey = @"custom_request_payload";
static NSString *const kCustomEndpointKey = @"custom_api_endpoint";
static NSString *const kGoogleSearchEnabledKey = @"enable_google_search";
static NSString *const kDefaultModel = @"gemini-1.5-flash";

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
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 60.0;
        config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        _session = [NSURLSession sessionWithConfiguration:config];
        [self synchronizeSettings];
    }
    return self;
}

- (void)synchronizeSettings {
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSString *)apiKey {
    [self synchronizeSettings];
    NSString *val = [[NSUserDefaults standardUserDefaults] stringForKey:kGeminiApiKeyDefaultsKey];
    return [val stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

- (NSString *)selectedModel {
    [self synchronizeSettings];
    NSString *m = [[NSUserDefaults standardUserDefaults] stringForKey:kGeminiModelDefaultsKey];
    m = [m stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return (m && m.length > 0) ? m : kDefaultModel;
}

- (NSString *)oauthClientId {
    [self synchronizeSettings];
    NSString *val = [[NSUserDefaults standardUserDefaults] stringForKey:kGeminiOAuthClientIdKey];
    return [val stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

- (NSString *)oauthClientSecret {
    [self synchronizeSettings];
    NSString *val = [[NSUserDefaults standardUserDefaults] stringForKey:kGeminiOAuthClientSecretKey];
    return [val stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

- (NSString *)oauthAccessToken {
    [self synchronizeSettings];
    return [[NSUserDefaults standardUserDefaults] stringForKey:kGeminiOAuthAccessTokenKey] ?: @"";
}

- (NSString *)userEmail {
    [self synchronizeSettings];
    return [[NSUserDefaults standardUserDefaults] stringForKey:kGeminiOAuthEmailKey] ?: @"";
}

- (BOOL)hasOAuthCredentials {
    return (self.oauthClientId.length > 5 && self.oauthClientSecret.length > 3);
}

- (BOOL)isGoogleAccountLinked {
    return (self.oauthAccessToken.length > 10);
}

- (BOOL)isAuthenticated {
    if (self.isGoogleAccountLinked) return YES;
    if (self.apiKey.length > 5) return YES;
    return NO;
}

- (void)signOutGoogleAccount {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kGeminiOAuthAccessTokenKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kGeminiOAuthRefreshTokenKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kGeminiOAuthEmailKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - OAuth Device Flow

- (void)startDeviceAuthFlowWithCompletion:(GeminiDeviceAuthHandler)completion {
    [self synchronizeSettings];
    if (![self hasOAuthCredentials]) {
        if (completion) {
            NSString *msg = [NSString stringWithFormat:@"Client ID: (%lu karakter), Secret: (%lu karakter). Lütfen iPad Ayarlar uygulamasından çıkıp Gemini uygulamasını açın veya 'Ayarları & Modelleri Eşitle' butonunu açın.",
                             (unsigned long)self.oauthClientId.length, (unsigned long)self.oauthClientSecret.length];
            NSError *err = [NSError errorWithDomain:@"GeminiOAuth" code:400 userInfo:@{NSLocalizedDescriptionKey: msg}];
            completion(nil, nil, nil, err);
        }
        return;
    }

    NSURL *url = [NSURL URLWithString:@"https://oauth2.googleapis.com/device/code"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];

    NSString *scope = @"https://www.googleapis.com/auth/generative-language email profile";
    NSString *bodyStr = [NSString stringWithFormat:@"client_id=%@&scope=%@", 
                         self.oauthClientId, [scope stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
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
                         self.oauthClientId, self.oauthClientSecret, deviceCode];
    [request setHTTPBody:[bodyStr dataUsingEncoding:NSUTF8StringEncoding]];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!data) return;

        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *accessToken = json[@"access_token"];
        NSString *refreshToken = json[@"refresh_token"];

        if (accessToken && accessToken.length > 0) {
            [timer invalidate];
            [[NSUserDefaults standardUserDefaults] setObject:accessToken forKey:kGeminiOAuthAccessTokenKey];
            if (refreshToken) [[NSUserDefaults standardUserDefaults] setObject:refreshToken forKey:kGeminiOAuthRefreshTokenKey];
            [[NSUserDefaults standardUserDefaults] synchronize];

            [self fetchUserEmail:accessToken];

            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.activePollHandler) {
                    self.activePollHandler(YES, nil);
                    self.activePollHandler = nil;
                }
            });
            return;
        }

        NSString *err = json[@"error"];
        if ([err isEqualToString:@"authorization_pending"] || [err isEqualToString:@"slow_down"]) {
            return;
        } else {
            [timer invalidate];
            NSString *desc = json[@"error_description"] ?: @"Giriş tamamlanamadı.";
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

- (void)fetchUserEmail:(NSString *)token {
    NSURL *url = [NSURL URLWithString:@"https://www.googleapis.com/oauth2/v2/userinfo"];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];

    [[self.session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *res, NSError *err) {
        if (data) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (json[@"email"]) {
                [[NSUserDefaults standardUserDefaults] setObject:json[@"email"] forKey:kGeminiOAuthEmailKey];
                [[NSUserDefaults standardUserDefaults] synchronize];
            }
        }
    }] resume];
}

- (void)fetchAvailableModelsWithCompletion:(GeminiModelsHandler)completion {
    [self synchronizeSettings];
    if (![self isAuthenticated]) {
        if (completion) {
            NSError *err = [NSError errorWithDomain:@"GeminiClient" code:401 userInfo:@{NSLocalizedDescriptionKey: @"Lütfen önce API Key girin veya Google hesabınızı bağlayın."}];
            completion(nil, err);
        }
        return;
    }

    NSString *urlString;
    if (self.isGoogleAccountLinked) {
        urlString = @"https://generativelanguage.googleapis.com/v1beta/models";
    } else {
        urlString = [NSString stringWithFormat:@"https://generativelanguage.googleapis.com/v1beta/models?key=%@", self.apiKey];
    }

    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"GET"];

    if (self.isGoogleAccountLinked) {
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

        [[NSUserDefaults standardUserDefaults] setObject:supported forKey:kGeminiCachedModelsKey];
        [[NSUserDefaults standardUserDefaults] synchronize];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(supported, nil);
        });
    }];
    [task resume];
}

- (NSString *)customRequestPayloadTemplate {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kCustomPayloadTemplateKey];
}

- (void)sendMessage:(NSString *)prompt 
            history:(NSArray *)historyMessages 
         completion:(GeminiCompletionHandler)completion {
    [self synchronizeSettings];
    if (![self isAuthenticated]) {
        if (completion) {
            NSError *err = [NSError errorWithDomain:@"GeminiClient" 
                                               code:401 
                                           userInfo:@{NSLocalizedDescriptionKey: @"Lütfen Ayarlar'dan API Key girin veya Google Hesabınızı bağlayın."}];
            completion(nil, err);
        }
        return;
    }

    NSString *model = self.selectedModel;
    if ([model hasPrefix:@"models/"]) {
        model = [model substringFromIndex:7];
    }

    NSString *customBaseUrl = [[NSUserDefaults standardUserDefaults] stringForKey:kCustomEndpointKey];
    NSString *baseUrl = (customBaseUrl && customBaseUrl.length > 5) ? customBaseUrl : @"https://generativelanguage.googleapis.com/v1beta";

    NSString *urlString;
    if (self.isGoogleAccountLinked) {
        urlString = [NSString stringWithFormat:@"%@/models/%@:generateContent", baseUrl, model];
    } else {
        urlString = [NSString stringWithFormat:@"%@/models/%@:generateContent?key=%@", baseUrl, model, self.apiKey];
    }

    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];

    if (self.isGoogleAccountLinked) {
        [request setValue:[NSString stringWithFormat:@"Bearer %@", self.oauthAccessToken] forHTTPHeaderField:@"Authorization"];
    }

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
