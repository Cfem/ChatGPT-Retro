#import "ChatViewController.h"
#import "ChatBubbleCell.h"
#import "ChatMessage.h"
#import "OpenAIClient.h"
#import "SettingsViewController.h"

@interface ChatViewController () <SettingsViewControllerDelegate>

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

@end

@implementation ChatViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"ChatGPT";
    self.view.backgroundColor = [UIColor colorWithRed:0.96 green:0.96 blue:0.98 alpha:1.0];

    _messages = [NSMutableArray array];

    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"enable_chatgpt_web_search"] == nil) {
        _isWebSearchActive = YES;
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"enable_chatgpt_web_search"];
    } else {
        _isWebSearchActive = [[NSUserDefaults standardUserDefaults] boolForKey:@"enable_chatgpt_web_search"];
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
    NSString *model = [OpenAIClient sharedClient].selectedModel;
    NSString *authStatus = ([OpenAIClient sharedClient].apiKey.length > 10) ? @" [Hazır]" : @" [API Key Eksik]";
    self.navigationItem.prompt = [NSString stringWithFormat:@"Model: %@%@ (v1.2)", model ?: @"gpt-4o-mini", authStatus];
}

- (void)setupNavigationItems {
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Temizle"
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(clearChatTapped)];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Ayarlar"
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self
                                                                             action:@selector(openSettingsTapped)];
}

- (void)openSettingsTapped {
    SettingsViewController *settingsVC = [[SettingsViewController alloc] init];
    settingsVC.delegate = self;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settingsVC];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)settingsDidUpdate {
    [self updateTitleWithModel];
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

    // Üst çizgi
    UIView *topLine = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 0.5)];
    topLine.backgroundColor = [UIColor colorWithWhite:0.8 alpha:1.0];
    topLine.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [_inputContainerView addSubview:topLine];

    // Web Arama Butonu (GeminiRetro stili)
    _webSearchButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _webSearchButton.frame = CGRectMake(8, 7, 36, 36);
    _webSearchButton.layer.cornerRadius = 18.0;
    _webSearchButton.layer.masksToBounds = YES;
    [_webSearchButton setTitle:@"🌐" forState:UIControlStateNormal];
    _webSearchButton.titleLabel.font = [UIFont systemFontOfSize:19.0];
    [_webSearchButton addTarget:self action:@selector(toggleWebSearch) forControlEvents:UIControlEventTouchUpInside];
    [self updateWebSearchButtonAppearance];
    [_inputContainerView addSubview:_webSearchButton];

    // Metin Kutusu
    CGFloat textX = 50.0;
    CGFloat textW = w - textX - 68.0;
    _inputTextField = [[UITextField alloc] initWithFrame:CGRectMake(textX, 8, textW, 34)];
    _inputTextField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _inputTextField.placeholder = @"Mesajınızı yazın...";
    _inputTextField.font = [UIFont fontWithName:@"HelveticaNeue" size:15.0];
    _inputTextField.borderStyle = UITextBorderStyleRoundedRect;
    _inputTextField.backgroundColor = [UIColor whiteColor];
    _inputTextField.returnKeyType = UIReturnKeySend;
    _inputTextField.delegate = self;
    [_inputContainerView addSubview:_inputTextField];

    // Gönder Butonu (OpenAI Yeşili)
    _sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _sendButton.frame = CGRectMake(w - 66, 8, 58, 34);
    _sendButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [_sendButton setTitle:@"Gönder" forState:UIControlStateNormal];
    _sendButton.titleLabel.font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:16.0];
    [_sendButton setTitleColor:[UIColor colorWithRed:16.0/255.0 green:163.0/255.0 blue:127.0/255.0 alpha:1.0] forState:UIControlStateNormal];
    [_sendButton addTarget:self action:@selector(sendButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [_inputContainerView addSubview:_sendButton];

    // Activity Indicator
    _activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _activityIndicator.frame = _sendButton.frame;
    _activityIndicator.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    _activityIndicator.hidesWhenStopped = YES;
    [_inputContainerView addSubview:_activityIndicator];

    [self.view addSubview:_inputContainerView];
}

- (void)toggleWebSearch {
    self.isWebSearchActive = !self.isWebSearchActive;
    [[NSUserDefaults standardUserDefaults] setBool:self.isWebSearchActive forKey:@"enable_chatgpt_web_search"];
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
        // OpenAI Teal/Yeşil Aktif Ton
        self.webSearchButton.backgroundColor = [UIColor colorWithRed:16.0/255.0 green:163.0/255.0 blue:127.0/255.0 alpha:0.18];
        self.webSearchButton.layer.borderWidth = 1.5;
        self.webSearchButton.layer.borderColor = [UIColor colorWithRed:16.0/255.0 green:163.0/255.0 blue:127.0/255.0 alpha:1.0].CGColor;
    } else {
        self.webSearchButton.backgroundColor = [UIColor colorWithWhite:0.92 alpha:1.0];
        self.webSearchButton.layer.borderWidth = 0.5;
        self.webSearchButton.layer.borderColor = [UIColor colorWithWhite:0.8 alpha:1.0].CGColor;
    }
}

- (void)addWelcomeMessageIfNeeded {
    NSString *welcome = @"👋 ChatGPT Retro'ya Hoş Geldiniz!\n\n"
                        @"Bu uygulama iPad Mini 1 (iOS 8.4) üzerinde resmi OpenAI modelleriyle (GPT-4o, GPT-6 Luna vb.) doğrudan sohbet etmeniz için uyarlandı.\n\n"
                        @"🌐 Sol alttaki Web Arama butonuyla canlı güncel internet bilgilerini açıp kapatabilirsiniz.";
    [self.messages addObject:[ChatMessage messageWithText:welcome sender:ChatMessageSenderAssistant]];
    [self.tableView reloadData];
}

- (void)clearChatTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Sohbeti Temizle"
                                                                   message:@"Tüm mesaj geçmişi silinsin mi?"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Temizle" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self.messages removeAllObjects];
        [self addWelcomeMessageIfNeeded];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Vazgeç" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

#pragma mark - Keyboard Handling

- (void)registerKeyboardNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
}

- (void)keyboardWillShow:(NSNotification *)note {
    NSDictionary *info = note.userInfo;
    CGRect endFrame = [info[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    NSTimeInterval duration = [info[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationOptions curve = [info[UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue] << 16;

    CGRect convertedFrame = [self.view convertRect:endFrame fromView:nil];
    self.keyboardHeight = self.view.bounds.size.height - convertedFrame.origin.y;
    if (self.keyboardHeight < 0) self.keyboardHeight = 0;

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

    if (![[OpenAIClient sharedClient] isAuthenticated]) {
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

    [[OpenAIClient sharedClient] sendMessage:rawText 
                                     history:self.messages 
                                   webSearch:self.isWebSearchActive 
                                  completion:^(NSString *response, NSError *error) {
        
        [self setSendingState:NO];
        self.isSending = NO;

        if (error) {
            ChatMessage *errChat = [ChatMessage messageWithText:[NSString stringWithFormat:@"Hata: %@", error.localizedDescription] 
                                                         sender:ChatMessageSenderAssistant];
            [self.messages addObject:errChat];
        } else {
            NSString *reply = (response && response.length > 0) ? response : @"(Boş yanıt döndü)";
            ChatMessage *assistantChat = [ChatMessage messageWithText:reply sender:ChatMessageSenderAssistant];
            [self.messages addObject:assistantChat];
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
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"API Anahtarı Gerekli"
                                                                   message:@"ChatGPT ile konuşabilmek için sağ üstteki 'Ayarlar' menüsünden OpenAI API Anahtarınızı (sk-...) giriniz."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Ayarlar'ı Aç" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self openSettingsTapped];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Vazgeç" style:UIAlertActionStyleCancel handler:nil]];
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
