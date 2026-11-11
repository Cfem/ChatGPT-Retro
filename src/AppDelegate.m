#import "AppDelegate.h"
#import "ChatViewController.h"
#import "GeminiClient.h"

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

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation {
    if (!url) return NO;

    [[NSUserDefaults standardUserDefaults] synchronize];
    NSString *host = [url.host lowercaseString];

    if ([host isEqualToString:@"push-settings"]) {
        [self.chatViewController handlePushSettingsAction];
        return YES;
    } else if ([host isEqualToString:@"start-oauth"]) {
        [self.chatViewController startGoogleOAuthFlow];
        return YES;
    } else if ([host isEqualToString:@"update-models"]) {
        [self.chatViewController refreshModelsAction];
        return YES;
    }

    return YES;
}

@end
