#import "GeminiClient.h"
#import "ChatMessage.h"

static NSString *const kGeminiApiKeyDefaultsKey = @"GeminiClientApiKey";
static NSString *const kGeminiModelDefaultsKey = @"GeminiClientModel";
static NSString *const kGeminiCachedModelsKey = @"GeminiClientCachedModels";
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
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        _apiKey = [defaults stringForKey:kGeminiApiKeyDefaultsKey] ?: @"";
        _selectedModel = [defaults stringForKey:kGeminiModelDefaultsKey] ?: kDefaultModel;

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

- (void)saveApiKey:(NSString *)apiKey {
    _apiKey = [apiKey stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    [[NSUserDefaults standardUserDefaults] setObject:_apiKey forKey:kGeminiApiKeyDefaultsKey];
    [[NSUserDefaults standardUserDefaults] setObject:_apiKey forKey:@"gemini_api_key"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)saveSelectedModel:(NSString *)model {
    _selectedModel = [model stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: kDefaultModel;
    [[NSUserDefaults standardUserDefaults] setObject:_selectedModel forKey:kGeminiModelDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)isAuthenticated {
    return (self.apiKey.length > 5);
}

- (void)fetchAvailableModelsWithCompletion:(GeminiModelsHandler)completion {
    if (![self isAuthenticated]) {
        if (completion) {
            NSError *err = [NSError errorWithDomain:@"GeminiClient" code:401 userInfo:@{NSLocalizedDescriptionKey: @"Lütfen önce geçerli bir Gemini API Anahtarı girin."}];
            completion(nil, err);
        }
        return;
    }

    NSString *urlString = [NSString stringWithFormat:@"https://generativelanguage.googleapis.com/v1beta/models?key=%@", self.apiKey];
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"GET"];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, error);
            });
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            NSString *errMsg = [NSString stringWithFormat:@"HTTP %ld: API Anahtarınızı kontrol edin.", (long)httpResponse.statusCode];
            NSError *apiErr = [NSError errorWithDomain:@"GeminiClient" code:httpResponse.statusCode userInfo:@{NSLocalizedDescriptionKey: errMsg}];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, apiErr);
            });
            return;
        }

        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSArray *modelsData = json[@"models"];
        NSMutableArray *supported = [NSMutableArray array];

        for (NSDictionary *m in modelsData) {
            NSString *name = m[@"name"];
            NSArray *methods = m[@"supportedGenerationMethods"];
            if ([methods containsObject:@"generateContent"] && [name hasPrefix:@"models/gemini"]) {
                NSString *shortName = [name substringFromIndex:7];
                [supported addObject:shortName];
            }
        }

        if (supported.count > 0) {
            [[NSUserDefaults standardUserDefaults] setObject:supported forKey:kGeminiCachedModelsKey];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }

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
                                           userInfo:@{NSLocalizedDescriptionKey: @"Lütfen sağ üstteki 'Ayarlar' butonuna dokunarak Gemini API Anahtarınızı girin veya QR kod ile okutun."}];
            completion(nil, err);
        }
        return;
    }

    NSString *model = self.selectedModel;
    if ([model hasPrefix:@"models/"]) {
        model = [model substringFromIndex:7];
    }

    NSString *urlString = [NSString stringWithFormat:@"https://generativelanguage.googleapis.com/v1beta/models/%@:generateContent?key=%@", model, self.apiKey];
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];

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

        if (fullText.length == 0) {
            [fullText appendString:@"(Boş yanıt döndü)"];
        }

        if (sourcesList.count > 0) {
            [fullText appendString:@"\n\n🌐 Kaynaklar:\n"];
            for (NSString *src in sourcesList) {
                [fullText appendFormat:@"%@\n", src];
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion([fullText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]], nil);
        });
    }];
    [task resume];
}

@end
