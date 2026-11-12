#import <UIKit/UIKit.h>

@protocol AccountLoginDelegate <NSObject>
- (void)accountLoginStateDidChange;
@end

@interface AccountLoginViewController : UITableViewController

@property (nonatomic, weak) id<AccountLoginDelegate> delegate;

@end
