#import <UIKit/UIKit.h>
#import "ChatSession.h"

@protocol ChatHistorySidebarDelegate <NSObject>
- (void)sidebarDidSelectSession:(ChatSession *)session;
- (void)sidebarDidRequestNewChat;
@optional
- (void)sidebarDidDeleteSession:(ChatSession *)newActiveSession;
@end

@interface ChatHistorySidebarViewController : UIViewController

@property (nonatomic, weak) id<ChatHistorySidebarDelegate> delegate;

- (void)reloadHistory;

@end
