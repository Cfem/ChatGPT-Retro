#import <Foundation/Foundation.h>

typedef void (^GeminiCompletionHandler)(NSString *response, NSError *error);
typedef void (^GeminiStreamChunkHandler)(NSString *chunk, NSString *accumulatedText, BOOL isFinished, NSError *error);
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

// SSE (Server-Sent Events) ile parça parça canlı akış yöntemi
- (void)streamMessage:(NSString *)prompt 
              history:(NSArray *)historyMessages 
         chunkHandler:(GeminiStreamChunkHandler)chunkHandler;

@end
