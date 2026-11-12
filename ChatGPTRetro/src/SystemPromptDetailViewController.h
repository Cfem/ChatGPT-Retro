#import <UIKit/UIKit.h>

@protocol SystemPromptDetailDelegate <NSObject>
@optional
- (void)systemPromptDidSaveOrDelete;
@end

@interface SystemPromptDetailViewController : UITableViewController

@property (nonatomic, weak) id<SystemPromptDetailDelegate> delegate;
@property (nonatomic, assign) NSInteger promptIndex; // -1 if new
@property (nonatomic, copy) NSString *promptId;
@property (nonatomic, copy) NSString *initialTitle;
@property (nonatomic, copy) NSString *initialContent;
@property (nonatomic, assign) BOOL isEnabled;

@end
