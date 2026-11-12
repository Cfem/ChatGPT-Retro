#import <UIKit/UIKit.h>

@protocol ModelSelectionDelegate <NSObject>
- (void)modelSelectionDidSelectModel:(NSString *)model;
@end

@interface ModelSelectionViewController : UITableViewController

@property (nonatomic, weak) id<ModelSelectionDelegate> delegate;

@end
