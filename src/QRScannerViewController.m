#import "QRScannerViewController.h"
#import <AVFoundation/AVFoundation.h>

@interface QRScannerViewController () <AVCaptureMetadataOutputObjectsDelegate>

@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, strong) UIView *targetFrameView;
@property (nonatomic, assign) BOOL hasScanned;

@end

@implementation QRScannerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"QR Kodu Tara";
    self.view.backgroundColor = [UIColor blackColor];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Vazgeç"
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(cancelAction)];

    [self setupCamera];
    [self setupOverlay];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.hasScanned = NO;
    if (self.captureSession && !self.captureSession.isRunning) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self.captureSession startRunning];
        });
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.captureSession && self.captureSession.isRunning) {
        [self.captureSession stopRunning];
    }
}

- (void)setupCamera {
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (!device) {
        UILabel *errorLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 200, self.view.bounds.size.width - 40, 60)];
        errorLabel.text = @"Kamera donanımı bulunamadı.";
        errorLabel.textColor = [UIColor whiteColor];
        errorLabel.textAlignment = NSTextAlignmentCenter;
        [self.view addSubview:errorLabel];
        return;
    }

    NSError *error = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if (error || !input) {
        return;
    }

    _captureSession = [[AVCaptureSession alloc] init];
    if ([_captureSession canAddInput:input]) {
        [_captureSession addInput:input];
    }

    AVCaptureMetadataOutput *metadataOutput = [[AVCaptureMetadataOutput alloc] init];
    if ([_captureSession canAddOutput:metadataOutput]) {
        [_captureSession addOutput:metadataOutput];
        [metadataOutput setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
        if ([metadataOutput.availableMetadataObjectTypes containsObject:AVMetadataObjectTypeQRCode]) {
            [metadataOutput setMetadataObjectTypes:@[AVMetadataObjectTypeQRCode]];
        }
    }

    _previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:_captureSession];
    _previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    _previewLayer.frame = self.view.layer.bounds;
    [self.view.layer addSublayer:_previewLayer];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.previewLayer) {
        self.previewLayer.frame = self.view.layer.bounds;
    }
    if (self.targetFrameView) {
        CGFloat s = MIN(self.view.bounds.size.width, self.view.bounds.size.height) * 0.65;
        self.targetFrameView.frame = CGRectMake((self.view.bounds.size.width - s)/2,
                                                (self.view.bounds.size.height - s)/2,
                                                s, s);
    }
}

- (void)setupOverlay {
    CGFloat s = MIN(self.view.bounds.size.width, self.view.bounds.size.height) * 0.65;
    _targetFrameView = [[UIView alloc] initWithFrame:CGRectMake((self.view.bounds.size.width - s)/2,
                                                                (self.view.bounds.size.height - s)/2,
                                                                s, s)];
    _targetFrameView.layer.borderColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.2 alpha:1.0].CGColor;
    _targetFrameView.layer.borderWidth = 3.0;
    _targetFrameView.layer.cornerRadius = 12.0;
    _targetFrameView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_targetFrameView];

    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(20, self.view.bounds.size.height - 80, self.view.bounds.size.width - 40, 40)];
    hint.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
    hint.text = @"API Anahtarınızı (AIza...) içeren QR kodu çerçeveye tutun";
    hint.textColor = [UIColor whiteColor];
    hint.textAlignment = NSTextAlignmentCenter;
    hint.font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:14.0];
    hint.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.6];
    hint.layer.cornerRadius = 8.0;
    hint.layer.masksToBounds = YES;
    [self.view addSubview:hint];
}

- (void)cancelAction {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - AVCaptureMetadataOutputObjectsDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputMetadataObjects:(NSArray *)metadataObjects fromConnection:(AVCaptureConnection *)connection {
    if (self.hasScanned) return;

    for (AVMetadataObject *metadata in metadataObjects) {
        if ([metadata.type isEqualToString:AVMetadataObjectTypeQRCode]) {
            AVMetadataMachineReadableCodeObject *codeObj = (AVMetadataMachineReadableCodeObject *)metadata;
            NSString *val = codeObj.stringValue;
            if (val && val.length > 0) {
                self.hasScanned = YES;
                [self.captureSession stopRunning];
                [self dismissViewControllerAnimated:YES completion:^{
                    if ([self.delegate respondsToSelector:@selector(qrScannerDidScanCode:)]) {
                        [self.delegate qrScannerDidScanCode:val];
                    }
                }];
                break;
            }
        }
    }
}

@end
