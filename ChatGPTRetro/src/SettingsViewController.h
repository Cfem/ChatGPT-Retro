#import <UIKit/UIKit.h>

@protocol SettingsViewControllerDelegate <NSObject>
- (void)settingsDidUpdate;
@optional
- (void)settingsDidRequestClose;
@end

@interface SettingsViewController : UITableViewController <UITextFieldDelegate>

@property (nonatomic, weak) id<SettingsViewControllerDelegate> delegate;

@end
