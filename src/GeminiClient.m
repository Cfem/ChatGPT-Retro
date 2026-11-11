#import "GeminiClient.h"
#import "ChatMessage.h"

static NSString *const kGeminiApiKeyDefaultsKey = @"GeminiClientApiKey";
static NSString *const kGeminiModelDefaultsKey = @"GeminiClientModel";
static NSString *const kGeminiOAuthClientIdKey = @"google_oauth_client_id";
static NSString *const kGeminiOAuthClientSecretKey = @"google_oauth_client_secret";
static NSString *const kGeminiOAuthAccessTokenKey = @"GeminiOAuthAccessToken";
static NSString *const kGeminiOAuthRefreshTokenKey = @"GeminiOAuthRefreshToken";
static NSString *const kCustomPayloadTemplateKey = @"custom_request_payload";
static NSString *const kCustomEndpointKey = @"custom_api_endpoint";
static NSString *const kGoogleSearchEnabledKey = @"enable_google_search";
static NSString *const kDefaultModel = @"gemini-1.5-flash";

@interface GeminiClient ()
@property (nonatomic, strong) NSURLSession *session;
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
    }
    return self;
}

- (NSString *)apiKey {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kGeminiApiKeyDefaultsKey] ?: @"";
}

- (NSString *)selectedModel {
    NSString *m = [[NSUserDefaults standardUserDefaults] stringForKey:kGeminiModelDefaultsKey];
    return (m && m.length > 0) ? m : kDefaultModel;
}

- (NSString *)oauthAccessToken {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kGeminiOAuthAccessTokenKey] ?: @"";
}

- (BOOL)isAuthenticated {
    if (self.apiKey.length > 5) return YES;
    if (self.oauthAccessToken.length > 10) return YES;
    return NO;
}

- (NSString *)customRequestPayloadTemplate {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kCustomPayloadTemplateKey];
}

- (void)sendMessage:(NSString *)prompt 
            history:(NSArray *)historyMessages 
         completion:(GeminiCompletionHandler)completion {
    if (![self isAuthenticated]) {
        if (completion) {
            NSError *err = [NSError errorWithDomain:@"GeminiClient" 
                                               code:401 
                                           userInfo:@{NSLocalizedDescriptionKey: @"Lütfen iPad'inizin Ayarlar uygulamasını açıp 'Gemini' sayfasından API anahtarınızı girin."}];
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
    if (self.apiKey.length > 5) {
        urlString = [NSString stringWithFormat:@"%@/models/%@:generateContent?key=%@", baseUrl, model, self.apiKey];
    } else {
        urlString = [NSString stringWithFormat:@"%@/models/%@:generateContent", baseUrl, model];
    }

    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];

    if (self.apiKey.length <= 5 && self.oauthAccessToken.length > 0) {
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
