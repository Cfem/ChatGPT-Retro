#import "AppDelegate.h"
#import "ChatViewController.h"

@interface AppDelegate ()
@property (nonatomic, strong) ChatViewController *chatViewController;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.backgroundColor = [UIColor whiteColor];

    _chatViewController = [[ChatViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:_chatViewController];
    
    nav.navigationBar.translucent = YES;
    nav.navigationBar.tintColor = [UIColor colorWithRed:0.0 green:0.478 blue:1.0 alpha:1.0];
    
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
