#import <UIKit/UIKit.h>
#import "ChatSession.h"

@protocol ChatHistorySidebarDelegate <NSObject>
- (void)sidebarDidSelectSession:(ChatSession *)session;
- (void)sidebarDidRequestNewChat;
@end

@interface ChatHistorySidebarViewController : UIViewController

@property (nonatomic, weak) id<ChatHistorySidebarDelegate> delegate;

- (void)reloadHistory;

@end
