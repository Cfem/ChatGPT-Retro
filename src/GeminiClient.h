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

- (void)fetchAvailableModelsWithCompletion:(GeminiModelsHandler)completion;
- (NSString *)customRequestPayloadTemplate;

// Yanıtı komple bekleyip tek seferde getiren kararlı metot (Kaynaklar dahil)
- (void)sendMessage:(NSString *)prompt 
            history:(NSArray *)historyMessages 
         completion:(GeminiCompletionHandler)completion;

@end
