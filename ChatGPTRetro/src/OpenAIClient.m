#import "OpenAIClient.h"
#import "ChatMessage.h"
#include <curl/curl.h>

static NSString *const kOpenAIApiKeyDefaultsKey = @"OpenAIClientApiKey";
static NSString *const kOpenAIModelDefaultsKey = @"OpenAIClientModel";
static NSString *const kOpenAICachedModelsKey = @"OpenAIClientCachedModels";
static NSString *const kDefaultModel = @"gpt-4o-mini";

struct CurlMemoryStruct {
    char *memory;
    size_t size;
};

static size_t CurlWriteCallback(void *contents, size_t size, size_t nmemb, void *userp) {
    size_t realsize = size * nmemb;
    struct CurlMemoryStruct *mem = (struct CurlMemoryStruct *)userp;
    char *ptr = realloc(mem->memory, mem->size + realsize + 1);
    if (!ptr) return 0;
    mem->memory = ptr;
    memcpy(&(mem->memory[mem->size]), contents, realsize);
    mem->size += realsize;
    mem->memory[mem->size] = 0;
    return realsize;
}

@implementation OpenAIClient

+ (void)initialize {
    if (self == [OpenAIClient class]) {
        curl_global_init(CURL_GLOBAL_ALL);
    }
}

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
    }
    return self;
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

#pragma mark - Model Classification Helpers

- (BOOL)isModernOrReasoningModel:(NSString *)model {
    NSString *m = [model lowercaseString];
    if ([m hasPrefix:@"o1"] || [m hasPrefix:@"o3"] || [m hasPrefix:@"o4"]) return YES;
    if ([m containsString:@"luna"] || [m containsString:@"sol"] || [m containsString:@"terra"]) return YES;
    if ([m hasPrefix:@"gpt-5"] || [m hasPrefix:@"gpt-6"]) return YES;
    return NO;
}

#pragma mark - cURL Request Engine

- (void)performCurlRequestToURL:(NSString *)urlString 
                         method:(NSString *)method 
                        headers:(NSDictionary *)headers 
                       jsonBody:(NSData *)bodyData 
                     completion:(void (^)(NSData *data, NSInteger statusCode, NSError *error))completion {

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        CURL *curl = curl_easy_init();
        if (!curl) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    NSError *err = [NSError errorWithDomain:@"OpenAIClient" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"cURL başlatılamadı."}];
                    completion(nil, 0, err);
                }
            });
            return;
        }

        struct CurlMemoryStruct chunk;
        chunk.memory = malloc(1);
        chunk.size = 0;

        struct curl_slist *headerList = NULL;
        for (NSString *key in headers) {
            NSString *val = headers[key];
            NSString *combined = [NSString stringWithFormat:@"%@: %@", key, val];
            headerList = curl_slist_append(headerList, [combined UTF8String]);
        }

        curl_easy_setopt(curl, CURLOPT_URL, [urlString UTF8String]);
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headerList);
        curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, CurlWriteCallback);
        curl_easy_setopt(curl, CURLOPT_WRITEDATA, (void *)&chunk);
        curl_easy_setopt(curl, CURLOPT_TIMEOUT, 60L);
        curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 20L);
        curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
        curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);

        // iOS 8.4 SSL/TLS el sıkışması uyumluluğu
        curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0L);
        curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 0L);

        if ([method isEqualToString:@"POST"]) {
            curl_easy_setopt(curl, CURLOPT_POST, 1L);
            if (bodyData && bodyData.length > 0) {
                curl_easy_setopt(curl, CURLOPT_POSTFIELDS, [bodyData bytes]);
                curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, (long)[bodyData length]);
            }
        } else {
            curl_easy_setopt(curl, CURLOPT_HTTPGET, 1L);
        }

        CURLcode res = curl_easy_perform(curl);
        long httpCode = 0;
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &httpCode);

        NSData *responseData = nil;
        NSError *reqError = nil;

        if (res == CURLE_OK) {
            if (chunk.memory && chunk.size > 0) {
                responseData = [NSData dataWithBytes:chunk.memory length:chunk.size];
            }
        } else {
            const char *errStr = curl_easy_strerror(res);
            NSString *errDesc = [NSString stringWithUTF8String:errStr] ?: @"Bilinmeyen ağ hatası";
            reqError = [NSError errorWithDomain:@"OpenAIClient" code:res userInfo:@{NSLocalizedDescriptionKey: errDesc}];
        }

        if (chunk.memory) {
            free(chunk.memory);
        }
        curl_slist_free_all(headerList);
        curl_easy_cleanup(curl);

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(responseData, httpCode, reqError);
            }
        });
    });
}

#pragma mark - Public Methods

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
    NSDictionary *headers = @{
        @"Authorization": [NSString stringWithFormat:@"Bearer %@", self.apiKey]
    };

    [self performCurlRequestToURL:urlString 
                           method:@"GET" 
                          headers:headers 
                         jsonBody:nil 
                       completion:^(NSData *data, NSInteger statusCode, NSError *error) {
        
        if (error) {
            if (completion) completion(nil, error);
            return;
        }

        if (statusCode != 200) {
            NSString *errMsg = [NSString stringWithFormat:@"HTTP %ld: API Anahtarınızı kontrol edin.", (long)statusCode];
            if (data.length > 0) {
                NSDictionary *errJson = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                if (errJson && errJson[@"error"] && errJson[@"error"][@"message"]) {
                    errMsg = errJson[@"error"][@"message"];
                }
            }
            NSError *apiErr = [NSError errorWithDomain:@"OpenAIClient" code:statusCode userInfo:@{NSLocalizedDescriptionKey: errMsg}];
            if (completion) completion(nil, apiErr);
            return;
        }

        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSArray *modelsData = json[@"data"];
        NSMutableArray *supported = [NSMutableArray array];

        for (NSDictionary *m in modelsData) {
            NSString *modelId = m[@"id"];
            if ([modelId hasPrefix:@"gpt-"] || [modelId hasPrefix:@"o1"] || [modelId hasPrefix:@"o3"] || [modelId hasPrefix:@"o4"] || [modelId hasPrefix:@"chatgpt-"]) {
                [supported addObject:modelId];
            }
        }

        [supported sortUsingSelector:@selector(compare:)];

        if (supported.count > 0) {
            [[NSUserDefaults standardUserDefaults] setObject:supported forKey:kOpenAICachedModelsKey];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }

        if (completion) completion(supported, nil);
    }];
}

- (void)sendMessage:(NSString *)prompt 
            history:(NSArray *)historyMessages 
          webSearch:(BOOL)webSearch
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

    NSString *model = (self.selectedModel.length > 0) ? self.selectedModel : kDefaultModel;
    BOOL isModern = [self isModernOrReasoningModel:model];

    NSString *urlString = @"https://api.openai.com/v1/chat/completions";
    NSMutableArray *messages = [NSMutableArray array];

    NSString *instructionRole = isModern ? @"developer" : @"system";
    NSMutableString *systemPrompt = [NSMutableString stringWithString:@"Sen iOS 8 iPad Mini üzerinde çalışan retro ve şık ChatGPTRetro asistanısın. Türkçe, net, kibar ve yardımcı yanıtlar ver."];
    
    if (webSearch) {
        [systemPrompt appendString:@" Web araması (canlı internet bilgisi) aktif. En güncel bilgilere göre cevap ver ve kaynakları/tarihleri belirt."];
    }

    [messages addObject:@{
        @"role": instructionRole,
        @"content": systemPrompt
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

    NSMutableDictionary *payloadDict = [NSMutableDictionary dictionary];
    payloadDict[@"model"] = model;
    payloadDict[@"messages"] = messages;

    // Web Search desteği (OpenAI Responses / Tool Search API)
    if (webSearch) {
        payloadDict[@"tools"] = @[
            @{ @"type": @"web_search" }
        ];
    }

    if (!isModern) {
        payloadDict[@"temperature"] = @0.7;
    }

    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:payloadDict options:0 error:nil];

    NSDictionary *headers = @{
        @"Content-Type": @"application/json; charset=utf-8",
        @"Authorization": [NSString stringWithFormat:@"Bearer %@", self.apiKey]
    };

    [self performCurlRequestToURL:urlString 
                           method:@"POST" 
                          headers:headers 
                         jsonBody:bodyData 
                       completion:^(NSData *data, NSInteger statusCode, NSError *error) {
        
        if (error) {
            if (completion) completion(nil, error);
            return;
        }

        // Eğer web_search tool'unu seçili model doğrudan desteklemiyorsa (HTTP 400),
        // aramayı prompt seviyesinde otomatik yedekleyip tekrar dener:
        if (statusCode == 400 && webSearch) {
            [payloadDict removeObjectForKey:@"tools"];
            NSData *fallbackData = [NSJSONSerialization dataWithJSONObject:payloadDict options:0 error:nil];
            [self performCurlRequestToURL:urlString method:@"POST" headers:headers jsonBody:fallbackData completion:^(NSData *fData, NSInteger fStatus, NSError *fErr) {
                if (fErr) {
                    if (completion) completion(nil, fErr);
                    return;
                }
                [self handleResponseData:fData statusCode:fStatus completion:completion];
            }];
            return;
        }

        [self handleResponseData:data statusCode:statusCode completion:completion];
    }];
}

- (void)handleResponseData:(NSData *)data statusCode:(NSInteger)statusCode completion:(OpenAICompletionHandler)completion {
    if (statusCode != 200) {
        NSString *errMsg = [NSString stringWithFormat:@"HTTP Hatası %ld", (long)statusCode];
        if (data.length > 0) {
            NSDictionary *errJson = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (errJson && errJson[@"error"] && errJson[@"error"][@"message"]) {
                errMsg = errJson[@"error"][@"message"];
            }
        }
        NSError *apiErr = [NSError errorWithDomain:@"OpenAIClient" code:statusCode userInfo:@{NSLocalizedDescriptionKey: errMsg}];
        if (completion) completion(nil, apiErr);
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

    if (completion) {
        completion([replyText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]], nil);
    }
}

@end
