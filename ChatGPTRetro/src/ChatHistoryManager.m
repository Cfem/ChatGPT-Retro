#import "ChatHistoryManager.h"
#import "ChatMessage.h"
#import "LocalizationManager.h"

static NSString *const kSavedSessionsKey = @"ChatGPTRetro_SavedChatSessions_v2";
static const NSInteger kMaxSessionsCount = 10;

@interface ChatHistoryManager ()
@property (nonatomic, strong, readwrite) NSMutableArray *sessions;
@end

@implementation ChatHistoryManager

+ (instancetype)sharedManager {
    static ChatHistoryManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ChatHistoryManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _sessions = [NSMutableArray array];
        [self loadSessions];
        if (_sessions.count == 0) {
            _activeSession = [self createNewSession];
        } else {
            _activeSession = _sessions.firstObject;
        }
    }
    return self;
}

- (void)loadSessions {
    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:kSavedSessionsKey];
    [self.sessions removeAllObjects];
    if (saved && [saved isKindOfClass:[NSArray class]]) {
        for (NSDictionary *dict in saved) {
            ChatSession *s = [ChatSession sessionFromDictionary:dict];
            if (s) {
                [self.sessions addObject:s];
            }
        }
    }
}

- (void)saveSessions {
    // En fazla 10 konuşmayı sakla
    while (self.sessions.count > kMaxSessionsCount) {
        [self.sessions removeLastObject];
    }

    NSMutableArray *toSave = [NSMutableArray array];
    for (ChatSession *s in self.sessions) {
        [toSave addObject:[s dictionaryRepresentation]];
    }

    [[NSUserDefaults standardUserDefaults] setObject:toSave forKey:kSavedSessionsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (ChatSession *)createNewSession {
    ChatSession *newSession = [ChatSession sessionWithTitle:LocalizedString(@"new_chat_title")];
    [self.sessions insertObject:newSession atIndex:0];
    self.activeSession = newSession;
    [self saveSessions];
    return newSession;
}

- (void)deleteSessionAtIndex:(NSInteger)index {
    if (index >= 0 && index < self.sessions.count) {
        ChatSession *s = self.sessions[index];
        [self.sessions removeObjectAtIndex:index];

        if (self.activeSession == s) {
            if (self.sessions.count > 0) {
                self.activeSession = self.sessions.firstObject;
            } else {
                self.activeSession = [self createNewSession];
            }
        }
        [self saveSessions];
    }
}

- (void)switchToSession:(ChatSession *)session {
    if ([self.sessions containsObject:session]) {
        self.activeSession = session;
    }
}

- (void)updateActiveSessionWithUserMessage:(NSString *)text {
    if (!self.activeSession) {
        [self createNewSession];
    }
    self.activeSession.updatedAt = [NSDate date];

    // Eğer oturumun adı varsayılan ise, kullanıcının ilk mesajına göre akıllı başlık ver
    if (([self.activeSession.title isEqualToString:@"Yeni Sohbet"] || 
         [self.activeSession.title isEqualToString:@"New Chat"] ||
         [self.activeSession.title isEqualToString:LocalizedString(@"new_chat_title")]) && text.length > 0) {
        NSString *clean = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (clean.length > 28) {
            clean = [[clean substringToIndex:28] stringByAppendingString:@"…"];
        }
        self.activeSession.title = clean;
    }

    // Aktif oturumu en tepeye taşı
    if ([self.sessions containsObject:self.activeSession]) {
        [self.sessions removeObject:self.activeSession];
        [self.sessions insertObject:self.activeSession atIndex:0];
    }

    [self saveSessions];
}

@end
