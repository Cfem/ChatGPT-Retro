#import "GeminiClient.h"
#import "ChatMessage.h"

static NSString *const kGeminiApiKeyDefaultsKey = @"GeminiClientApiKey";
static NSString *const kGeminiModelDefaultsKey = @"GeminiClientModel";
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
        
        // RAM tasarrufu için minimal ephemeral/default konfigürasyon
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

- (void)sendMessage:(NSString *)prompt 
            history:(NSArray *)historyMessages 
         completion:(GeminiCompletionHandler)completion {
    if (![self hasApiKey]) {
        if (completion) {
            NSError *err = [NSError errorWithDomain:@"GeminiClient" 
                                               code:401 
                                           userInfo:@{NSLocalizedDescriptionKey: @"API Key girilmedi. Lütfen Ayarlar ikonuna basıp Google AI Studio API anahtarınızı girin."}];
            completion(nil, err);
        }
        return;
    }

    NSString *model = self.selectedModel.length > 0 ? self.selectedModel : kDefaultModel;
    NSString *urlString = [NSString stringWithFormat:@"https://generativelanguage.googleapis.com/v1beta/models/%@:generateContent?key=%@",
                           model, self.apiKey];
    
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        if (completion) {
            NSError *err = [NSError errorWithDomain:@"GeminiClient" 
                                               code:400 
                                           userInfo:@{NSLocalizedDescriptionKey: @"Geçersiz API URL'i oluşturuldu."}];
            completion(nil, err);
        }
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];

    // 512 MB RAM koruması: Sadece son 8-10 mesajı bağlam olarak gönder (Memory & Token koruması)
    NSMutableArray *contents = [NSMutableArray array];
    NSInteger startIndex = 0;
    if (historyMessages.count > 10) {
        startIndex = historyMessages.count - 10;
    }

    for (NSInteger i = startIndex; i < historyMessages.count; i++) {
        ChatMessage *msg = historyMessages[i];
        NSString *role = (msg.sender == ChatMessageSenderUser) ? @"user" : @"model";
        NSDictionary *contentObj = @{
            @"role": role,
            @"parts": @[
                @{ @"text": msg.text ?: @"" }
            ]
        };
        [contents addObject:contentObj];
    }

    // Kullanıcının en son yazdığı mesaj
    [contents addObject:@{
        @"role": @"user",
        @"parts": @[
            @{ @"text": prompt ?: @"" }
        ]
    }];

    NSDictionary *payload = @{
        @"contents": contents,
        @"generationConfig": @{
            @"temperature": @0.7,
            @"maxOutputTokens": @2048
        }
    };

    NSError *jsonError = nil;
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&jsonError];
    if (jsonError || !bodyData) {
        if (completion) {
            completion(nil, jsonError);
        }
        return;
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
            NSError *apiErr = [NSError errorWithDomain:@"GeminiClient" 
                                                  code:httpResponse.statusCode 
                                              userInfo:@{NSLocalizedDescriptionKey: errMsg}];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, apiErr);
            });
            return;
        }

        NSError *parseError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
        if (parseError || !json) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, parseError);
            });
            return;
        }

        NSString *replyText = @"";
        NSArray *candidates = json[@"candidates"];
        if (candidates.count > 0) {
            NSDictionary *candidate = candidates[0];
            NSDictionary *content = candidate[@"content"];
            NSArray *parts = content[@"parts"];
            if (parts.count > 0) {
                replyText = parts[0][@"text"] ?: @"";
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(replyText, nil);
            }
        });
    }];

    [task resume];
}

@end
