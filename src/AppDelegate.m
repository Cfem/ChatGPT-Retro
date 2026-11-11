#import "AppDelegate.h"
#import "ChatViewController.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.backgroundColor = [UIColor whiteColor];

    ChatViewController *chatVC = [[ChatViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:chatVC];
    
    // iOS 8 Tasarım Özellikleri: Temiz Navigation Bar
    nav.navigationBar.translucent = YES;
    nav.navigationBar.tintColor = [UIColor colorWithRed:0.0 green:0.478 blue:1.0 alpha:1.0]; // iOS 8 System Blue
    
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
