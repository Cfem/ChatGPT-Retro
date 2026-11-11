#import "GeminiClient.h"
#import "ChatMessage.h"

static NSString *const kGeminiApiKeyDefaultsKey = @"GeminiClientApiKey";
static NSString *const kGeminiModelDefaultsKey = @"GeminiClientModel";
static NSString *const kGeminiCachedModelsKey = @"GeminiClientCachedModels";
static NSString *const kCustomPayloadTemplateKey = @"custom_request_payload";
static NSString *const kCustomEndpointKey = @"custom_api_endpoint";
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
        _cachedModels = [defaults arrayForKey:kGeminiCachedModelsKey] ?: @[];
        
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 45.0;
        config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        _session = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
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

- (BOOL)hasApiKey {
    return (self.apiKey && self.apiKey.length > 5);
}

- (NSString *)customRequestPayloadTemplate {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kCustomPayloadTemplateKey];
}

- (void)fetchAvailableModelsWithCompletion:(GeminiModelsHandler)completion {
    if (![self hasApiKey]) {
        if (completion) {
            NSError *err = [NSError errorWithDomain:@"GeminiClient" 
                                               code:401 
                                           userInfo:@{NSLocalizedDescriptionKey: @"API Key girilmedi."}];
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

        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
        if (httpResp.statusCode != 200) {
            NSString *errMsg = [NSString stringWithFormat:@"HTTP %ld: Modeller alınamadı", (long)httpResp.statusCode];
            if (data.length > 0) {
                NSDictionary *errJson = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                if (errJson[@"error"][@"message"]) {
                    errMsg = errJson[@"error"][@"message"];
                }
            }
            NSError *apiErr = [NSError errorWithDomain:@"GeminiClient" code:httpResp.statusCode userInfo:@{NSLocalizedDescriptionKey: errMsg}];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, apiErr);
            });
            return;
        }

        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSArray *rawModels = json[@"models"];
        NSMutableArray *supported = [NSMutableArray array];

        for (NSDictionary *m in rawModels) {
            NSArray *methods = m[@"supportedGenerationMethods"];
            if ([methods containsObject:@"generateContent"]) {
                NSString *name = m[@"name"]; // Örn: "models/gemini-1.5-flash"
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
    if (![self hasApiKey]) {
        if (completion) {
            NSError *err = [NSError errorWithDomain:@"GeminiClient" 
                                               code:401 
                                           userInfo:@{NSLocalizedDescriptionKey: @"API Key girilmedi. Lütfen Ayarlar'dan Google AI Studio API anahtarınızı girin."}];
            completion(nil, err);
        }
        return;
    }

    NSString *model = self.selectedModel.length > 0 ? self.selectedModel : kDefaultModel;
    if ([model hasPrefix:@"models/"]) {
        model = [model substringFromIndex:7];
    }

    // iOS Settings uygulamasından özel endpoint tanımlanmış mı?
    NSString *customBaseUrl = [[NSUserDefaults standardUserDefaults] stringForKey:kCustomEndpointKey];
    NSString *urlString;
    if (customBaseUrl && customBaseUrl.length > 5) {
        urlString = [NSString stringWithFormat:@"%@/models/%@:generateContent?key=%@", customBaseUrl, model, self.apiKey];
    } else {
        urlString = [NSString stringWithFormat:@"https://generativelanguage.googleapis.com/v1beta/models/%@:generateContent?key=%@", model, self.apiKey];
    }
    
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        if (completion) {
            NSError *err = [NSError errorWithDomain:@"GeminiClient" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Geçersiz API URL'i."}];
            completion(nil, err);
        }
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];

    // 512 MB RAM Koruması: Sadece son 8 mesajı gönder
    NSMutableArray *contents = [NSMutableArray array];
    NSInteger startIndex = 0;
    if (historyMessages.count > 8) {
        startIndex = historyMessages.count - 8;
    }

    for (NSInteger i = startIndex; i < historyMessages.count; i++) {
        ChatMessage *msg = historyMessages[i];
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

    NSDictionary *payloadDict = @{
        @"contents": contents,
        @"generationConfig": @{
            @"temperature": @0.7,
            @"maxOutputTokens": @2048
        }
    };

    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:payloadDict options:0 error:nil];
    
    // Son yapılan ham isteği Settings.bundle'da gösterilmek üzere NSUserDefaults'a yaz
    NSString *rawJsonString = [[NSString alloc] initWithData:bodyData encoding:NSUTF8StringEncoding];
    [[NSUserDefaults standardUserDefaults] setObject:rawJsonString forKey:@"last_raw_request"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    // Eğer kullanıcı iOS Ayarlar uygulamasından özel bir şablon girdiyse onu kullan
    NSString *customPayload = [self customRequestPayloadTemplate];
    if (customPayload && customPayload.length > 10) {
        // {PROMPT} placeholder'ı varsa kullanıcının mesajını içine yerleştir
        NSString *filled = [customPayload stringByReplacingOccurrencesOfString:@"{PROMPT}" withString:prompt];
        NSData *customData = [filled dataUsingEncoding:NSUTF8StringEncoding];
        if (customData) {
            bodyData = customData;
        }
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
                if (errJson[@"error"][@"message"]) {
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
        NSString *replyText = @"";
        NSArray *candidates = json[@"candidates"];
        if (candidates.count > 0) {
            NSDictionary *cand = candidates[0];
            NSArray *parts = cand[@"content"][@"parts"];
            if (parts.count > 0) {
                replyText = parts[0][@"text"] ?: @"";
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(replyText, nil);
        });
    }];
    [task resume];
}

@end
