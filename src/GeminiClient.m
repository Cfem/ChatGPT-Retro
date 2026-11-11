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
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        _apiKey = [defaults stringForKey:kGeminiApiKeyDefaultsKey] ?: @"";
        _selectedModel = [defaults stringForKey:kGeminiModelDefaultsKey] ?: kDefaultModel;
        _oauthClientId = [defaults stringForKey:kGeminiOAuthClientIdKey] ?: @"";
        _oauthClientSecret = [defaults stringForKey:kGeminiOAuthClientSecretKey] ?: @"";
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

- (void)saveOAuthClientId:(NSString *)clientId secret:(NSString *)secret {
    _oauthClientId = [clientId stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    _oauthClientSecret = [secret stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    
    [[NSUserDefaults standardUserDefaults] setObject:_oauthClientId forKey:kGeminiOAuthClientIdKey];
    [[NSUserDefaults standardUserDefaults] setObject:_oauthClientSecret forKey:kGeminiOAuthClientSecretKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)saveApiKey:(NSString *)apiKey {
    _apiKey = [apiKey stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    [[NSUserDefaults standardUserDefaults] setObject:_apiKey forKey:kGeminiApiKeyDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)saveSelectedModel:(NSString *)model {
    _selectedModel = [model stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: kDefaultModel;
    [[NSUserDefaults standardUserDefaults] setObject:_selectedModel forKey:kGeminiModelDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
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

#pragma mark - Standard OAuth 2.0 (Gemini Scope & QR / OOB Flow)

- (NSString *)standardRedirectUri {
    NSString *cid = [self.oauthClientId stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (cid.length == 0) return @"http://localhost";

    // Eğer iOS Client ID ise (.apps.googleusercontent.com) ters çevrilmiş bundle şeması oluştur
    if ([cid containsString:@".apps.googleusercontent.com"]) {
        NSArray *parts = [cid componentsSeparatedByString:@"."];
        NSArray *reversed = [[parts reverseObjectEnumerator] allObjects];
        NSString *rev = [reversed componentsJoinedByString:@"."];
        return [NSString stringWithFormat:@"%@:/oauth2redirect", rev];
    }
    return @"http://localhost";
}

- (NSString *)standardOAuthAuthorizationURL {
    NSString *cid = [self.oauthClientId stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (cid.length == 0) return @"";

    // Scope: Sadece Gemini modelleri ve OpenID profil bilgisi
    NSString *scope = @"https://www.googleapis.com/auth/generative-language openid email profile";
    NSString *encodedScope = [scope stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];

    NSString *redirectUri = [self standardRedirectUri];
    NSString *encodedRedirect = [redirectUri stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];

    return [NSString stringWithFormat:@"https://accounts.google.com/o/oauth2/v2/auth?client_id=%@&redirect_uri=%@&response_type=code&scope=%@&prompt=consent&access_type=offline",
            cid, encodedRedirect, encodedScope];
}

- (void)exchangeAuthCode:(NSString *)rawInput completion:(GeminiExchangeCodeHandler)completion {
    if (!rawInput || rawInput.length == 0) {
        if (completion) {
            NSError *err = [NSError errorWithDomain:@"GeminiOAuth" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Doğrulama kodu boş olamaz."}];
            completion(NO, err);
        }
        return;
    }

    NSString *code = [rawInput stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    // Eğer kullanıcı veya kamera URL'nin tamamını verdiyse içindeki code= kısmını ayıkla
    if ([code containsString:@"code="]) {
        NSRange range = [code rangeOfString:@"code="];
        NSString *sub = [code substringFromIndex:range.location + range.length];
        NSRange ampRange = [sub rangeOfString:@"&"];
        if (ampRange.location != NSNotFound) {
            code = [sub substringToIndex:ampRange.location];
        } else {
            code = sub;
        }
    }
    code = [code stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];

    NSURL *tokenUrl = [NSURL URLWithString:@"https://oauth2.googleapis.com/token"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:tokenUrl];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];

    NSString *redirectUri = [self standardRedirectUri];
    NSString *bodyStr;
    if (self.oauthClientSecret.length > 0) {
        bodyStr = [NSString stringWithFormat:@"client_id=%@&client_secret=%@&code=%@&grant_type=authorization_code&redirect_uri=%@",
                   self.oauthClientId, self.oauthClientSecret, [code stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding], [redirectUri stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    } else {
        bodyStr = [NSString stringWithFormat:@"client_id=%@&code=%@&grant_type=authorization_code&redirect_uri=%@",
                   self.oauthClientId, [code stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding], [redirectUri stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    }
    [request setHTTPBody:[bodyStr dataUsingEncoding:NSUTF8StringEncoding]];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, error);
            });
            return;
        }

        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *accessToken = json[@"access_token"];
        NSString *refreshToken = json[@"refresh_token"];

        if (accessToken && accessToken.length > 0) {
            self.oauthAccessToken = accessToken;
            [[NSUserDefaults standardUserDefaults] setObject:accessToken forKey:kGeminiOAuthAccessTokenKey];
            if (refreshToken && refreshToken.length > 0) {
                self.oauthRefreshToken = refreshToken;
                [[NSUserDefaults standardUserDefaults] setObject:refreshToken forKey:kGeminiOAuthRefreshTokenKey];
            }
            [[NSUserDefaults standardUserDefaults] synchronize];

            [self fetchUserEmail:accessToken];

            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(YES, nil);
            });
            return;
        }

        NSString *desc = json[@"error_description"] ?: json[@"error"] ?: @"Doğrulama kodu Google tarafından onaylanamadı. Kodun süresi dolmuş veya hatalı olabilir.";
        NSError *failErr = [NSError errorWithDomain:@"GeminiOAuth" code:400 userInfo:@{NSLocalizedDescriptionKey: desc}];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(NO, failErr);
        });
    }];
    [task resume];
}

- (void)refreshAccessTokenIfNeededWithCompletion:(void (^)(BOOL refreshed))completion {
    if (self.oauthRefreshToken.length == 0 || self.oauthClientId.length == 0) {
        if (completion) completion(NO);
        return;
    }

    NSURL *tokenUrl = [NSURL URLWithString:@"https://oauth2.googleapis.com/token"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:tokenUrl];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];

    NSString *bodyStr;
    if (self.oauthClientSecret.length > 0) {
        bodyStr = [NSString stringWithFormat:@"client_id=%@&client_secret=%@&refresh_token=%@&grant_type=refresh_token",
                   self.oauthClientId, self.oauthClientSecret, self.oauthRefreshToken];
    } else {
        bodyStr = [NSString stringWithFormat:@"client_id=%@&refresh_token=%@&grant_type=refresh_token",
                   self.oauthClientId, self.oauthRefreshToken];
    }
    [request setHTTPBody:[bodyStr dataUsingEncoding:NSUTF8StringEncoding]];

    [[self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!data) {
            if (completion) completion(NO);
            return;
        }

        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *newAccessToken = json[@"access_token"];
        if (newAccessToken && newAccessToken.length > 0) {
            self.oauthAccessToken = newAccessToken;
            [[NSUserDefaults standardUserDefaults] setObject:newAccessToken forKey:kGeminiOAuthAccessTokenKey];
            [[NSUserDefaults standardUserDefaults] synchronize];
            if (completion) completion(YES);
        } else {
            if (completion) completion(NO);
        }
    }] resume];
}

#pragma mark - OAuth Device Flow

- (void)startDeviceAuthFlowWithCompletion:(GeminiDeviceAuthHandler)completion {
    if (![self hasOAuthCredentials]) {
        if (completion) {
            NSError *err = [NSError errorWithDomain:@"GeminiOAuth" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Lütfen önce Client ID ve Client Secret alanlarını doldurup 'Ayarları Kaydet' butonuna basın."}];
            completion(nil, nil, nil, err);
        }
        return;
    }

    NSURL *url = [NSURL URLWithString:@"https://oauth2.googleapis.com/device/code"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];

    NSString *scope = @"https://www.googleapis.com/auth/cloud-platform email profile";
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
            NSString *errMsg = json[@"error_description"] ?: @"Google Device Flow başlatılamadı. Client ID'nin doğru ve 'TVs and Limited Input devices' türünde olduğunu kontrol edin.";
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
            self.oauthAccessToken = accessToken;
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
                self.userEmail = json[@"email"];
                [[NSUserDefaults standardUserDefaults] setObject:json[@"email"] forKey:kGeminiOAuthEmailKey];
                [[NSUserDefaults standardUserDefaults] synchronize];
            }
        }
    }] resume];
}

- (void)fetchAvailableModelsWithCompletion:(GeminiModelsHandler)completion {
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

- (void)sendMessage:(NSString *)prompt 
            history:(NSArray *)historyMessages 
         completion:(GeminiCompletionHandler)completion {
    if (![self isAuthenticated]) {
        if (completion) {
            NSError *err = [NSError errorWithDomain:@"GeminiClient" 
                                               code:401 
                                           userInfo:@{NSLocalizedDescriptionKey: @"Lütfen sağ üstteki 'Ayarlar'dan Google Hesabınızı bağlayın veya API Key girin."}];
            completion(nil, err);
        }
        return;
    }

    NSString *model = self.selectedModel;
    if ([model hasPrefix:@"models/"]) {
        model = [model substringFromIndex:7];
    }

    NSString *baseUrl = @"https://generativelanguage.googleapis.com/v1beta";
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
    [request setHTTPBody:bodyData];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, error);
            });
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode == 401 && self.oauthRefreshToken.length > 0) {
            // Token süresi dolmuş, refresh_token ile arka planda sessizce yenile ve mesajı tekrar dene
            [self refreshAccessTokenIfNeededWithCompletion:^(BOOL refreshed) {
                if (refreshed) {
                    [self sendMessage:prompt history:historyMessages completion:completion];
                } else {
                    NSError *apiErr = [NSError errorWithDomain:@"GeminiClient" code:401 userInfo:@{NSLocalizedDescriptionKey: @"Google oturum süresi doldu. Lütfen Ayarlar'dan tekrar giriş yapın."}];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (completion) completion(nil, apiErr);
                    });
                }
            }];
            return;
        }

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
