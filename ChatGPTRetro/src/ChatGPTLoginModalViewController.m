#import "ChatGPTLoginModalViewController.h"
#import "OpenAIClient.h"
#import <CoreImage/CoreImage.h>

@interface ChatGPTLoginModalViewController () <UITextFieldDelegate>

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIImageView *qrImageView;
@property (nonatomic, strong) UITextField *urlField;
@property (nonatomic, strong) UIButton *pasteAndSubmitButton;
@property (nonatomic, strong) UIButton *openSafariDirectButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;

@property (nonatomic, copy) NSString *authURLString;

@end

@implementation ChatGPTLoginModalViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"ChatGPT ile Giriş Yap";
    self.view.backgroundColor = [UIColor groupTableViewBackgroundColor];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Kapat"
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(closeAction)];

    // Prepare auth parameters, code verifier, and start local loopback listener
    _authURLString = [[OpenAIClient sharedClient] prepareOAuthAuthorizationURL];

    [self setupUI];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(authStateDidChange:)
                                                 name:kChatGPTAuthStateDidChangeNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)authStateDidChange:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([[OpenAIClient sharedClient] isChatGPTAccountLinked]) {
            [self.spinner stopAnimating];
            if ([self.delegate respondsToSelector:@selector(chatGPTLoginDidComplete)]) {
                [self.delegate chatGPTLoginDidComplete];
            }
            [self dismissViewControllerAnimated:YES completion:nil];
        }
    });
}

- (void)closeAction {
    [self dismissViewControllerAnimated:YES completion:nil];
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
    UILabel *descLabel = [[UILabel alloc] initWithFrame:CGRectMake(pad, 15, contentW, 48)];
    descLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    descLabel.numberOfLines = 0;
    descLabel.text = @"1. iPhone veya modern telefonunuzla aşağıdaki QR kodu okutun ve ChatGPT Plus/Pro hesabınızla giriş yapın:";
    descLabel.font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:14.0];
    descLabel.textColor = [UIColor darkGrayColor];
    [_scrollView addSubview:descLabel];

    // 2. QR Kod Görseli
    CGFloat qrSize = 200.0;
    _qrImageView = [[UIImageView alloc] initWithFrame:CGRectMake((w - qrSize)/2, CGRectGetMaxY(descLabel.frame) + 10, qrSize, qrSize)];
    _qrImageView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    _qrImageView.backgroundColor = [UIColor whiteColor];
    _qrImageView.layer.borderColor = [UIColor colorWithWhite:0.8 alpha:1.0].CGColor;
    _qrImageView.layer.borderWidth = 1.0;
    _qrImageView.layer.cornerRadius = 8.0;
    _qrImageView.layer.masksToBounds = YES;
    _qrImageView.image = [self generateQRCodeImageFromString:_authURLString size:qrSize];
    [_scrollView addSubview:_qrImageView];

    // 3. Giriş Linkini Kopyala Butonu
    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyBtn.frame = CGRectMake(pad, CGRectGetMaxY(_qrImageView.frame) + 10, contentW, 30);
    copyBtn.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [copyBtn setTitle:@"Giriş Linkini Panoya Kopyala" forState:UIControlStateNormal];
    copyBtn.titleLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:14.0];
    [copyBtn setTitleColor:[UIColor colorWithRed:16.0/255.0 green:163.0/255.0 blue:127.0/255.0 alpha:1.0] forState:UIControlStateNormal];
    [copyBtn addTarget:self action:@selector(copyLinkAction) forControlEvents:UIControlEventTouchUpInside];
    [_scrollView addSubview:copyBtn];

    // 4. İkinci Adım Açıklaması
    UILabel *step2Label = [[UILabel alloc] initWithFrame:CGRectMake(pad, CGRectGetMaxY(copyBtn.frame) + 14, contentW, 60)];
    step2Label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    step2Label.numberOfLines = 0;
    step2Label.text = @"2. Telefonda onaylayınca tarayıcının adres çubuğunda kalan yönlendirme linkini kopyalayıp (AirDrop veya Pano ile) buraya yapıştırın:";
    step2Label.font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:14.0];
    step2Label.textColor = [UIColor darkGrayColor];
    [_scrollView addSubview:step2Label];

    // 5. Kod / URL Giriş Kutusu
    _urlField = [[UITextField alloc] initWithFrame:CGRectMake(pad, CGRectGetMaxY(step2Label.frame) + 8, contentW, 40)];
    _urlField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _urlField.backgroundColor = [UIColor whiteColor];
    _urlField.placeholder = @"http://127.0.0.1:8787/auth/callback?code=... veya sadece kod";
    _urlField.font = [UIFont fontWithName:@"HelveticaNeue" size:13.0];
    _urlField.layer.borderColor = [UIColor colorWithWhite:0.75 alpha:1.0].CGColor;
    _urlField.layer.borderWidth = 1.0;
    _urlField.layer.cornerRadius = 6.0;
    _urlField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 40)];
    _urlField.leftViewMode = UITextFieldViewModeAlways;
    _urlField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _urlField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _urlField.autocorrectionType = UITextAutocorrectionTypeNo;
    _urlField.delegate = self;
    [_scrollView addSubview:_urlField];

    // 6. Yapıştır ve Onayla Butonu (Yeşil)
    _pasteAndSubmitButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _pasteAndSubmitButton.frame = CGRectMake(pad, CGRectGetMaxY(_urlField.frame) + 14, contentW, 44);
    _pasteAndSubmitButton.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _pasteAndSubmitButton.backgroundColor = [UIColor colorWithRed:16.0/255.0 green:163.0/255.0 blue:127.0/255.0 alpha:1.0];
    [_pasteAndSubmitButton setTitle:@"Panodan Yapıştır ve Girişi Tamamla" forState:UIControlStateNormal];
    [_pasteAndSubmitButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _pasteAndSubmitButton.titleLabel.font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:15.0];
    _pasteAndSubmitButton.layer.cornerRadius = 8.0;
    [_pasteAndSubmitButton addTarget:self action:@selector(pasteAndSubmitAction) forControlEvents:UIControlEventTouchUpInside];
    [_scrollView addSubview:_pasteAndSubmitButton];

    // 7. Doğrudan iPad Safari ile Dene Butonu (Alternatif)
    _openSafariDirectButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _openSafariDirectButton.frame = CGRectMake(pad, CGRectGetMaxY(_pasteAndSubmitButton.frame) + 12, contentW, 36);
    _openSafariDirectButton.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [_openSafariDirectButton setTitle:@"iPad Safari'sinde Açmayı Dene (Doğrudan)" forState:UIControlStateNormal];
    [_openSafariDirectButton setTitleColor:[UIColor colorWithWhite:0.35 alpha:1.0] forState:UIControlStateNormal];
    _openSafariDirectButton.titleLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:13.0];
    [_openSafariDirectButton addTarget:self action:@selector(openSafariDirectAction) forControlEvents:UIControlEventTouchUpInside];
    [_scrollView addSubview:_openSafariDirectButton];

    // 8. Spinner
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _spinner.frame = CGRectMake((w - 30)/2, CGRectGetMaxY(_openSafariDirectButton.frame) + 10, 30, 30);
    _spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    _spinner.hidesWhenStopped = YES;
    [_scrollView addSubview:_spinner];

    _scrollView.contentSize = CGSizeMake(w, CGRectGetMaxY(_spinner.frame) + 30);
}

- (void)copyLinkAction {
    if (self.authURLString.length > 0) {
        [UIPasteboard generalPasteboard].string = self.authURLString;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Kopyalandı"
                                                                       message:@"Giriş linki panoya kopyalandı. iPhone'unuza aktarabilirsiniz."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Tamam" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)openSafariDirectAction {
    if (self.authURLString.length > 0) {
        NSURL *url = [NSURL URLWithString:self.authURLString];
        if (url) {
            [[UIApplication sharedApplication] openURL:url];
        }
    }
}

- (void)pasteAndSubmitAction {
    NSString *clipboardText = [UIPasteboard generalPasteboard].string;
    if (clipboardText.length > 0) {
        self.urlField.text = clipboardText;
    }

    NSString *inputText = [self.urlField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (inputText.length == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Giriş Gerekli"
                                                                       message:@"Lütfen telefonda onay sonrası tarayıcının adres çubuğunda kalan linki yapıştırın."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Tamam" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    [self submitCallbackText:inputText];
}

- (void)submitCallbackText:(NSString *)callbackText {
    [self.spinner startAnimating];
    self.pasteAndSubmitButton.enabled = NO;

    [[OpenAIClient sharedClient] handleIncomingCallbackURLString:callbackText completion:^(BOOL success, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimating];
            self.pasteAndSubmitButton.enabled = YES;

            if (success) {
                if ([self.delegate respondsToSelector:@selector(chatGPTLoginDidComplete)]) {
                    [self.delegate chatGPTLoginDidComplete];
                }
                [self dismissViewControllerAnimated:YES completion:nil];
            } else {
                NSString *msg = error.localizedDescription ?: @"Giriş doğrulanamadı. Lütfen linki kontrol edip tekrar deneyin.";
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Bağlantı Hatası"
                                                                               message:msg
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"Tamam" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }
        });
    }];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    [self pasteAndSubmitAction];
    return YES;
}

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

@end
