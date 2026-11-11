#import "OAuthModalViewController.h"
#import "GeminiClient.h"
#import "QRScannerViewController.h"
#import <CoreImage/CoreImage.h>

@interface OAuthModalViewController () <QRScannerDelegate, UITextFieldDelegate>

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIImageView *qrImageView;
@property (nonatomic, strong) UITextField *codeField;
@property (nonatomic, strong) UIButton *scanButton;
@property (nonatomic, strong) UIButton *submitButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;

@property (nonatomic, copy) NSString *authURLString;

@end

@implementation OAuthModalViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Google Hesabı Bağla";
    self.view.backgroundColor = [UIColor groupTableViewBackgroundColor];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Kapat"
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(closeAction)];

    _authURLString = [[GeminiClient sharedClient] standardOAuthAuthorizationURL];

    [self setupUI];
}

- (void)setupUI {
    _scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    _scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:_scrollView];

    CGFloat w = self.view.bounds.size.width;
    CGFloat pad = 20.0;
    CGFloat contentW = w - (pad * 2);

    // 1. Bilgi Açıklaması
    UILabel *descLabel = [[UILabel alloc] initWithFrame:CGRectMake(pad, 15, contentW, 55)];
    descLabel.numberOfLines = 0;
    descLabel.text = @"1. Telefonunuzun kamerasıyla aşağıdaki QR kodu okutun ve Google hesabınızla sadece Gemini için izin verin:";
    descLabel.font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:14.0];
    descLabel.textColor = [UIColor darkGrayColor];
    [_scrollView addSubview:descLabel];

    // 2. QR Kod Görseli
    CGFloat qrSize = 180.0;
    _qrImageView = [[UIImageView alloc] initWithFrame:CGRectMake((w - qrSize)/2, CGRectGetMaxY(descLabel.frame) + 10, qrSize, qrSize)];
    _qrImageView.backgroundColor = [UIColor whiteColor];
    _qrImageView.layer.borderColor = [UIColor colorWithWhite:0.8 alpha:1.0].CGColor;
    _qrImageView.layer.borderWidth = 1.0;
    _qrImageView.layer.cornerRadius = 8.0;
    _qrImageView.layer.masksToBounds = YES;
    _qrImageView.image = [self generateQRCodeImageFromString:_authURLString size:qrSize];
    [_scrollView addSubview:_qrImageView];

    // 3. Link Kopyalama Butonu
    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyBtn.frame = CGRectMake(pad, CGRectGetMaxY(_qrImageView.frame) + 10, contentW, 30);
    [copyBtn setTitle:@"🔗 Giriş Linkini Panoya Kopyala" forState:UIControlStateNormal];
    copyBtn.titleLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:14.0];
    [copyBtn addTarget:self action:@selector(copyLinkAction) forControlEvents:UIControlEventTouchUpInside];
    [_scrollView addSubview:copyBtn];

    // 4. İkinci Adım Açıklaması
    UILabel *step2Label = [[UILabel alloc] initWithFrame:CGRectMake(pad, CGRectGetMaxY(copyBtn.frame) + 15, contentW, 55)];
    step2Label.numberOfLines = 0;
    step2Label.text = @"2. Telefonda onaylayınca tarayıcının adres çubuğunda çıkan linki buraya yapıştırın veya kamerayla okutun:";
    step2Label.font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:14.0];
    step2Label.textColor = [UIColor darkGrayColor];
    [_scrollView addSubview:step2Label];

    // 5. Kod Giriş Kutusu
    _codeField = [[UITextField alloc] initWithFrame:CGRectMake(pad, CGRectGetMaxY(step2Label.frame) + 8, contentW, 40)];
    _codeField.backgroundColor = [UIColor whiteColor];
    _codeField.placeholder = @"Doğrulama kodunu veya yönlendirme linkini yapıştırın";
    _codeField.font = [UIFont fontWithName:@"HelveticaNeue" size:13.0];
    _codeField.layer.borderColor = [UIColor colorWithWhite:0.75 alpha:1.0].CGColor;
    _codeField.layer.borderWidth = 1.0;
    _codeField.layer.cornerRadius = 6.0;
    _codeField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 40)];
    _codeField.leftViewMode = UITextFieldViewModeAlways;
    _codeField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _codeField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _codeField.autocorrectionType = UITextAutocorrectionTypeNo;
    _codeField.delegate = self;
    [_scrollView addSubview:_codeField];

    // 6. Kamera Butonu
    _scanButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _scanButton.frame = CGRectMake(pad, CGRectGetMaxY(_codeField.frame) + 12, (contentW - 10) / 2, 44);
    _scanButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.9 alpha:1.0];
    [_scanButton setTitle:@"📷 Kamerayla Tara" forState:UIControlStateNormal];
    [_scanButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _scanButton.titleLabel.font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:15.0];
    _scanButton.layer.cornerRadius = 8.0;
    [_scanButton addTarget:self action:@selector(openCameraAction) forControlEvents:UIControlEventTouchUpInside];
    [_scrollView addSubview:_scanButton];

    // 7. Onayla Butonu
    _submitButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _submitButton.frame = CGRectMake(CGRectGetMaxX(_scanButton.frame) + 10, CGRectGetMaxY(_codeField.frame) + 12, (contentW - 10) / 2, 44);
    _submitButton.backgroundColor = [UIColor colorWithRed:0.1 green:0.65 blue:0.2 alpha:1.0];
    [_submitButton setTitle:@"✓ Onayla ve Bağla" forState:UIControlStateNormal];
    [_submitButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _submitButton.titleLabel.font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:15.0];
    _submitButton.layer.cornerRadius = 8.0;
    [_submitButton addTarget:self action:@selector(submitCodeAction) forControlEvents:UIControlEventTouchUpInside];
    [_scrollView addSubview:_submitButton];

    // 8. Spinner
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _spinner.center = CGPointMake(w/2, CGRectGetMaxY(_submitButton.frame) + 25);
    _spinner.hidesWhenStopped = YES;
    [_scrollView addSubview:_spinner];

    _scrollView.contentSize = CGSizeMake(w, CGRectGetMaxY(_submitButton.frame) + 60);
}

#pragma mark - QR Code Generator (CoreImage)

- (UIImage *)generateQRCodeImageFromString:(NSString *)string size:(CGFloat)size {
    if (!string || string.length == 0) return nil;

    NSData *stringData = [string dataUsingEncoding:NSUTF8StringEncoding];
    CIFilter *qrFilter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
    [qrFilter setValue:stringData forKey:@"inputMessage"];
    [qrFilter setValue:@"M" forKey:@"inputCorrectionLevel"];

    CIImage *ciImage = qrFilter.outputImage;
    if (!ciImage) return nil;

    CGRect extent = CGRectIntegral(ciImage.extent);
    CGFloat scale = MIN(size / CGRectGetWidth(extent), size / CGRectGetHeight(extent));

    size_t width = CGRectGetWidth(extent) * scale;
    size_t height = CGRectGetHeight(extent) * scale;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceGray();
    CGContextRef bitmapRef = CGBitmapContextCreate(nil, width, height, 8, 0, cs, (CGBitmapInfo)kCGImageAlphaNone);
    CIContext *context = [CIContext contextWithOptions:nil];
    CGImageRef bitmapImage = [context createCGImage:ciImage fromRect:extent];
    CGContextSetInterpolationQuality(bitmapRef, kCGInterpolationNone);
    CGContextScaleCTM(bitmapRef, scale, scale);
    CGContextDrawImage(bitmapRef, extent, bitmapImage);

    CGImageRef scaledImage = CGBitmapContextCreateImage(bitmapRef);
    CGContextRelease(bitmapRef);
    CGImageRelease(bitmapImage);
    CGColorSpaceRelease(cs);

    UIImage *result = [UIImage imageWithCGImage:scaledImage];
    CGImageRelease(scaledImage);
    return result;
}

#pragma mark - Actions

- (void)closeAction {
    [self.view endEditing:YES];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)copyLinkAction {
    [UIPasteboard generalPasteboard].string = self.authURLString;
    UIAlertController *copied = [UIAlertController alertControllerWithTitle:@"Kopyalandı"
                                                                    message:@"Giriş linki panoya kopyalandı! Telefonunuza veya tarayıcınıza yapıştırabilirsiniz."
                                                             preferredStyle:UIAlertControllerStyleAlert];
    [copied addAction:[UIAlertAction actionWithTitle:@"Tamam" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:copied animated:YES completion:nil];
}

- (void)openCameraAction {
    [self.view endEditing:YES];
    QRScannerViewController *scanner = [[QRScannerViewController alloc] init];
    scanner.delegate = self;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:scanner];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)submitCodeAction {
    [self.view endEditing:YES];
    NSString *input = self.codeField.text ?: @"";
    if (input.length == 0) {
        UIAlertController *err = [UIAlertController alertControllerWithTitle:@"Kod Gerekli"
                                                                     message:@"Lütfen tarayıcıdan aldığınız doğrulama kodunu veya linki yapıştırınız."
                                                              preferredStyle:UIAlertControllerStyleAlert];
        [err addAction:[UIAlertAction actionWithTitle:@"Tamam" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:err animated:YES completion:nil];
        return;
    }

    [self.spinner startAnimating];
    self.submitButton.enabled = NO;
    self.scanButton.enabled = NO;

    [[GeminiClient sharedClient] exchangeAuthCode:input completion:^(BOOL success, NSError *error) {
        [self.spinner stopAnimating];
        self.submitButton.enabled = YES;
        self.scanButton.enabled = YES;

        if (success) {
            UIAlertController *done = [UIAlertController alertControllerWithTitle:@"Giriş Başarılı!"
                                                                          message:@"Google hesabınız başarıyla bağlandı! Artık doğrudan kendi hesabınızla kotasız sohbet edebilirsiniz."
                                                                   preferredStyle:UIAlertControllerStyleAlert];
            [done addAction:[UIAlertAction actionWithTitle:@"Harika" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                if ([self.delegate respondsToSelector:@selector(oauthModalDidCompleteLogin)]) {
                    [self.delegate oauthModalDidCompleteLogin];
                }
                [self dismissViewControllerAnimated:YES completion:nil];
            }]];
            [self presentViewController:done animated:YES completion:nil];
        } else {
            UIAlertController *fail = [UIAlertController alertControllerWithTitle:@"Giriş Başarısız"
                                                                          message:error.localizedDescription
                                                                   preferredStyle:UIAlertControllerStyleAlert];
            [fail addAction:[UIAlertAction actionWithTitle:@"Tekrar Dene" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:fail animated:YES completion:nil];
        }
    }];
}

#pragma mark - QRScannerDelegate

- (void)qrScannerDidScanCode:(NSString *)code {
    self.codeField.text = code;
    [self submitCodeAction];
}

@end
