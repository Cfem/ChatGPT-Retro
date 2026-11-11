#import "AppDelegate.h"
#import "ChatViewController.h"
#import "OpenAIClient.h"

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
    nav.navigationBar.tintColor = [UIColor colorWithRed:16.0/255.0 green:163.0/255.0 blue:127.0/255.0 alpha:1.0];
    
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    return YES;
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation {
    if (!url) return NO;
    NSString *urlString = [url absoluteString];
    if ([urlString hasPrefix:@"chatgptretro://"] && [urlString containsString:@"code="]) {
        // Eğer 127.0.0.1 loopback henüz tüketmediyse URL şeması üzerinden yakala
        if (![[OpenAIClient sharedClient] isChatGPTAccountLinked]) {
            [[OpenAIClient sharedClient] handleIncomingCallbackURLString:urlString completion:nil];
        }
        return YES;
    }
    return NO;
}

@end
