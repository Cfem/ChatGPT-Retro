#import <Foundation/Foundation.h>

typedef void (^OpenAICompletionHandler)(NSString *response, NSError *error);
typedef void (^OpenAIModelsHandler)(NSArray *models, NSError *error);

@interface OpenAIClient : NSObject

@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, copy) NSString *selectedModel;

+ (instancetype)sharedClient;

- (void)saveApiKey:(NSString *)apiKey;
- (void)saveSelectedModel:(NSString *)model;

- (BOOL)isAuthenticated;

- (void)fetchAvailableModelsWithCompletion:(OpenAIModelsHandler)completion;

- (void)sendMessage:(NSString *)prompt 
            history:(NSArray *)historyMessages 
          webSearch:(BOOL)webSearch
         completion:(OpenAICompletionHandler)completion;

@end
