#import <UIKit/UIKit.h>
#import "OpenAIClient.h"
#import "ChatMessage.h"
#include <curl/curl.h>
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

NSString *const kChatGPTAuthStateDidChangeNotification = @"ChatGPTAuthStateDidChangeNotification";

static NSString *const kOpenAIApiKeyDefaultsKey      = @"OpenAIClientApiKey";
static NSString *const kOpenAIModelDefaultsKey       = @"OpenAIClientModel";
static NSString *const kOpenAICustomInstructionKey   = @"OpenAIClientCustomInstruction";
static NSString *const kOpenAISystemPromptsListKey   = @"OpenAIClientSystemPromptsList";
static NSString *const kOpenAICachedModelsKey        = @"OpenAIClientCachedModels";

// SIWC Storage Keys
static NSString *const kSIWCHostIdKey                = @"SIWC_HostId";
static NSString *const kSIWCIssuedClientIdKey        = @"SIWC_IssuedClientId";
static NSString *const kSIWCAccessTokenKey           = @"SIWC_AccessToken";
static NSString *const kSIWCRefreshTokenKey          = @"SIWC_RefreshToken";
static NSString *const kSIWCExpiresAtKey             = @"SIWC_ExpiresAt";
static NSString *const kSIWCUserEmailKey             = @"SIWC_UserEmail";
static NSString *const kSIWCUserNameKey              = @"SIWC_UserName";
static NSString *const kSIWCPlanSharingKey           = @"SIWC_PlanSharing";

static NSString *const kSIWCAuthorizeEndpoint        = @"https://auth.openai.com/api/accounts/authorize";
static NSString *const kSIWCTokenEndpoint            = @"https://auth.openai.com/api/accounts/oauth/token";
static NSString *const kSIWCRevokeEndpoint           = @"https://auth.openai.com/api/accounts/oauth/revoke";
static NSString *const kSIWCResource                 = @"https://api.openai.com/v1";
static NSString *const kSIWCScopes                   = @"openid profile email offline_access resource.invoke chatgpt.tokens.use.direct";
static const NSInteger kSIWCRedirectPort             = 8787;

static NSString *const kDefaultModel                 = @"gpt-4o-mini";

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

@interface OpenAIClient ()
@property (nonatomic, copy, readwrite) NSString *hostId;
@property (nonatomic, copy, readwrite) NSString *issuedClientId;
@property (nonatomic, copy, readwrite) NSString *oauthAccessToken;
@property (nonatomic, copy, readwrite) NSString *oauthRefreshToken;
@property (nonatomic, copy, readwrite) NSString *userEmail;
@property (nonatomic, copy, readwrite) NSString *userName;
@property (nonatomic, assign, readwrite) BOOL isPlanSharingEnabled;
@property (nonatomic, assign) NSTimeInterval tokenExpiresAt;

// Active OAuth Transaction State
@property (nonatomic, copy) NSString *pendingCodeVerifier;
@property (nonatomic, copy) NSString *pendingState;
@property (nonatomic, copy) NSString *pendingNonce;
@property (nonatomic, copy) NSString *pendingRedirectUri;
@property (nonatomic, copy) NSString *lastAuthURL;
@property (nonatomic, copy) OpenAISignInHandler pendingSignInCompletion;

// Background Task & Loopback Socket
@property (nonatomic, assign) int listenSocketFD;
@property (nonatomic, assign) UIBackgroundTaskIdentifier bgTask;
@end

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
        _listenSocketFD = -1;
        _bgTask = UIBackgroundTaskInvalid;

        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        _apiKey = [defaults stringForKey:kOpenAIApiKeyDefaultsKey] ?: @"";
        _selectedModel = [defaults stringForKey:kOpenAIModelDefaultsKey] ?: kDefaultModel;
        _customSystemInstruction = [defaults stringForKey:kOpenAICustomInstructionKey] ?: @"";

        NSArray *savedPrompts = [defaults arrayForKey:kOpenAISystemPromptsListKey];
        if (savedPrompts) {
            _systemPromptsList = [NSMutableArray array];
            for (NSDictionary *dict in savedPrompts) {
                [_systemPromptsList addObject:[dict mutableCopy]];
            }
        } else {
            _systemPromptsList = [NSMutableArray array];
            // Eğer daha önceden kalan customSystemInstruction varsa bunu ilk prompt olarak aktaralım
            if (_customSystemInstruction.length > 0) {
                [_systemPromptsList addObject:[@{
                    @"id": [[NSUUID UUID] UUIDString],
                    @"title": @"Özel Talimatım",
                    @"content": _customSystemInstruction,
                    @"enabled": @YES
                } mutableCopy]];
            }
        }

        if ([defaults objectForKey:@"OpenAI_ReasoningEffortLevel"] != nil) {
            _reasoningEffortLevel = [defaults integerForKey:@"OpenAI_ReasoningEffortLevel"];
        } else {
            _reasoningEffortLevel = 3; // Default: medium
        }
        _enableReasoningSummary = [defaults boolForKey:@"OpenAI_EnableReasoningSummary"];
        _enableWebSearch = [defaults boolForKey:@"enable_chatgpt_web_search"];
        _enableCodeInterpreter = [defaults boolForKey:@"OpenAI_EnableCodeInterpreter"];
        if ([defaults objectForKey:@"OpenAI_ModelTemperature"] != nil) {
            _modelTemperature = [defaults floatForKey:@"OpenAI_ModelTemperature"];
        } else {
            _modelTemperature = 0.7f;
        }

        // Advanced Cost Optimizations
        _enablePromptCaching = [defaults objectForKey:@"Adv_EnablePromptCaching"] ? [defaults boolForKey:@"Adv_EnablePromptCaching"] : YES;
        _enableTruncateAssistant = [defaults boolForKey:@"Adv_EnableTruncateAssistant"];
        _enableKeywordFiltering = [defaults boolForKey:@"Adv_EnableKeywordFiltering"];
        _maxHistoryTurns = [defaults objectForKey:@"Adv_MaxHistoryTurns"] ? [defaults integerForKey:@"Adv_MaxHistoryTurns"] : 8;

        // 1. Prepare App's Host ID (urn:uuid:...) per SIWC DevKit spec
        _hostId = [defaults stringForKey:kSIWCHostIdKey];
        if (!_hostId || ![_hostId hasPrefix:@"urn:uuid:"]) {
            NSString *uuidStr = [[[NSUUID UUID] UUIDString] lowercaseString];
            _hostId = [NSString stringWithFormat:@"urn:uuid:%@", uuidStr];
            [defaults setObject:_hostId forKey:kSIWCHostIdKey];
            [defaults synchronize];
        }

        _issuedClientId = [defaults stringForKey:kSIWCIssuedClientIdKey] ?: @"";
        _oauthAccessToken = [defaults stringForKey:kSIWCAccessTokenKey] ?: @"";
        _oauthRefreshToken = [defaults stringForKey:kSIWCRefreshTokenKey] ?: @"";
        _userEmail = [defaults stringForKey:kSIWCUserEmailKey] ?: @"";
        _userName = [defaults stringForKey:kSIWCUserNameKey] ?: @"";
        _isPlanSharingEnabled = [defaults boolForKey:kSIWCPlanSharingKey];
        _tokenExpiresAt = [defaults doubleForKey:kSIWCExpiresAtKey];
    }
    return self;
}

- (void)setEnablePromptCaching:(BOOL)enablePromptCaching {
    _enablePromptCaching = enablePromptCaching;
    [[NSUserDefaults standardUserDefaults] setBool:enablePromptCaching forKey:@"Adv_EnablePromptCaching"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)setEnableTruncateAssistant:(BOOL)enableTruncateAssistant {
    _enableTruncateAssistant = enableTruncateAssistant;
    [[NSUserDefaults standardUserDefaults] setBool:enableTruncateAssistant forKey:@"Adv_EnableTruncateAssistant"];
    if (enableTruncateAssistant) {
        _enableKeywordFiltering = NO;
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"Adv_EnableKeywordFiltering"];
    }
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)setEnableKeywordFiltering:(BOOL)enableKeywordFiltering {
    _enableKeywordFiltering = enableKeywordFiltering;
    [[NSUserDefaults standardUserDefaults] setBool:enableKeywordFiltering forKey:@"Adv_EnableKeywordFiltering"];
    if (enableKeywordFiltering) {
        _enableTruncateAssistant = NO;
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"Adv_EnableTruncateAssistant"];
    }
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)setMaxHistoryTurns:(NSInteger)maxHistoryTurns {
    if (maxHistoryTurns < 1) maxHistoryTurns = 1;
    if (maxHistoryTurns > 20) maxHistoryTurns = 20;
    _maxHistoryTurns = maxHistoryTurns;
    [[NSUserDefaults standardUserDefaults] setInteger:maxHistoryTurns forKey:@"Adv_MaxHistoryTurns"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - Context & Cost Optimization Helpers

- (NSSet<NSString *> *)extractKeywordsFromString:(NSString *)text {
    if (!text || text.length == 0) return [NSSet set];
    NSCharacterSet *punctAndSpace = [NSCharacterSet characterSetWithCharactersInString:@" \t\r\n.,;:!?'\"()[]{}<>/\\|@#$%^&*-_+=`~"];
    NSArray *words = [text componentsSeparatedByCharactersInSet:punctAndSpace];
    NSMutableSet *keywords = [NSMutableSet set];
    NSSet *stopWords = [NSSet setWithObjects:@"ve", @"ile", @"bir", @"bu", @"su", @"o", @"de", @"da", @"mi", @"mu", @"mü", @"icin", @"ama", @"fakat", @"gibi", @"kadar", @"the", @"and", @"is", @"in", @"to", @"of", @"it", @"that", @"you", @"was", @"for", @"on", @"are", @"as", @"with", @"at", @"be", @"this", @"have", @"from", nil];

    for (NSString *w in words) {
        NSString *cleaned = [[w lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (cleaned.length >= 3 && ![stopWords containsObject:cleaned]) {
            [keywords addObject:cleaned];
        }
    }
    return keywords;
}

- (NSString *)truncateAssistantMessage:(NSString *)text {
    if (!text || text.length <= 400) return text;
    // İlk 200 karakter + son 150 karakteri alarak aradaki uzun açıklamaları at
    NSString *head = [text substringToIndex:200];
    NSString *tail = [text substringFromIndex:text.length - 150];
    return [NSString stringWithFormat:@"%@\n[...detaylar maliyet tasarrufu için kırpıldı...]\n%@", head, tail];
}

- (NSArray<NSDictionary *> *)prepareOptimizedHistoryMessages:(NSArray *)historyMessages currentPrompt:(NSString *)currentPrompt {
    NSMutableArray<ChatMessage *> *filtered = [NSMutableArray array];
    for (ChatMessage *msg in historyMessages) {
        if ([msg.text containsString:@"iPad Mini 1 (iOS 8.4"] || [msg.text isEqualToString:@"..."]) {
            continue;
        }
        [filtered addObject:msg];
    }

    // 1. Sliding Window (Slider ile seçilen tur sayısı)
    NSInteger turnsLimit = self.maxHistoryTurns > 0 ? self.maxHistoryTurns : 8;
    NSInteger startIndex = 0;
    if ((NSInteger)filtered.count > turnsLimit) {
        startIndex = filtered.count - turnsLimit;
    }

    NSMutableArray<ChatMessage *> *windowedMessages = [NSMutableArray array];
    for (NSInteger i = startIndex; i < (NSInteger)filtered.count; i++) {
        [windowedMessages addObject:filtered[i]];
    }

    // 2. Anahtar Kelime Filtreleme (TF-IDF benzeri eşleşme)
    if (self.enableKeywordFiltering && currentPrompt.length > 0) {
        NSSet *promptKeywords = [self extractKeywordsFromString:currentPrompt];
        NSMutableArray<ChatMessage *> *relevantMessages = [NSMutableArray array];

        for (ChatMessage *msg in windowedMessages) {
            NSSet *msgKeywords = [self extractKeywordsFromString:msg.text];
            NSMutableSet *intersection = [promptKeywords mutableCopy];
            [intersection intersectSet:msgKeywords];

            // Kullanıcının mesajıysa veya ortak anahtar kelime barındırıyorsa tut
            if (msg.sender == ChatMessageSenderUser || intersection.count > 0) {
                [relevantMessages addObject:msg];
            }
        }
        // Eğer hiçbir eşleşme çıkmadıysa son 2 mesajı bari koru
        if (relevantMessages.count == 0 && windowedMessages.count > 0) {
            NSInteger keep = MIN((NSInteger)windowedMessages.count, 2);
            for (NSInteger i = windowedMessages.count - keep; i < (NSInteger)windowedMessages.count; i++) {
                [relevantMessages addObject:windowedMessages[i]];
            }
        }
        windowedMessages = relevantMessages;
    }

    // 3. Mesaj formatına dönüştürme ve (varsa) Asistan yanıtlarını kırpma
    NSMutableArray *result = [NSMutableArray array];
    for (ChatMessage *msg in windowedMessages) {
        NSString *role = (msg.sender == ChatMessageSenderUser) ? @"user" : @"assistant";
        NSString *body = msg.text ?: @"";

        if (self.enableTruncateAssistant && msg.sender == ChatMessageSenderAssistant) {
            body = [self truncateAssistantMessage:body];
        }

        [result addObject:@{
            @"role": role,
            @"content": body
        }];
    }

    return result;
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

- (void)saveCustomSystemInstruction:(NSString *)instruction {
    _customSystemInstruction = [instruction stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    [[NSUserDefaults standardUserDefaults] setObject:_customSystemInstruction forKey:kOpenAICustomInstructionKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)saveSystemPromptsList:(NSArray *)prompts {
    _systemPromptsList = [NSMutableArray array];
    for (NSDictionary *dict in prompts) {
        [_systemPromptsList addObject:[dict mutableCopy]];
    }
    [[NSUserDefaults standardUserDefaults] setObject:_systemPromptsList forKey:kOpenAISystemPromptsListKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSString *)effectiveCombinedSystemInstructionWithWebSearch:(BOOL)webSearch {
    NSMutableString *combined = [NSMutableString string];

    // Kullanıcının sistem genelindeki aktif (tikli) talimatları ekleniyor
    for (NSDictionary *promptDict in self.systemPromptsList) {
        if ([promptDict[@"enabled"] boolValue]) {
            NSString *content = [promptDict[@"content"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (content.length > 0) {
                if (combined.length > 0) {
                    [combined appendString:@"\n\n"];
                }
                [combined appendString:content];
            }
        }
    }

    if (webSearch) {
        if (combined.length > 0) {
            [combined appendString:@"\n\n"];
        }
        [combined appendString:@"Web araması aktif. En güncel bilgilere göre cevap ver ve kaynakları/tarihleri belirt."];
    }

    return combined;
}

- (void)setReasoningEffortLevel:(NSInteger)reasoningEffortLevel {
    if (reasoningEffortLevel < 0) reasoningEffortLevel = 0;
    if (reasoningEffortLevel > 6) reasoningEffortLevel = 6;
    _reasoningEffortLevel = reasoningEffortLevel;
    [[NSUserDefaults standardUserDefaults] setInteger:_reasoningEffortLevel forKey:@"OpenAI_ReasoningEffortLevel"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)setEnableReasoningSummary:(BOOL)enableReasoningSummary {
    _enableReasoningSummary = enableReasoningSummary;
    [[NSUserDefaults standardUserDefaults] setBool:_enableReasoningSummary forKey:@"OpenAI_EnableReasoningSummary"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)setEnableWebSearch:(BOOL)enableWebSearch {
    _enableWebSearch = enableWebSearch;
    [[NSUserDefaults standardUserDefaults] setBool:_enableWebSearch forKey:@"enable_chatgpt_web_search"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)setEnableCodeInterpreter:(BOOL)enableCodeInterpreter {
    _enableCodeInterpreter = enableCodeInterpreter;
    [[NSUserDefaults standardUserDefaults] setBool:_enableCodeInterpreter forKey:@"OpenAI_EnableCodeInterpreter"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)setModelTemperature:(float)modelTemperature {
    if (modelTemperature < 0.0f) modelTemperature = 0.0f;
    if (modelTemperature > 2.0f) modelTemperature = 2.0f;
    _modelTemperature = modelTemperature;
    [[NSUserDefaults standardUserDefaults] setFloat:_modelTemperature forKey:@"OpenAI_ModelTemperature"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSString *)reasoningEffortApiValueForLevel:(NSInteger)level {
    NSArray *levels = @[@"none", @"minimal", @"low", @"medium", @"high", @"xhigh", @"max"];
    if (level >= 0 && level < levels.count) {
        return levels[level];
    }
    return @"medium";
}

- (BOOL)supportsReasoningEffortForModel:(NSString *)model {
    return [self isModernOrReasoningModel:model];
}

- (BOOL)supportsWebSearchForModel:(NSString *)model {
    NSString *m = [model lowercaseString];
    if ([m hasPrefix:@"gpt-3.5"] || [m isEqualToString:@"gpt-4"] || [m hasPrefix:@"gpt-4-0"]) return NO;
    return YES;
}

- (BOOL)supportsCodeInterpreterForModel:(NSString *)model {
    NSString *m = [model lowercaseString];
    if ([m hasPrefix:@"gpt-3.5"]) return NO;
    return YES;
}

- (BOOL)supportsTemperatureForModel:(NSString *)model {
    return ![self isModernOrReasoningModel:model];
}

- (BOOL)isChatGPTAccountLinked {
    return (self.oauthAccessToken.length > 10);
}

- (BOOL)isAuthenticated {
    if ([self isChatGPTAccountLinked]) return YES;
    return (self.apiKey.length > 10);
}

- (NSString *)activeBearerToken {
    if ([self isChatGPTAccountLinked]) {
        return self.oauthAccessToken;
    }
    return self.apiKey;
}

#pragma mark - PKCE & Base64URL Helpers

- (NSString *)base64UrlEncodeData:(NSData *)data {
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return base64;
}

- (NSString *)generateRandomBase64UrlToken {
    uint8_t bytes[32];
    SecRandomCopyBytes(kSecRandomDefault, 32, bytes);
    NSData *data = [NSData dataWithBytes:bytes length:32];
    return [self base64UrlEncodeData:data];
}

- (NSString *)sha256Base64Url:(NSString *)input {
    NSData *data = [input dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSData *hashData = [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
    return [self base64UrlEncodeData:hashData];
}

- (NSString *)urlEncode:(NSString *)str {
    if (!str) return @"";
    CFStringRef encoded = CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,
                                                                  (__bridge CFStringRef)str,
                                                                  NULL,
                                                                  CFSTR("!*'();:@&=+$,/?%#[] "),
                                                                  kCFStringEncodingUTF8);
    return (__bridge_transfer NSString *)encoded;
}

- (NSDictionary *)decodeJWTClaims:(NSString *)jwt {
    if (!jwt) return nil;
    NSArray *parts = [jwt componentsSeparatedByString:@"."];
    if (parts.count < 2) return nil;
    NSString *payloadB64 = parts[1];
    payloadB64 = [payloadB64 stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    payloadB64 = [payloadB64 stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    while (payloadB64.length % 4 != 0) {
        payloadB64 = [payloadB64 stringByAppendingString:@"="];
    }
    NSData *decoded = [[NSData alloc] initWithBase64EncodedString:payloadB64 options:0];
    if (!decoded) return nil;
    NSDictionary *claims = [NSJSONSerialization JSONObjectWithData:decoded options:0 error:nil];
    return [claims isKindOfClass:[NSDictionary class]] ? claims : nil;
}

#pragma mark - Sign in with ChatGPT (Direct Safari + 127.0.0.1 Loopback Server)

- (NSString *)currentAuthorizationURL {
    return self.lastAuthURL ?: @"";
}

- (void)stopLoopbackListener {
    if (self.listenSocketFD >= 0) {
        close(self.listenSocketFD);
        self.listenSocketFD = -1;
    }
    if (self.bgTask != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:self.bgTask];
        self.bgTask = UIBackgroundTaskInvalid;
    }
}

- (NSString *)prepareOAuthAuthorizationURL {
    [self stopLoopbackListener];

    // Generate fresh state, nonce, and PKCE values
    self.pendingState = [self generateRandomBase64UrlToken];
    self.pendingNonce = [self generateRandomBase64UrlToken];
    self.pendingCodeVerifier = [self generateRandomBase64UrlToken];
    NSString *codeChallenge = [self sha256Base64Url:self.pendingCodeVerifier];

    // Start background task so iOS 8 keeps our loopback callback server alive
    UIApplication *app = [UIApplication sharedApplication];
    self.bgTask = [app beginBackgroundTaskWithExpirationHandler:^{
        [self stopLoopbackListener];
    }];

    // Bind server on port 8787 (INADDR_ANY 0.0.0.0 so both 127.0.0.1 and Wi-Fi LAN IP can access)
    int serverFD = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(serverFD, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons(kSIWCRedirectPort);

    NSInteger boundPort = kSIWCRedirectPort;
    if (bind(serverFD, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        // Fallback to any free ephemeral port if 8787 is busy
        addr.sin_port = 0;
        bind(serverFD, (struct sockaddr *)&addr, sizeof(addr));
        socklen_t len = sizeof(addr);
        getsockname(serverFD, (struct sockaddr *)&addr, &len);
        boundPort = ntohs(addr.sin_port);
    }

    listen(serverFD, 5);
    self.listenSocketFD = serverFD;
    self.pendingRedirectUri = [NSString stringWithFormat:@"http://127.0.0.1:%ld/auth/callback", (long)boundPort];

    BOOL hasIssuedClient = (self.issuedClientId.length > 0 && ![self.issuedClientId isEqualToString:@"dynamic_agent_client"]);
    NSString *clientIdParam = hasIssuedClient ? self.issuedClientId : @"dynamic_agent_client";

    NSMutableString *authUrl = [NSMutableString stringWithFormat:@"%@?client_id=%@&response_type=code&redirect_uri=%@&scope=%@&resource=%@&state=%@&nonce=%@&code_challenge_method=S256&code_challenge=%@&ext_agent_host_id=%@",
                                kSIWCAuthorizeEndpoint,
                                [self urlEncode:clientIdParam],
                                [self urlEncode:self.pendingRedirectUri],
                                [self urlEncode:kSIWCScopes],
                                [self urlEncode:kSIWCResource],
                                [self urlEncode:self.pendingState],
                                [self urlEncode:self.pendingNonce],
                                [self urlEncode:codeChallenge],
                                [self urlEncode:self.hostId]];

    if (!hasIssuedClient) {
        [authUrl appendFormat:@"&agent_name_hint=%@", [self urlEncode:@"ChatGPT Retro"]];
    }
    if (self.userEmail.length > 0) {
        [authUrl appendFormat:@"&login_hint=%@", [self urlEncode:self.userEmail]];
    }

    self.lastAuthURL = authUrl;

    // Accept callback on background thread
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        while (self.listenSocketFD == serverFD && serverFD >= 0) {
            struct sockaddr_in clientAddr;
            socklen_t clientLen = sizeof(clientAddr);
            int clientFD = accept(serverFD, (struct sockaddr *)&clientAddr, &clientLen);
            if (clientFD < 0) break;

            char buffer[4096];
            ssize_t bytesRead = recv(clientFD, buffer, sizeof(buffer) - 1, 0);
            if (bytesRead > 0) {
                buffer[bytesRead] = '\0';
                NSString *requestStr = [NSString stringWithUTF8String:buffer];
                NSArray *lines = [requestStr componentsSeparatedByString:@"\r\n"];
                NSString *firstLine = lines.firstObject ?: @"";
                // Example: GET /auth/callback?code=...&client_id=...&state=... HTTP/1.1
                NSArray *parts = [firstLine componentsSeparatedByString:@" "];
                if (parts.count >= 2) {
                    NSString *pathAndQuery = parts[1];
                    if ([pathAndQuery hasPrefix:@"/auth/callback"]) {
                        // Send HTML page that automatically redirects back to chatgptretro://
                        NSString *deepLink = [NSString stringWithFormat:@"chatgptretro://auth%@", [pathAndQuery substringFromIndex:14]];
                        NSString *html = [NSString stringWithFormat:
                            @"HTTP/1.1 200 OK\r\n"
                            @"Content-Type: text/html; charset=utf-8\r\n"
                            @"Cache-Control: no-store\r\n"
                            @"Connection: close\r\n\r\n"
                            @"<!doctype html><html lang='tr'><head><meta charset='utf-8'>"
                            @"<meta name='viewport' content='width=device-width, initial-scale=1'>"
                            @"<title>ChatGPT Retro'ya Dönülüyor</title>"
                            @"<style>body{font:17px -apple-system,HelveticaNeue,sans-serif;max-width:28rem;margin:15vh auto;padding:24px;text-align:center;color:#202123;background:#f7f7f8}"
                            @"h1{font-size:22px;color:#10a37f}a.btn{display:inline-block;margin-top:18px;padding:12px 24px;background:#10a37f;color:#fff;text-decoration:none;border-radius:8px;font-weight:bold}</style></head>"
                            @"<body><h1>Giriş Başarılı!</h1><p>ChatGPT bağlantınız doğrulanıyor. Uygulamaya otomatik yönlendiriliyorsunuz...</p>"
                            @"<a class='btn' href='%@'>ChatGPT Retro'ya Dön</a>"
                            @"<script>setTimeout(function(){ window.location.href = '%@'; }, 200);</script></body></html>",
                            deepLink, deepLink];

                        const char *respBytes = [html UTF8String];
                        send(clientFD, respBytes, strlen(respBytes), 0);
                        close(clientFD);

                        NSString *fullCallbackUrl = [NSString stringWithFormat:@"http://127.0.0.1:%ld%@", (long)boundPort, pathAndQuery];
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self handleIncomingCallbackURLString:fullCallbackUrl completion:self.pendingSignInCompletion];
                            self.pendingSignInCompletion = nil;
                        });
                        break;
                    }
                }
            }
            close(clientFD);
        }
        [self stopLoopbackListener];
    });

    return authUrl;
}

- (void)startSignInWithChatGPTInSafariWithCompletion:(OpenAISignInHandler)completion {
    self.pendingSignInCompletion = completion;
    NSString *authUrl = [self prepareOAuthAuthorizationURL];

    // Open Safari directly with the authorization URL
    NSURL *safariURL = [NSURL URLWithString:authUrl];
    if (safariURL) {
        [[UIApplication sharedApplication] openURL:safariURL];
    }
}

- (NSDictionary *)parseQueryParametersFromString:(NSString *)raw {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    NSString *query = raw;
    NSRange qMark = [raw rangeOfString:@"?"];
    if (qMark.location != NSNotFound) {
        query = [raw substringFromIndex:qMark.location + 1];
    }
    NSArray *pairs = [query componentsSeparatedByString:@"&"];
    for (NSString *pair in pairs) {
        NSArray *kv = [pair componentsSeparatedByString:@"="];
        if (kv.count == 2) {
            NSString *k = [kv[0] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            NSString *v = [kv[1] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            if (k && v) params[k] = v;
        }
    }
    return params;
}

- (void)handleIncomingCallbackURLString:(NSString *)rawInput completion:(OpenAISignInHandler)completion {
    [self stopLoopbackListener];

    NSString *trimmed = [rawInput stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        if (completion) {
            NSError *err = [NSError errorWithDomain:@"SIWC" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Doğrulama yanıtı boş."}];
            completion(NO, err);
        }
        return;
    }

    NSDictionary *params = [self parseQueryParametersFromString:trimmed];
    if (params[@"error"]) {
        NSString *errMsg = params[@"error_description"] ?: params[@"error"];
        NSError *err = [NSError errorWithDomain:@"SIWC" code:400 userInfo:@{NSLocalizedDescriptionKey: errMsg}];
        if (completion) completion(NO, err);
        return;
    }

    NSString *code = params[@"code"] ?: trimmed;
    NSString *returnedClientId = params[@"client_id"];
    NSString *extractedRedirectUri = self.pendingRedirectUri ?: [NSString stringWithFormat:@"http://127.0.0.1:%ld/auth/callback", (long)kSIWCRedirectPort];

    if ([trimmed hasPrefix:@"http://127.0.0.1"]) {
        NSRange qRange = [trimmed rangeOfString:@"?"];
        if (qRange.location != NSNotFound) {
            extractedRedirectUri = [trimmed substringToIndex:qRange.location];
        }
    }

    NSString *effectiveClientId = returnedClientId ?: self.issuedClientId;
    if (!effectiveClientId || effectiveClientId.length == 0 || [effectiveClientId isEqualToString:@"dynamic_agent_client"]) {
        NSError *err = [NSError errorWithDomain:@"SIWC" code:400 userInfo:@{NSLocalizedDescriptionKey: @"OpenAI tarafından verilen client_id alınamadı. Lütfen tekrar giriş yapmayı deneyin."}];
        if (completion) completion(NO, err);
        return;
    }

    // 1. Save issued client_id before exchanging one-time code (per SIWC DevKit spec)
    self.issuedClientId = effectiveClientId;
    [[NSUserDefaults standardUserDefaults] setObject:effectiveClientId forKey:kSIWCIssuedClientIdKey];
    [[NSUserDefaults standardUserDefaults] synchronize];

    // 2. Exchange authorization code for tokens
    NSString *verifier = self.pendingCodeVerifier ?: @"";
    NSString *formBody = [NSString stringWithFormat:@"grant_type=authorization_code&client_id=%@&code=%@&code_verifier=%@&redirect_uri=%@&resource=%@",
                          [self urlEncode:effectiveClientId],
                          [self urlEncode:code],
                          [self urlEncode:verifier],
                          [self urlEncode:extractedRedirectUri],
                          [self urlEncode:kSIWCResource]];

    NSDictionary *headers = @{
        @"Content-Type": @"application/x-www-form-urlencoded",
        @"Accept": @"application/json"
    };

    [self performCurlRequestToURL:kSIWCTokenEndpoint
                           method:@"POST"
                          headers:headers
                             body:[formBody dataUsingEncoding:NSUTF8StringEncoding]
                       completion:^(NSData *data, NSInteger statusCode, NSError *error) {
        if (error) {
            if (completion) completion(NO, error);
            return;
        }

        NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (statusCode != 200 || !json || !json[@"access_token"]) {
            NSString *errMsg = json[@"error_description"] ?: json[@"error"] ?: [NSString stringWithFormat:@"Token değişimi başarısız (HTTP %ld)", (long)statusCode];
            NSError *apiErr = [NSError errorWithDomain:@"SIWC" code:statusCode userInfo:@{NSLocalizedDescriptionKey: errMsg}];
            if (completion) completion(NO, apiErr);
            return;
        }

        [self storeTokenResponse:json];
        [[NSNotificationCenter defaultCenter] postNotificationName:kChatGPTAuthStateDidChangeNotification object:nil];
        if (completion) completion(YES, nil);
    }];
}

- (void)storeTokenResponse:(NSDictionary *)json {
    NSString *accessToken = json[@"access_token"] ?: @"";
    NSString *refreshToken = json[@"refresh_token"];
    NSNumber *expiresIn = json[@"expires_in"];
    NSString *scopeStr = json[@"scope"] ?: @"";
    NSString *idToken = json[@"id_token"];

    self.oauthAccessToken = accessToken;
    if (refreshToken && refreshToken.length > 0) {
        self.oauthRefreshToken = refreshToken;
    }

    NSTimeInterval exp = [[NSDate date] timeIntervalSince1970] + (expiresIn ? [expiresIn doubleValue] : 3600.0);
    self.tokenExpiresAt = exp;

    if (scopeStr.length > 0) {
        self.isPlanSharingEnabled = [scopeStr containsString:@"chatgpt.tokens.use.direct"];
    } else {
        self.isPlanSharingEnabled = YES;
    }

    if (idToken) {
        NSDictionary *claims = [self decodeJWTClaims:idToken];
        if (claims[@"email"]) self.userEmail = claims[@"email"];
        if (claims[@"name"]) self.userName = claims[@"name"];
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:self.oauthAccessToken forKey:kSIWCAccessTokenKey];
    if (self.oauthRefreshToken) [defaults setObject:self.oauthRefreshToken forKey:kSIWCRefreshTokenKey];
    [defaults setDouble:self.tokenExpiresAt forKey:kSIWCExpiresAtKey];
    [defaults setBool:self.isPlanSharingEnabled forKey:kSIWCPlanSharingKey];
    if (self.userEmail) [defaults setObject:self.userEmail forKey:kSIWCUserEmailKey];
    if (self.userName) [defaults setObject:self.userName forKey:kSIWCUserNameKey];
    [defaults synchronize];
}

- (void)refreshOAuthTokenIfNeededWithCompletion:(void (^)(BOOL success))completion {
    if (![self isChatGPTAccountLinked]) {
        if (completion) completion(NO);
        return;
    }

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (self.tokenExpiresAt > now + 60.0) {
        if (completion) completion(YES);
        return;
    }

    if (self.oauthRefreshToken.length == 0 || self.issuedClientId.length == 0) {
        if (completion) completion(YES);
        return;
    }

    NSString *formBody = [NSString stringWithFormat:@"grant_type=refresh_token&client_id=%@&refresh_token=%@&resource=%@",
                          [self urlEncode:self.issuedClientId],
                          [self urlEncode:self.oauthRefreshToken],
                          [self urlEncode:kSIWCResource]];

    NSDictionary *headers = @{
        @"Content-Type": @"application/x-www-form-urlencoded",
        @"Accept": @"application/json"
    };

    [self performCurlRequestToURL:kSIWCTokenEndpoint
                           method:@"POST"
                          headers:headers
                             body:[formBody dataUsingEncoding:NSUTF8StringEncoding]
                       completion:^(NSData *data, NSInteger statusCode, NSError *error) {
        if (statusCode == 200 && data) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (json && json[@"access_token"]) {
                [self storeTokenResponse:json];
                if (completion) completion(YES);
                return;
            }
        }
        if (completion) completion(NO);
    }];
}

- (void)disconnectChatGPTAccountWithCompletion:(void (^)(void))completion {
    NSString *tokenToRevoke = self.oauthRefreshToken.length > 0 ? self.oauthRefreshToken : self.oauthAccessToken;
    NSString *cid = self.issuedClientId;

    self.oauthAccessToken = @"";
    self.oauthRefreshToken = @"";
    self.isPlanSharingEnabled = NO;
    self.tokenExpiresAt = 0;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:kSIWCAccessTokenKey];
    [defaults removeObjectForKey:kSIWCRefreshTokenKey];
    [defaults removeObjectForKey:kSIWCExpiresAtKey];
    [defaults setBool:NO forKey:kSIWCPlanSharingKey];
    [defaults synchronize];

    [[NSNotificationCenter defaultCenter] postNotificationName:kChatGPTAuthStateDidChangeNotification object:nil];

    if (tokenToRevoke.length > 0 && cid.length > 0) {
        NSString *formBody = [NSString stringWithFormat:@"token=%@&token_type_hint=refresh_token&client_id=%@",
                              [self urlEncode:tokenToRevoke],
                              [self urlEncode:cid]];
        NSDictionary *headers = @{ @"Content-Type": @"application/x-www-form-urlencoded" };
        [self performCurlRequestToURL:kSIWCRevokeEndpoint
                               method:@"POST"
                              headers:headers
                                 body:[formBody dataUsingEncoding:NSUTF8StringEncoding]
                           completion:^(NSData *data, NSInteger statusCode, NSError *error) {
            if (completion) completion();
        }];
    } else {
        if (completion) completion();
    }
}

#pragma mark - Model Classification Helpers

- (BOOL)isModernOrReasoningModel:(NSString *)model {
    NSString *m = [model lowercaseString];
    if ([m hasPrefix:@"o1"] || [m hasPrefix:@"o3"] || [m hasPrefix:@"o4"]) return YES;
    if ([m containsString:@"luna"] || [m containsString:@"sol"] || [m containsString:@"terra"] || [m containsString:@"astra"]) return YES;
    if ([m hasPrefix:@"gpt-5"] || [m hasPrefix:@"gpt-6"]) return YES;
    return NO;
}

#pragma mark - cURL Request Engine

- (void)performCurlRequestToURL:(NSString *)urlString 
                         method:(NSString *)method 
                        headers:(NSDictionary *)headers 
                           body:(NSData *)bodyData 
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
        curl_easy_setopt(curl, CURLOPT_TIMEOUT, 90L);
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

#pragma mark - Public API Methods

- (void)fetchAvailableModelsWithCompletion:(OpenAIModelsHandler)completion {
    if (![self isAuthenticated]) {
        if (completion) {
            NSError *err = [NSError errorWithDomain:@"OpenAIClient" 
                                               code:401 
                                           userInfo:@{NSLocalizedDescriptionKey: @"Lütfen önce ChatGPT ile giriş yapın veya bir OpenAI API Anahtarı girin."}];
            completion(nil, err);
        }
        return;
    }

    [self refreshOAuthTokenIfNeededWithCompletion:^(BOOL refreshed) {
        NSString *urlString = @"https://api.openai.com/v1/models";
        NSDictionary *headers = @{
            @"Authorization": [NSString stringWithFormat:@"Bearer %@", [self activeBearerToken]],
            @"Accept": @"application/json"
        };

        [self performCurlRequestToURL:urlString 
                               method:@"GET" 
                              headers:headers 
                                 body:nil 
                           completion:^(NSData *data, NSInteger statusCode, NSError *error) {
            
            if (error) {
                if (completion) completion(nil, error);
                return;
            }

            if (statusCode != 200) {
                NSString *errMsg = [NSString stringWithFormat:@"HTTP %ld: Kimlik doğrulamanızı kontrol edin.", (long)statusCode];
                if (data.length > 0) {
                    NSDictionary *errJson = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                    if (errJson && errJson[@"error"]) {
                        if ([errJson[@"error"] isKindOfClass:[NSDictionary class]] && errJson[@"error"][@"message"]) {
                            errMsg = errJson[@"error"][@"message"];
                        } else if ([errJson[@"error"] isKindOfClass:[NSString class]]) {
                            errMsg = errJson[@"error"];
                        }
                    }
                }
                NSError *apiErr = [NSError errorWithDomain:@"OpenAIClient" code:statusCode userInfo:@{NSLocalizedDescriptionKey: errMsg}];
                if (completion) completion(nil, apiErr);
                return;
            }

            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSMutableArray *supported = [NSMutableArray array];

            // 1. SIWC Model Catalog format: { "models": [ { "slug": "...", "display_name": "...", "visibility": "list" } ] }
            if ([json[@"models"] isKindOfClass:[NSArray class]]) {
                for (NSDictionary *m in json[@"models"]) {
                    NSString *visibility = m[@"visibility"];
                    NSString *slug = m[@"slug"];
                    if (slug && (!visibility || [visibility isEqualToString:@"list"])) {
                        [supported addObject:slug];
                    }
                }
            }
            // 2. Standard Platform API format: { "data": [ { "id": "..." } ] }
            else if ([json[@"data"] isKindOfClass:[NSArray class]]) {
                for (NSDictionary *m in json[@"data"]) {
                    NSString *modelId = m[@"id"];
                    if ([modelId hasPrefix:@"gpt-"] || [modelId hasPrefix:@"o1"] || [modelId hasPrefix:@"o3"] || [modelId hasPrefix:@"o4"] || [modelId hasPrefix:@"chatgpt-"]) {
                        [supported addObject:modelId];
                    }
                }
                [supported sortUsingSelector:@selector(compare:)];
            }

            if (supported.count > 0) {
                [[NSUserDefaults standardUserDefaults] setObject:supported forKey:kOpenAICachedModelsKey];
                [[NSUserDefaults standardUserDefaults] synchronize];
            }

            if (completion) completion(supported, nil);
        }];
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
                                           userInfo:@{NSLocalizedDescriptionKey: @"Kimlik doğrulaması bulunamadı. Lütfen Ayarlar'dan ChatGPT ile giriş yapın veya API Anahtarınızı girin."}];
            completion(nil, err);
        }
        return;
    }

    [self refreshOAuthTokenIfNeededWithCompletion:^(BOOL refreshed) {
        if ([self isChatGPTAccountLinked]) {
            [self sendMessageViaResponsesAPI:prompt history:historyMessages webSearch:webSearch completion:completion];
        } else {
            [self sendMessageViaChatCompletionsAPI:prompt history:historyMessages webSearch:webSearch completion:completion];
        }
    }];
}

// SIWC Direct Plan Sharing Endpoint (/v1/responses with SSE streaming as required by SIWC DevKit)
- (void)sendMessageViaResponsesAPI:(NSString *)prompt
                           history:(NSArray *)historyMessages
                         webSearch:(BOOL)webSearch
                        completion:(OpenAICompletionHandler)completion {

    NSString *model = (self.selectedModel.length > 0) ? self.selectedModel : kDefaultModel;
    NSString *urlString = @"https://api.openai.com/v1/responses";

    NSString *instructions = [self effectiveCombinedSystemInstructionWithWebSearch:webSearch];

    // Optimize edilmiş geçmişi al (Sliding window + keyword filter + truncate assistant)
    NSArray *optimizedHistory = [self prepareOptimizedHistoryMessages:historyMessages currentPrompt:prompt];
    NSMutableArray *inputMessages = [NSMutableArray arrayWithArray:optimizedHistory];

    [inputMessages addObject:@{
        @"role": @"user",
        @"content": prompt ?: @""
    }];

    NSMutableDictionary *payloadDict = [NSMutableDictionary dictionary];
    payloadDict[@"model"] = model;
    payloadDict[@"input"] = inputMessages;
    if (instructions.length > 0) {
        payloadDict[@"instructions"] = instructions;
    }
    payloadDict[@"store"] = @NO;
    payloadDict[@"stream"] = @YES;

    // 1. Reasoning Effort & Reasoning Summary (Responses API spec: reasoning: { effort: "...", summary: "auto" })
    if ([self supportsReasoningEffortForModel:model]) {
        NSMutableDictionary *reasoningDict = [NSMutableDictionary dictionary];
        reasoningDict[@"effort"] = [self reasoningEffortApiValueForLevel:self.reasoningEffortLevel];
        if (self.enableReasoningSummary) {
            reasoningDict[@"summary"] = @"auto";
        }
        payloadDict[@"reasoning"] = reasoningDict;
    } else if ([self supportsTemperatureForModel:model]) {
        payloadDict[@"temperature"] = @(self.modelTemperature);
    }

    // 2. Hosted Tools (web_search, code_interpreter)
    NSMutableArray *toolsArray = [NSMutableArray array];
    BOOL effectiveWebSearch = webSearch || self.enableWebSearch;
    if (effectiveWebSearch && [self supportsWebSearchForModel:model]) {
        [toolsArray addObject:@{ @"type": @"web_search" }];
    }
    if (self.enableCodeInterpreter && [self supportsCodeInterpreterForModel:model]) {
        [toolsArray addObject:@{
            @"type": @"code_interpreter",
            @"container": @{ @"type": @"auto" }
        }];
    }
    if (toolsArray.count > 0) {
        payloadDict[@"tools"] = toolsArray;
    }

    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:payloadDict options:0 error:nil];
    NSDictionary *headers = @{
        @"Content-Type": @"application/json; charset=utf-8",
        @"Accept": @"text/event-stream",
        @"Authorization": [NSString stringWithFormat:@"Bearer %@", [self activeBearerToken]]
    };

    [self performCurlRequestToURL:urlString
                           method:@"POST"
                          headers:headers
                             body:bodyData
                       completion:^(NSData *data, NSInteger statusCode, NSError *error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }

        if (statusCode == 400 && (payloadDict[@"tools"] || payloadDict[@"reasoning"])) {
            [payloadDict removeObjectForKey:@"tools"];
            if (payloadDict[@"reasoning"]) {
                // Eğer model none/max gibi uç bir değeri desteklemiyorsa güvenli medium'a veya parametresiz haline düş
                [payloadDict removeObjectForKey:@"reasoning"];
            }
            NSData *fallbackBody = [NSJSONSerialization dataWithJSONObject:payloadDict options:0 error:nil];
            [self performCurlRequestToURL:urlString method:@"POST" headers:headers body:fallbackBody completion:^(NSData *fData, NSInteger fStatus, NSError *fErr) {
                if (fErr) {
                    if (completion) completion(nil, fErr);
                    return;
                }
                [self parseResponsesAPIOutput:fData statusCode:fStatus completion:completion];
            }];
            return;
        }

        [self parseResponsesAPIOutput:data statusCode:statusCode completion:completion];
    }];
}

- (void)parseResponsesAPIOutput:(NSData *)data statusCode:(NSInteger)statusCode completion:(OpenAICompletionHandler)completion {
    if (statusCode != 200) {
        NSString *errMsg = [NSString stringWithFormat:@"HTTP Hatası %ld", (long)statusCode];
        if (data.length > 0) {
            NSDictionary *errJson = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (errJson && errJson[@"error"]) {
                if ([errJson[@"error"] isKindOfClass:[NSDictionary class]] && errJson[@"error"][@"message"]) {
                    errMsg = errJson[@"error"][@"message"];
                } else if ([errJson[@"error"] isKindOfClass:[NSString class]]) {
                    errMsg = errJson[@"error"];
                }
            }
        }
        NSError *apiErr = [NSError errorWithDomain:@"OpenAIClient" code:statusCode userInfo:@{NSLocalizedDescriptionKey: errMsg}];
        if (completion) completion(nil, apiErr);
        return;
    }

    NSString *rawStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    NSMutableString *collectedText = [NSMutableString string];

    NSArray *lines = [rawStr componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([trimmed hasPrefix:@"data:"]) {
            NSString *jsonPart = [[trimmed substringFromIndex:5] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if ([jsonPart isEqualToString:@"[DONE]"] || jsonPart.length == 0) continue;
            NSData *eventData = [jsonPart dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *event = [NSJSONSerialization JSONObjectWithData:eventData options:0 error:nil];
            if ([event isKindOfClass:[NSDictionary class]]) {
                NSString *type = event[@"type"];
                if ([type isEqualToString:@"response.output_text.delta"] && [event[@"delta"] isKindOfClass:[NSString class]]) {
                    [collectedText appendString:event[@"delta"]];
                }
            }
        }
    }

    if (collectedText.length == 0 && data.length > 0) {
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([json isKindOfClass:[NSDictionary class]] && [json[@"output_text"] isKindOfClass:[NSString class]]) {
            [collectedText appendString:json[@"output_text"]];
        }
    }

    if (collectedText.length == 0) {
        [collectedText appendString:@"(Boş yanıt döndü)"];
    }

    if (completion) {
        completion([collectedText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]], nil);
    }
}

// Standard Platform API Key Endpoint (/v1/chat/completions)
- (void)sendMessageViaChatCompletionsAPI:(NSString *)prompt
                                 history:(NSArray *)historyMessages
                               webSearch:(BOOL)webSearch
                              completion:(OpenAICompletionHandler)completion {

    NSString *model = (self.selectedModel.length > 0) ? self.selectedModel : kDefaultModel;
    BOOL isModern = [self isModernOrReasoningModel:model];

    NSString *urlString = @"https://api.openai.com/v1/chat/completions";
    NSMutableArray *messages = [NSMutableArray array];

    NSString *instructionRole = isModern ? @"developer" : @"system";
    NSString *systemPrompt = [self effectiveCombinedSystemInstructionWithWebSearch:webSearch];

    if (systemPrompt.length > 0) {
        [messages addObject:@{
            @"role": instructionRole,
            @"content": systemPrompt
        }];
    }

    // Optimize edilmiş geçmişi al (Sliding window + keyword filter + truncate assistant)
    NSArray *optimizedHistory = [self prepareOptimizedHistoryMessages:historyMessages currentPrompt:prompt];
    [messages addObjectsFromArray:optimizedHistory];

    [messages addObject:@{
        @"role": @"user",
        @"content": prompt ?: @""
    }];

    NSMutableDictionary *payloadDict = [NSMutableDictionary dictionary];
    payloadDict[@"model"] = model;
    payloadDict[@"messages"] = messages;

    if ([self supportsReasoningEffortForModel:model]) {
        payloadDict[@"reasoning_effort"] = [self reasoningEffortApiValueForLevel:self.reasoningEffortLevel];
    } else if ([self supportsTemperatureForModel:model]) {
        payloadDict[@"temperature"] = @(self.modelTemperature);
    }

    NSMutableArray *toolsArray = [NSMutableArray array];
    BOOL effectiveWebSearch = webSearch || self.enableWebSearch;
    if (effectiveWebSearch && [self supportsWebSearchForModel:model]) {
        [toolsArray addObject:@{ @"type": @"web_search" }];
    }
    if (toolsArray.count > 0) {
        payloadDict[@"tools"] = toolsArray;
    }

    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:payloadDict options:0 error:nil];

    NSDictionary *headers = @{
        @"Content-Type": @"application/json; charset=utf-8",
        @"Authorization": [NSString stringWithFormat:@"Bearer %@", self.apiKey]
    };

    [self performCurlRequestToURL:urlString 
                           method:@"POST" 
                          headers:headers 
                             body:bodyData 
                       completion:^(NSData *data, NSInteger statusCode, NSError *error) {
        
        if (error) {
            if (completion) completion(nil, error);
            return;
        }

        if (statusCode == 400 && (payloadDict[@"tools"] || payloadDict[@"reasoning_effort"])) {
            [payloadDict removeObjectForKey:@"tools"];
            [payloadDict removeObjectForKey:@"reasoning_effort"];
            NSData *fallbackData = [NSJSONSerialization dataWithJSONObject:payloadDict options:0 error:nil];
            [self performCurlRequestToURL:urlString method:@"POST" headers:headers body:fallbackData completion:^(NSData *fData, NSInteger fStatus, NSError *fErr) {
                if (fErr) {
                    if (completion) completion(nil, fErr);
                    return;
                }
                [self handleChatCompletionsResponseData:fData statusCode:fStatus completion:completion];
            }];
            return;
        }

        [self handleChatCompletionsResponseData:data statusCode:statusCode completion:completion];
    }];
}

- (void)handleChatCompletionsResponseData:(NSData *)data statusCode:(NSInteger)statusCode completion:(OpenAICompletionHandler)completion {
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
