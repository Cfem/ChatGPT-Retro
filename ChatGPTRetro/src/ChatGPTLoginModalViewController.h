#import <UIKit/UIKit.h>

@protocol ChatGPTLoginModalDelegate <NSObject>
- (void)chatGPTLoginDidComplete;
@end

@interface ChatGPTLoginModalViewController : UIViewController

@property (nonatomic, weak) id<ChatGPTLoginModalDelegate> delegate;

@end
