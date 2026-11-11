#import <UIKit/UIKit.h>

@interface ChatViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>

- (void)handlePushSettingsAction;
- (void)startGoogleOAuthFlow;
- (void)refreshModelsAction;

@end
