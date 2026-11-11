#import <UIKit/UIKit.h>

@protocol QRScannerDelegate <NSObject>
- (void)qrScannerDidScanCode:(NSString *)code;
@end

@interface QRScannerViewController : UIViewController

@property (nonatomic, weak) id<QRScannerDelegate> delegate;

@end
