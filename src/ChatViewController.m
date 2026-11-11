#import "ChatViewController.h"
#import "ChatBubbleCell.h"
#import "ChatMessage.h"
#import "GeminiClient.h"
#import "SettingsViewController.h"

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
@property (nonatomic, assign) BOOL isStreaming;
@property (nonatomic, assign) BOOL isWebSearchActive;

@end

@implementation ChatViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Gemini";
    self.view.backgroundColor = [UIColor colorWithRed:0.96 green:0.96 blue:0.98 alpha:1.0];

    _messages = [NSMutableArray array];

    // Web arama durumunu NSUserDefaults'tan oku (varsayılan: AÇIK)
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

    [self addWelcomeMessageIfNeeded];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateTitleWithModel];
}

- (void)updateTitleWithModel {
    NSString *model = [GeminiClient sharedClient].selectedModel;
    if ([model containsString:@"flash-8b"]) {
        self.navigationItem.prompt = @"Model: Gemini 1.5 Flash-8B (v1.6)";
    } else if ([model containsString:@"pro"]) {
        self.navigationItem.prompt = @"Model: Gemini 1.5 Pro (v1.6)";
    } else {
        self.navigationItem.prompt = [NSString stringWithFormat:@"Model: %@ (v1.6)", model ?: @"Gemini 1.5 Flash"];
    }
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

    // İnce üst çizgi
    UIView *topLine = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 0.5)];
    topLine.backgroundColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    topLine.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [_inputContainerView addSubview:topLine];

    // 1. SOL: İnternet / Web Arama Butonu (Chatbox'ın hemen solunda)
    _webSearchButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _webSearchButton.frame = CGRectMake(8, 7, 36, 36);
    _webSearchButton.layer.cornerRadius = 18.0;
    _webSearchButton.layer.masksToBounds = YES;
    [_webSearchButton setTitle:@"🌐" forState:UIControlStateNormal];
    _webSearchButton.titleLabel.font = [UIFont systemFontOfSize:19.0];
    [_webSearchButton addTarget:self action:@selector(toggleWebSearch) forControlEvents:UIControlEventTouchUpInside];
    [self updateWebSearchButtonAppearance];
    [_inputContainerView addSubview:_webSearchButton];

    // 2. ORTA: Giriş Kutusu (Chatbox)
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

    // 3. SAĞ: Gönder butonu
    _sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _sendButton.frame = CGRectMake(w - 62, 8, 54, 34);
    _sendButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [_sendButton setTitle:@"Gönder" forState:UIControlStateNormal];
    _sendButton.titleLabel.font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:15.0];
    [_sendButton addTarget:self action:@selector(sendButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [_inputContainerView addSubview:_sendButton];

    // Yükleniyor göstergesi
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
        // Açık: Canlı Mavi Arka Plan, Beyaz/Parlak İkon
        self.webSearchButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.478 blue:1.0 alpha:0.18];
        self.webSearchButton.layer.borderWidth = 1.5;
        self.webSearchButton.layer.borderColor = [UIColor colorWithRed:0.0 green:0.478 blue:1.0 alpha:1.0].CGColor;
    } else {
        // Kapalı: Düz Açık Gri Arka Plan
        self.webSearchButton.backgroundColor = [UIColor colorWithWhite:0.92 alpha:1.0];
        self.webSearchButton.layer.borderWidth = 0.5;
        self.webSearchButton.layer.borderColor = [UIColor colorWithWhite:0.8 alpha:1.0].CGColor;
    }
}

- (void)addWelcomeMessageIfNeeded {
    if (self.messages.count == 0) {
        NSString *welcomeText = @"Merhaba! Ben Gemini. iPad Mini 1 (iOS 8.4, v1.6) üzerinde canlı akış ve doğrudan web arama butonu ile çalışıyorum.\n\nİnternette canlı arama yapmak için mesaj kutusunun solundaki 🌐 butonunu maviye (açık) alabilirsiniz!";
        ChatMessage *welcome = [ChatMessage messageWithText:welcomeText sender:ChatMessageSenderGemini];
        [self.messages addObject:welcome];
        [self.tableView reloadData];
    }
}

- (void)openSettingsTapped {
    SettingsViewController *settingsVC = [[SettingsViewController alloc] init];
    settingsVC.delegate = self;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settingsVC];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)clearChatTapped {
    [self.messages removeAllObjects];
    [self.tableView reloadData];
    [self addWelcomeMessageIfNeeded];
}

- (void)settingsDidUpdate {
    [self updateTitleWithModel];
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

#pragma mark - Keyboard Notifications

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
    if (rawText.length == 0 || self.isStreaming) return;

    if (![[GeminiClient sharedClient] hasApiKey]) {
        [self showApiKeyPrompt];
        return;
    }

    ChatMessage *userMsg = [ChatMessage messageWithText:rawText sender:ChatMessageSenderUser];
    [self.messages addObject:userMsg];

    ChatMessage *geminiMsg = [ChatMessage messageWithText:@"..." sender:ChatMessageSenderGemini];
    [self.messages addObject:geminiMsg];

    [self.tableView reloadData];
    [self scrollToBottomAnimated:YES];

    self.inputTextField.text = @"";
    [self setSendingState:YES];
    self.isStreaming = YES;

    [[GeminiClient sharedClient] streamMessage:rawText 
                                       history:self.messages 
                                  chunkHandler:^(NSString *chunk, NSString *accumulatedText, BOOL isFinished, NSError *error) {
        
        if (error && accumulatedText.length == 0) {
            [self setSendingState:NO];
            self.isStreaming = NO;
            geminiMsg.text = [NSString stringWithFormat:@"Hata: %@", error.localizedDescription];
            geminiMsg.cachedHeight = 0;
            [self.tableView reloadData];
            return;
        }

        if (accumulatedText.length > 0) {
            geminiMsg.text = accumulatedText;
            geminiMsg.cachedHeight = 0;
        }

        if (isFinished) {
            [self setSendingState:NO];
            self.isStreaming = NO;
            [self.tableView reloadData];
            [self scrollToBottomAnimated:YES];
        } else {
            [self updateLastMessageCellAnimated:NO];
        }
    }];
}

- (void)updateLastMessageCellAnimated:(BOOL)animated {
    if (self.messages.count == 0) return;
    NSIndexPath *lastPath = [NSIndexPath indexPathForRow:self.messages.count - 1 inSection:0];
    [UIView performWithoutAnimation:^{
        [self.tableView reloadRowsAtIndexPaths:@[lastPath] withRowAnimation:UITableViewRowAnimationNone];
    }];
    [self scrollToBottomAnimated:NO];
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

- (void)showApiKeyPrompt {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"API Anahtarı Gerekli"
                                                                   message:@"Gemini ile konuşabilmek için Ayarlar'dan ücretsiz Google AI Studio API anahtarınızı girmeniz gerekmektedir."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Vazgeç" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Ayarlar'a Git" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self openSettingsTapped];
    }]];
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
