#import <UIKit/UIKit.h>

@protocol OAuthModalDelegate <NSObject>
- (void)oauthModalDidCompleteLogin;
@end

@interface OAuthModalViewController : UIViewController

@property (nonatomic, weak) id<OAuthModalDelegate> delegate;

@end
