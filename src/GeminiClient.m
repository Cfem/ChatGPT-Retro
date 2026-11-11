#import "GeminiClient.h"
#import "ChatMessage.h"

static NSString *const kGeminiApiKeyDefaultsKey = @"GeminiClientApiKey";
static NSString *const kGeminiModelDefaultsKey = @"GeminiClientModel";
static NSString *const kGeminiCachedModelsKey = @"GeminiClientCachedModels";
static NSString *const kCustomPayloadTemplateKey = @"custom_request_payload";
static NSString *const kCustomEndpointKey = @"custom_api_endpoint";
static NSString *const kDefaultModel = @"gemini-1.5-flash";

@interface GeminiClient () <NSURLSessionDataDelegate>
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, copy) GeminiStreamChunkHandler currentChunkHandler;
@property (nonatomic, strong) NSMutableString *streamBuffer;
@property (nonatomic, strong) NSMutableString *accumulatedText;
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
        _streamBuffer = [NSMutableString string];
        _accumulatedText = [NSMutableString string];

        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 60.0;
        config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        _session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:[NSOperationQueue mainQueue]];
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
            NSError *err = [NSError errorWithDomain:@"GeminiClient" code:401 userInfo:@{NSLocalizedDescriptionKey: @"API Key girilmedi."}];
            completion(nil, err);
        }
        return;
    }

    NSString *urlString = [NSString stringWithFormat:@"https://generativelanguage.googleapis.com/v1beta/models?key=%@", self.apiKey];
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"GET"];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
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

- (void)streamMessage:(NSString *)prompt 
              history:(NSArray *)historyMessages 
         chunkHandler:(GeminiStreamChunkHandler)chunkHandler {
    if (![self hasApiKey]) {
        if (chunkHandler) {
            NSError *err = [NSError errorWithDomain:@"GeminiClient" 
                                               code:401 
                                           userInfo:@{NSLocalizedDescriptionKey: @"API Key girilmedi."}];
            chunkHandler(nil, nil, YES, err);
        }
        return;
    }

    self.currentChunkHandler = chunkHandler;
    [self.streamBuffer setString:@""];
    [self.accumulatedText setString:@""];

    NSString *model = self.selectedModel.length > 0 ? self.selectedModel : kDefaultModel;
    if ([model hasPrefix:@"models/"]) {
        model = [model substringFromIndex:7];
    }

    NSString *customBaseUrl = [[NSUserDefaults standardUserDefaults] stringForKey:kCustomEndpointKey];
    NSString *urlString;
    if (customBaseUrl && customBaseUrl.length > 5) {
        urlString = [NSString stringWithFormat:@"%@/models/%@:streamGenerateContent?alt=sse&key=%@", customBaseUrl, model, self.apiKey];
    } else {
        urlString = [NSString stringWithFormat:@"https://generativelanguage.googleapis.com/v1beta/models/%@:streamGenerateContent?alt=sse&key=%@", model, self.apiKey];
    }

    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];

    // Son konuşma geçmişini derle (RAM korumalı)
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
            @"maxOutputTokens": @4096
        }
    };

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

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request];
    [task resume];
}

#pragma mark - NSURLSessionDataDelegate (SSE Stream Parser)

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
    if (http.statusCode != 200) {
        // Hata durumunda da akışı bitir
    }
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text) return;

    [self.streamBuffer appendString:text];

    // SSE Satırlarını ayrıştır ("data: { ... }")
    while (YES) {
        NSRange newlineRange = [self.streamBuffer rangeOfString:@"\n"];
        if (newlineRange.location == NSNotFound) {
            break;
        }

        NSString *line = [self.streamBuffer substringToIndex:newlineRange.location];
        [self.streamBuffer deleteCharactersInRange:NSMakeRange(0, newlineRange.location + 1)];

        line = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([line hasPrefix:@"data: "]) {
            NSString *jsonString = [line substringFromIndex:6];
            NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
            if (!jsonData) continue;

            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
            if (!json) continue;

            NSArray *candidates = json[@"candidates"];
            if (candidates.count > 0) {
                NSDictionary *candidate = candidates[0];
                NSArray *parts = candidate[@"content"][@"parts"];
                
                // TÜM PART'LARI EKSİKSİZ BİRLEŞTİR (1. 2. 3. blokları asla kaçırma)
                NSMutableString *chunkText = [NSMutableString string];
                for (NSDictionary *p in parts) {
                    if (p[@"text"]) {
                        [chunkText appendString:p[@"text"]];
                    }
                }

                if (chunkText.length > 0) {
                    [self.accumulatedText appendString:chunkText];
                    if (self.currentChunkHandler) {
                        self.currentChunkHandler(chunkText, [self.accumulatedText copy], NO, nil);
                    }
                }
            }
        }
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (self.currentChunkHandler) {
        self.currentChunkHandler(@"", [self.accumulatedText copy], YES, error);
        self.currentChunkHandler = nil;
    }
}

@end
