#import <Foundation/Foundation.h>

typedef void (^GeminiCompletionHandler)(NSString *response, NSError *error);
typedef void (^GeminiModelsHandler)(NSArray *models, NSError *error);

@interface GeminiClient : NSObject

@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, copy) NSString *selectedModel;
@property (nonatomic, strong) NSArray *cachedModels;

+ (instancetype)sharedClient;

- (void)saveApiKey:(NSString *)apiKey;
- (void)saveSelectedModel:(NSString *)model;
- (BOOL)hasApiKey;

// Canlı modelleri Google AI Studio'dan çeker (generateContent destekleyenleri filtreler)
- (void)fetchAvailableModelsWithCompletion:(GeminiModelsHandler)completion;

// Ham request şablonunu Settings.bundle / NSUserDefaults üzerinden okur veya günceller
- (NSString *)customRequestPayloadTemplate;

- (void)sendMessage:(NSString *)prompt 
            history:(NSArray *)historyMessages 
         completion:(GeminiCompletionHandler)completion;

@end
