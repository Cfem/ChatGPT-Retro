#import <UIKit/UIKit.h>

@protocol SettingsViewControllerDelegate <NSObject>
- (void)settingsDidUpdate;
@end

@interface SettingsViewController : UITableViewController <UITextFieldDelegate>

@property (nonatomic, weak) id<SettingsViewControllerDelegate> delegate;

@end
