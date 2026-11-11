#import "ChatViewController.h"
#import "ChatBubbleCell.h"
#import "ChatMessage.h"
#import "GeminiClient.h"

@interface ChatViewController ()

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *messages;

// Giriş çubuğu bileşenleri
@property (nonatomic, strong) UIView *inputContainerView;
@property (nonatomic, strong) UIButton *webSearchButton;
@property (nonatomic, strong) UITextField *inputTextField;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;

@property (nonatomic, assign) CGFloat keyboardHeight;
@property (nonatomic, assign) BOOL isSending;
@property (nonatomic, assign) BOOL isWebSearchActive;
@property (nonatomic, strong) UIAlertController *deviceAuthAlert;

@end

@implementation ChatViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Gemini";
    self.view.backgroundColor = [UIColor colorWithRed:0.96 green:0.96 blue:0.98 alpha:1.0];

    _messages = [NSMutableArray array];

    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"enable_google_search"] == nil) {
        _isWebSearchActive = YES;
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"enable_google_search"];
    } else {
        _isWebSearchActive = [[NSUserDefaults standardUserDefaults] boolForKey:@"enable_google_search"];
    }

    [self setupNavigationItems];
    [self setupTableView];
    [self setupInputBar];
    [self registerKeyboardNotifications];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(userDefaultsDidChange:)
                                                 name:NSUserDefaultsDidChangeNotification
                                               object:nil];

    [self addWelcomeMessageIfNeeded];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateTitleWithModel];
}

- (void)userDefaultsDidChange:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateTitleWithModel];
    });
}

- (void)updateTitleWithModel {
    NSString *model = [GeminiClient sharedClient].selectedModel;
    NSString *authStatus = @"";
    if ([GeminiClient sharedClient].isGoogleAccountLinked) {
        authStatus = @" [Google Hesabı]";
    } else if ([GeminiClient sharedClient].apiKey.length > 5) {
        authStatus = @" [API Key]";
    }
    self.navigationItem.prompt = [NSString stringWithFormat:@"Model: %@%@ (v2.2)", model ?: @"gemini-1.5-flash", authStatus];
}

- (void)setupNavigationItems {
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Temizle"
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(clearChatTapped)];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"İşlemler / Ayarlar"
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self
                                                                             action:@selector(openSettingsTapped)];
}

- (void)openSettingsTapped {
    [[NSUserDefaults standardUserDefaults] synchronize];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Gemini İşlemleri"
                                                                   message:@"Google Hesabı bağlantısı ve canlı model listesi:"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    if ([GeminiClient sharedClient].isGoogleAccountLinked) {
        NSString *email = [GeminiClient sharedClient].userEmail.length > 0 ? [GeminiClient sharedClient].userEmail : @"Bağlı Hesap";
        [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"🔴 Google Hesabından Çıkış Yap (%@)", email]
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(UIAlertAction *action) {
            [[GeminiClient sharedClient] signOutGoogleAccount];
            [self updateTitleWithModel];
            [self showAlertWithTitle:@"Çıkış Yapıldı" message:@"Google hesabınızın bağlantısı kaldırıldı."];
        }]];
    } else {
        [sheet addAction:[UIAlertAction actionWithTitle:@"🔑 Google Hesabı Bağla (OAuth)"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            [self startGoogleOAuthFlow];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"🔄 Modelleri Canlı Yenile (Refresh Models)"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [self refreshModelsAction];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"📥 Ayarları Senkronize Et / Kontrol Et"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [self handlePushSettingsAction];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Vazgeç" style:UIAlertActionStyleCancel handler:nil]];

    sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - Custom URL Scheme Action Handlers

- (void)handlePushSettingsAction {
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self updateTitleWithModel];

    NSString *msg = [NSString stringWithFormat:@"Ayarlar başarıyla uygulamaya aktarıldı!\n\n• Client ID: %lu karakter\n• Client Secret: %lu karakter\n• API Key: %lu karakter\n• Model: %@",
                     (unsigned long)[GeminiClient sharedClient].oauthClientId.length,
                     (unsigned long)[GeminiClient sharedClient].oauthClientSecret.length,
                     (unsigned long)[GeminiClient sharedClient].apiKey.length,
                     [GeminiClient sharedClient].selectedModel];

    [self showAlertWithTitle:@"Ayarlar Kaydedildi" message:msg];
}

- (void)startGoogleOAuthFlow {
    [[NSUserDefaults standardUserDefaults] synchronize];

    if (![[GeminiClient sharedClient] hasOAuthCredentials]) {
        NSString *msg = [NSString stringWithFormat:@"Client ID (%lu karakter) veya Secret (%lu karakter) eksik.\n\nLütfen iPad Ayarlar uygulamasından Client ID ve Secret'ı girip altındaki '📥 Ayarları Uygulamaya Kaydet / Aktar' butonuna dokunun.",
                         (unsigned long)[GeminiClient sharedClient].oauthClientId.length,
                         (unsigned long)[GeminiClient sharedClient].oauthClientSecret.length];
        [self showAlertWithTitle:@"Client ID / Secret Eksik" message:msg];
        return;
    }

    UIAlertController *loading = [UIAlertController alertControllerWithTitle:@"Google Bağlantısı"
                                                                     message:@"Cihaz kodu alınıyor, lütfen bekleyin..."
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loading animated:YES completion:nil];

    [[GeminiClient sharedClient] startDeviceAuthFlowWithCompletion:^(NSString *userCode, NSString *verificationUrl, NSString *deviceCode, NSError *error) {
        [loading dismissViewControllerAnimated:YES completion:^{
            if (error) {
                [self showAlertWithTitle:@"Bağlantı Hatası" message:error.localizedDescription];
                return;
            }

            NSString *msg = [NSString stringWithFormat:@"Telefonunuzdan veya bilgisayarınızdan şu adresi açın:\n\n%@\n\nVe bu kodu girin:\n👉 %@ 👈\n\nOnayladıktan sonra bu ekran otomatik kapanacaktır.",
                             verificationUrl, userCode];

            self.deviceAuthAlert = [UIAlertController alertControllerWithTitle:@"Google Hesabınızı Onaylayın"
                                                                       message:msg
                                                                preferredStyle:UIAlertControllerStyleAlert];
            [self.deviceAuthAlert addAction:[UIAlertAction actionWithTitle:@"Vazgeç" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:self.deviceAuthAlert animated:YES completion:nil];

            [[GeminiClient sharedClient] pollDeviceTokenWithDeviceCode:deviceCode interval:5 completion:^(BOOL success, NSError *pollErr) {
                [self.deviceAuthAlert dismissViewControllerAnimated:YES completion:^{
                    if (success) {
                        [self updateTitleWithModel];
                        [self showAlertWithTitle:@"Giriş Başarılı!" 
                                         message:@"Google hesabınız başarıyla bağlandı. Artık kotasız ve doğrudan hesabınızla konuşabilirsiniz."];
                    } else if (pollErr) {
                        [self showAlertWithTitle:@"Giriş Tamamlanamadı" message:pollErr.localizedDescription];
                    }
                }];
            }];
        }];
    }];
}

- (void)refreshModelsAction {
    [[NSUserDefaults standardUserDefaults] synchronize];

    if (![[GeminiClient sharedClient] isAuthenticated]) {
        [self showAlertWithTitle:@"Giriş Gerekli" 
                         message:@"Modelleri çekebilmek için lütfen geçerli bir API Key girin veya Google Hesabınızı bağlayın."];
        return;
    }

    UIAlertController *loading = [UIAlertController alertControllerWithTitle:@"Modeller Alınıyor"
                                                                     message:@"Google API'den canlı model listesi çekiliyor..."
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loading animated:YES completion:nil];

    [[GeminiClient sharedClient] fetchAvailableModelsWithCompletion:^(NSArray *models, NSError *error) {
        [loading dismissViewControllerAnimated:YES completion:^{
            if (error) {
                [self showAlertWithTitle:@"Hata" message:error.localizedDescription];
                return;
            }

            if (models.count == 0) {
                [self showAlertWithTitle:@"Model Bulunamadı" message:@"Erişilebilir model listesi boş döndü."];
                return;
            }

            UIAlertController *modelPicker = [UIAlertController alertControllerWithTitle:@"Model Seçin"
                                                                                 message:@"Kullanmak istediğiniz modeli seçin:"
                                                                          preferredStyle:UIAlertControllerStyleActionSheet];
            for (NSString *m in models) {
                [modelPicker addAction:[UIAlertAction actionWithTitle:m style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                    [[NSUserDefaults standardUserDefaults] setObject:m forKey:@"GeminiClientModel"];
                    [[NSUserDefaults standardUserDefaults] synchronize];
                    [self updateTitleWithModel];
                }]];
            }
            [modelPicker addAction:[UIAlertAction actionWithTitle:@"Vazgeç" style:UIAlertActionStyleCancel handler:nil]];
            modelPicker.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
            [self presentViewController:modelPicker animated:YES completion:nil];
        }];
    }];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)msg {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Tamam" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)setupTableView {
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;

    _tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, w, h - 50.0) style:UITableViewStylePlain];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.backgroundColor = [UIColor colorWithRed:0.96 green:0.96 blue:0.98 alpha:1.0];
    _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    [_tableView addGestureRecognizer:tap];

    [self.view addSubview:_tableView];
}

- (void)setupInputBar {
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    CGFloat barH = 50.0;

    _inputContainerView = [[UIView alloc] initWithFrame:CGRectMake(0, h - barH, w, barH)];
    _inputContainerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    _inputContainerView.backgroundColor = [UIColor colorWithWhite:0.98 alpha:0.95];

    UIView *topLine = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 0.5)];
    topLine.backgroundColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    topLine.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [_inputContainerView addSubview:topLine];

    _webSearchButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _webSearchButton.frame = CGRectMake(8, 7, 36, 36);
    _webSearchButton.layer.cornerRadius = 18.0;
    _webSearchButton.layer.masksToBounds = YES;
    [_webSearchButton setTitle:@"🌐" forState:UIControlStateNormal];
    _webSearchButton.titleLabel.font = [UIFont systemFontOfSize:19.0];
    [_webSearchButton addTarget:self action:@selector(toggleWebSearch) forControlEvents:UIControlEventTouchUpInside];
    [self updateWebSearchButtonAppearance];
    [_inputContainerView addSubview:_webSearchButton];

    CGFloat textX = 50.0;
    CGFloat textW = w - textX - 68.0;
    _inputTextField = [[UITextField alloc] initWithFrame:CGRectMake(textX, 8, textW, 34)];
    _inputTextField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _inputTextField.placeholder = @"Gemini'ye bir soru sor...";
    _inputTextField.font = [UIFont fontWithName:@"HelveticaNeue" size:15.0];
    _inputTextField.backgroundColor = [UIColor whiteColor];
    _inputTextField.layer.cornerRadius = 17.0;
    _inputTextField.layer.borderWidth = 0.5;
    _inputTextField.layer.borderColor = [UIColor colorWithWhite:0.8 alpha:1.0].CGColor;
    _inputTextField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 34)];
    _inputTextField.leftViewMode = UITextFieldViewModeAlways;
    _inputTextField.delegate = self;
    _inputTextField.returnKeyType = UIReturnKeySend;
    [_inputContainerView addSubview:_inputTextField];

    _sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _sendButton.frame = CGRectMake(w - 62, 8, 54, 34);
    _sendButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [_sendButton setTitle:@"Gönder" forState:UIControlStateNormal];
    _sendButton.titleLabel.font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:15.0];
    [_sendButton addTarget:self action:@selector(sendButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [_inputContainerView addSubview:_sendButton];

    _activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _activityIndicator.center = _sendButton.center;
    _activityIndicator.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    _activityIndicator.hidesWhenStopped = YES;
    [_inputContainerView addSubview:_activityIndicator];

    [self.view addSubview:_inputContainerView];
}

- (void)toggleWebSearch {
    self.isWebSearchActive = !self.isWebSearchActive;
    [[NSUserDefaults standardUserDefaults] setBool:self.isWebSearchActive forKey:@"enable_google_search"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    [UIView animateWithDuration:0.2 animations:^{
        [self updateWebSearchButtonAppearance];
        self.webSearchButton.transform = CGAffineTransformMakeScale(1.15, 1.15);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.15 animations:^{
            self.webSearchButton.transform = CGAffineTransformIdentity;
        }];
    }];
}

- (void)updateWebSearchButtonAppearance {
    if (self.isWebSearchActive) {
        self.webSearchButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.478 blue:1.0 alpha:0.18];
        self.webSearchButton.layer.borderWidth = 1.5;
        self.webSearchButton.layer.borderColor = [UIColor colorWithRed:0.0 green:0.478 blue:1.0 alpha:1.0].CGColor;
    } else {
        self.webSearchButton.backgroundColor = [UIColor colorWithWhite:0.92 alpha:1.0];
        self.webSearchButton.layer.borderWidth = 0.5;
        self.webSearchButton.layer.borderColor = [UIColor colorWithWhite:0.8 alpha:1.0].CGColor;
    }
}

- (void)addWelcomeMessageIfNeeded {
    if (self.messages.count == 0) {
        NSString *welcomeText = @"Merhaba! Ben Gemini. iPad Mini 1 (iOS 8.4, v2.2) üzerinde çalışıyorum.\n\nİşlem yapmak için sağ üstteki 'İşlemler' butonunu veya iPad Ayarları'ndaki doğrudan butonları kullanabilirsiniz!";
        ChatMessage *welcome = [ChatMessage messageWithText:welcomeText sender:ChatMessageSenderGemini];
        [self.messages addObject:welcome];
        [self.tableView reloadData];
    }
}

- (void)clearChatTapped {
    [self.messages removeAllObjects];
    [self.tableView reloadData];
    [self addWelcomeMessageIfNeeded];
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

#pragma mark - Keyboard Notifications

- (void)registerKeyboardNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)keyboardWillShow:(NSNotification *)note {
    NSDictionary *info = note.userInfo;
    CGRect endFrame = [info[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    NSTimeInterval duration = [info[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationOptions curve = [info[UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue] << 16;

    CGRect convertedFrame = [self.view convertRect:endFrame fromView:nil];
    CGFloat kh = self.view.bounds.size.height - convertedFrame.origin.y;
    self.keyboardHeight = kh > 0 ? kh : 0;

    [UIView animateWithDuration:duration delay:0 options:curve animations:^{
        CGFloat w = self.view.bounds.size.width;
        CGFloat h = self.view.bounds.size.height;
        self.inputContainerView.frame = CGRectMake(0, h - self.keyboardHeight - 50.0, w, 50.0);
        self.tableView.frame = CGRectMake(0, 0, w, h - self.keyboardHeight - 50.0);
    } completion:^(BOOL finished) {
        [self scrollToBottomAnimated:NO];
    }];
}

- (void)keyboardWillHide:(NSNotification *)note {
    NSDictionary *info = note.userInfo;
    NSTimeInterval duration = [info[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationOptions curve = [info[UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue] << 16;
    self.keyboardHeight = 0;

    [UIView animateWithDuration:duration delay:0 options:curve animations:^{
        CGFloat w = self.view.bounds.size.width;
        CGFloat h = self.view.bounds.size.height;
        self.inputContainerView.frame = CGRectMake(0, h - 50.0, w, 50.0);
        self.tableView.frame = CGRectMake(0, 0, w, h - 50.0);
    } completion:nil];
}

#pragma mark - Messaging Logic

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self sendButtonTapped];
    return YES;
}

- (void)sendButtonTapped {
    NSString *rawText = [self.inputTextField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (rawText.length == 0 || self.isSending) return;

    if (![[GeminiClient sharedClient] isAuthenticated]) {
        [self showAuthPrompt];
        return;
    }

    ChatMessage *userMsg = [ChatMessage messageWithText:rawText sender:ChatMessageSenderUser];
    [self.messages addObject:userMsg];

    [self.tableView reloadData];
    [self scrollToBottomAnimated:YES];

    self.inputTextField.text = @"";
    [self setSendingState:YES];
    self.isSending = YES;

    [[GeminiClient sharedClient] sendMessage:rawText 
                                     history:self.messages 
                                  completion:^(NSString *response, NSError *error) {
        
        [self setSendingState:NO];
        self.isSending = NO;

        if (error) {
            ChatMessage *errChat = [ChatMessage messageWithText:[NSString stringWithFormat:@"Hata: %@", error.localizedDescription] 
                                                         sender:ChatMessageSenderGemini];
            [self.messages addObject:errChat];
        } else {
            NSString *reply = (response && response.length > 0) ? response : @"(Boş yanıt döndü)";
            ChatMessage *geminiChat = [ChatMessage messageWithText:reply sender:ChatMessageSenderGemini];
            [self.messages addObject:geminiChat];
        }

        [self.tableView reloadData];
        [self scrollToBottomAnimated:YES];
    }];
}

- (void)setSendingState:(BOOL)sending {
    self.sendButton.hidden = sending;
    if (sending) {
        [self.activityIndicator startAnimating];
        self.inputTextField.enabled = NO;
    } else {
        [self.activityIndicator stopAnimating];
        self.inputTextField.enabled = YES;
    }
}

- (void)scrollToBottomAnimated:(BOOL)animated {
    if (self.messages.count > 0) {
        NSIndexPath *lastPath = [NSIndexPath indexPathForRow:self.messages.count - 1 inSection:0];
        [self.tableView scrollToRowAtIndexPath:lastPath atScrollPosition:UITableViewScrollPositionBottom animated:animated];
    }
}

- (void)showAuthPrompt {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Giriş Gerekli"
                                                                   message:@"Gemini ile konuşabilmek için sağ üstteki 'İşlemler' menüsünden Google Hesabınızı bağlayabilir veya iPad Ayarları'ndan API anahtarınızı girebilirsiniz."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Tamam" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Table View Data Source & Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.messages.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    ChatMessage *msg = self.messages[indexPath.row];
    return [ChatBubbleCell heightForMessage:msg containerWidth:tableView.bounds.size.width];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellId = @"ChatBubbleCell";
    ChatBubbleCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
    if (!cell) {
        cell = [[ChatBubbleCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellId];
    }
    ChatMessage *msg = self.messages[indexPath.row];
    [cell configureWithMessage:msg containerWidth:tableView.bounds.size.width];
    return cell;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
