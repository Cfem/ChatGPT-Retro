#import <Foundation/Foundation.h>
#import "ChatSession.h"

@interface ChatHistoryManager : NSObject

@property (nonatomic, strong, readonly) NSMutableArray *sessions; // Array of ChatSession, max 10
@property (nonatomic, strong) ChatSession *activeSession;

+ (instancetype)sharedManager;

- (void)loadSessions;
- (void)saveSessions;

- (ChatSession *)createNewSession;
- (void)deleteSessionAtIndex:(NSInteger)index;
- (void)switchToSession:(ChatSession *)session;
- (void)updateActiveSessionWithUserMessage:(NSString *)text;

@end
