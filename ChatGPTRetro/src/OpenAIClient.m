#import "OpenAIClient.h"
#import "ChatMessage.h"
#import <Security/Security.h>

static NSString *const kOpenAIApiKeyDefaultsKey = @"OpenAIClientApiKey";
static NSString *const kOpenAIModelDefaultsKey = @"OpenAIClientModel";
static NSString *const kOpenAICachedModelsKey = @"OpenAIClientCachedModels";
static NSString *const kDefaultModel = @"gpt-4o-mini";

@interface OpenAIClient () <NSURLSessionDelegate>
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation OpenAIClient

+ (instancetype)sharedClient {
    static OpenAIClient *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[OpenAIClient alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        _apiKey = [defaults stringForKey:kOpenAIApiKeyDefaultsKey] ?: @"";
        _selectedModel = [defaults stringForKey:kOpenAIModelDefaultsKey] ?: kDefaultModel;

        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 60.0;
        config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        
        // iOS 8.4 Legacy SSL/TLS handshake uyumluluğu için delegate kullanımı
        _session = [NSURLSession sessionWithConfiguration:config 
                                                 delegate:self 
                                            delegateQueue:[NSOperationQueue mainQueue]];
    }
    return self;
}

#pragma mark - NSURLSessionDelegate (SSL / Server Trust Bypass for iOS 8.4)

- (void)URLSession:(NSURLSession *)session 
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge 
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler {

    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        SecTrustRef serverTrust = challenge.protectionSpace.serverTrust;
        NSString *host = challenge.protectionSpace.host;

        // OpenAI ve ilgili endpoint'ler için iOS 8'in eski kök sertifika deposundan kaynaklanan
        // SSL doğrulaması engelini aşmak üzere güveni kabul et:
        if ([host containsString:@"openai.com"]) {
            completionHandler(NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialForTrust:serverTrust]);
            return;
        }
    }
    
    completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
}

- (void)saveApiKey:(NSString *)apiKey {
    _apiKey = [apiKey stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    [[NSUserDefaults standardUserDefaults] setObject:_apiKey forKey:kOpenAIApiKeyDefaultsKey];
    [[NSUserDefaults standardUserDefaults] setObject:_apiKey forKey:@"openai_api_key"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)saveSelectedModel:(NSString *)model {
    _selectedModel = [model stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: kDefaultModel;
    [[NSUserDefaults standardUserDefaults] setObject:_selectedModel forKey:kOpenAIModelDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)isAuthenticated {
    return (self.apiKey.length > 10);
}

- (void)fetchAvailableModelsWithCompletion:(OpenAIModelsHandler)completion {
    if (![self isAuthenticated]) {
        if (completion) {
            NSError *err = [NSError errorWithDomain:@"OpenAIClient" 
                                               code:401 
                                           userInfo:@{NSLocalizedDescriptionKey: @"Lütfen önce geçerli bir OpenAI API Anahtarı (sk-...) girin."}];
            completion(nil, err);
        }
        return;
    }

    NSString *urlString = @"https://api.openai.com/v1/models";
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"GET"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", self.apiKey] forHTTPHeaderField:@"Authorization"];

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
            if (data.length > 0) {
                NSDictionary *errJson = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                if (errJson && errJson[@"error"] && errJson[@"error"][@"message"]) {
                    errMsg = errJson[@"error"][@"message"];
                }
            }
            NSError *apiErr = [NSError errorWithDomain:@"OpenAIClient" code:httpResponse.statusCode userInfo:@{NSLocalizedDescriptionKey: errMsg}];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, apiErr);
            });
            return;
        }

        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSArray *modelsData = json[@"data"];
        NSMutableArray *supported = [NSMutableArray array];

        for (NSDictionary *m in modelsData) {
            NSString *modelId = m[@"id"];
            if ([modelId hasPrefix:@"gpt-"] || [modelId hasPrefix:@"o1"] || [modelId hasPrefix:@"o3"] || [modelId hasPrefix:@"chatgpt-"]) {
                [supported addObject:modelId];
            }
        }

        [supported sortUsingSelector:@selector(compare:)];

        if (supported.count > 0) {
            [[NSUserDefaults standardUserDefaults] setObject:supported forKey:kOpenAICachedModelsKey];
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
         completion:(OpenAICompletionHandler)completion {

    if (![self isAuthenticated]) {
        if (completion) {
            NSError *err = [NSError errorWithDomain:@"OpenAIClient" 
                                               code:401 
                                           userInfo:@{NSLocalizedDescriptionKey: @"API Anahtarı bulunamadı. Lütfen Ayarlar'dan OpenAI API Anahtarınızı girin."}];
            completion(nil, err);
        }
        return;
    }

    NSString *urlString = @"https://api.openai.com/v1/chat/completions";
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", self.apiKey] forHTTPHeaderField:@"Authorization"];

    NSMutableArray *messages = [NSMutableArray array];

    // System prompt
    [messages addObject:@{
        @"role": @"system",
        @"content": @"Sen iOS 8 iPad Mini üzerinde çalışan retro ve şık ChatGPTRetro asistanısın. Türkçe, net, kibar ve yardımcı yanıtlar ver."
    }];

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
        NSString *role = (msg.sender == ChatMessageSenderUser) ? @"user" : @"assistant";
        [messages addObject:@{
            @"role": role,
            @"content": msg.text ?: @""
        }];
    }

    [messages addObject:@{
        @"role": @"user",
        @"content": prompt ?: @""
    }];

    NSString *model = (self.selectedModel.length > 0) ? self.selectedModel : kDefaultModel;
    NSMutableDictionary *payloadDict = [NSMutableDictionary dictionary];
    payloadDict[@"model"] = model;
    payloadDict[@"messages"] = messages;

    // Reasoning modelleri haricinde temperature ekleyebiliriz
    if (![model hasPrefix:@"o1"] && ![model hasPrefix:@"o3"]) {
        payloadDict[@"temperature"] = @0.7;
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
            NSError *apiErr = [NSError errorWithDomain:@"OpenAIClient" code:httpResponse.statusCode userInfo:@{NSLocalizedDescriptionKey: errMsg}];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, apiErr);
            });
            return;
        }

        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *replyText = @"";

        NSArray *choices = json[@"choices"];
        if (choices.count > 0) {
            NSDictionary *choice = choices[0];
            NSDictionary *message = choice[@"message"];
            if (message && message[@"content"]) {
                replyText = message[@"content"];
            }
        }

        if (replyText.length == 0) {
            replyText = @"(Boş yanıt döndü)";
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion([replyText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]], nil);
        });
    }];
    [task resume];
}

@end
