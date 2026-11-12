#import "ChatViewController.h"
#import "ChatBubbleCell.h"
#import "ChatMessage.h"
#import "OpenAIClient.h"
#import "SettingsViewController.h"
#import "ChatGPTLoginModalViewController.h"
#import "ChatHistoryManager.h"
#import "ChatHistorySidebarViewController.h"
#import "LocalizationManager.h"

@interface ChatViewController () <SettingsViewControllerDelegate, ChatGPTLoginModalDelegate, ChatHistorySidebarDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *messages;

// Slide-out Drawer / Sidebar (Left: Chats History)
@property (nonatomic, strong) ChatHistorySidebarViewController *sidebarVC;
@property (nonatomic, strong) UINavigationController *sidebarNavController;
@property (nonatomic, strong) UIView *sidebarContainerView;
@property (nonatomic, strong) UIView *dimmingOverlayView;
@property (nonatomic, assign) BOOL isSidebarOpen;

// Slide-out Drawer / Settings (Right: Wide Settings Drawer)
@property (nonatomic, strong) SettingsViewController *settingsVC;
@property (nonatomic, strong) UINavigationController *settingsNavController;
@property (nonatomic, strong) UIView *settingsContainerView;
@property (nonatomic, assign) BOOL isSettingsOpen;

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
    [self setupSidebarGestures];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(userDefaultsDidChange:)
                                                 name:NSUserDefaultsDidChangeNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(userDefaultsDidChange:)
                                                 name:kChatGPTAuthStateDidChangeNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(languageDidChange:)
                                                 name:kLanguageDidChangeNotification
                                               object:nil];

    // Aktif oturumu yükle
    ChatSession *active = [ChatHistoryManager sharedManager].activeSession;
    [self loadSession:active];
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

- (void)languageDidChange:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setupNavigationItems];
        [self updateTitleWithModel];
        self.inputTextField.placeholder = LocalizedString(@"input_placeholder");
        [self.sendButton setTitle:LocalizedString(@"send_button") forState:UIControlStateNormal];
        [self.tableView reloadData];
    });
}

- (void)updateTitleWithModel {
    NSString *model = [OpenAIClient sharedClient].selectedModel;
    NSString *authStatus = LocalizedString(@"auth_status_need_login");
    if ([[OpenAIClient sharedClient] isChatGPTAccountLinked]) {
        authStatus = LocalizedString(@"auth_status_plan");
    } else if ([OpenAIClient sharedClient].apiKey.length > 10) {
        authStatus = LocalizedString(@"auth_status_ready");
    }
    self.navigationItem.prompt = [NSString stringWithFormat:@"Model: %@%@ (v1.6.1)", model ?: @"gpt-4o-mini", authStatus];
}

- (void)setupNavigationItems {
    // Sol: "Sohbetler" Butonu (Yerelleştirilmiş, emojiden arındırılmış)
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:LocalizedString(@"sidebar_chats")
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(toggleSidebar)];

    // Sağ: Ayarlar (Klasik Apple Dişli İkonu) ve Yeni Sohbet (+) Butonları
    UIImage *gearImg = [UIImage imageNamed:@"SettingsGear"];
    UIBarButtonItem *settingsBtn;
    if (gearImg) {
        gearImg = [gearImg imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        settingsBtn = [[UIBarButtonItem alloc] initWithImage:gearImg
                                                       style:UIBarButtonItemStylePlain
                                                      target:self
                                                      action:@selector(openSettingsTapped)];
    } else {
        settingsBtn = [[UIBarButtonItem alloc] initWithTitle:LocalizedString(@"settings_title")
                                                       style:UIBarButtonItemStylePlain
                                                      target:self
                                                      action:@selector(openSettingsTapped)];
    }

    UIBarButtonItem *newChatBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose
                                                                                target:self
                                                                                action:@selector(newChatTapped)];

    self.navigationItem.rightBarButtonItems = @[settingsBtn, newChatBtn];
}

#pragma mark - Sidebar Setup & Gestures

- (CGFloat)sidebarWidth {
    CGFloat screenW = self.view.window.bounds.size.width;
    if (screenW <= 0) screenW = self.view.bounds.size.width;
    // iOS 8 iPad için ideal kenar çekmecesi genişliği: 320pt veya %35
    CGFloat w = screenW * 0.35;
    if (w < 300.0) w = 300.0;
    if (screenW > 0 && w > screenW * 0.6) w = screenW * 0.6;
    return w;
}

- (CGFloat)settingsWidth {
    CGFloat screenW = self.view.window.bounds.size.width;
    if (screenW <= 0) screenW = self.view.bounds.size.width;
    // Enlemesine geniş sağ çekmece (iPad ekranının %65'i)
    CGFloat w = screenW * 0.65;
    if (w < 440.0) w = 440.0;
    if (screenW > 0 && w > screenW * 0.85) w = screenW * 0.85;
    return w;
}

- (void)setupSidebarGestures {
    // Ekranın sol kenarından sağa kaydırarak açma (Screen Edge Swipe Left -> Sidebar)
    UIScreenEdgePanGestureRecognizer *edgeSwipeLeft = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(handleScreenEdgePanLeft:)];
    edgeSwipeLeft.edges = UIRectEdgeLeft;
    [self.view addGestureRecognizer:edgeSwipeLeft];

    // Ekranın sağ kenarından sola kaydırarak açma (Screen Edge Swipe Right -> Settings)
    UIScreenEdgePanGestureRecognizer *edgeSwipeRight = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(handleScreenEdgePanRight:)];
    edgeSwipeRight.edges = UIRectEdgeRight;
    [self.view addGestureRecognizer:edgeSwipeRight];
}

- (void)handleScreenEdgePanLeft:(UIScreenEdgePanGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateBegan && !self.isSidebarOpen && !self.isSettingsOpen) {
        [self openSidebarAnimated:YES];
    }
}

- (void)handleScreenEdgePanRight:(UIScreenEdgePanGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateBegan && !self.isSettingsOpen && !self.isSidebarOpen) {
        [self openSettingsAnimated:YES];
    }
}

- (void)ensureSidebarViews {
    if (self.sidebarContainerView) return;

    UIWindow *targetWindow = self.view.window ?: [UIApplication sharedApplication].keyWindow;
    CGRect winBounds = targetWindow.bounds;
    CGFloat sWidth = [self sidebarWidth];

    // 1. Arka planı karartan ve dokununca kapatan Dimming Overlay
    if (!_dimmingOverlayView) {
        _dimmingOverlayView = [[UIView alloc] initWithFrame:winBounds];
        _dimmingOverlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _dimmingOverlayView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.4];
        _dimmingOverlayView.alpha = 0.0;
        _dimmingOverlayView.hidden = YES;

        UITapGestureRecognizer *tapToClose = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDimmingOverlayTap)];
        [_dimmingOverlayView addGestureRecognizer:tapToClose];

        [targetWindow addSubview:_dimmingOverlayView];
    }

    // 2. Sidebar Sütunu (Tam Yükseklik - Soldan Kayar)
    _sidebarContainerView = [[UIView alloc] initWithFrame:CGRectMake(-sWidth, 0, sWidth, winBounds.size.height)];
    _sidebarContainerView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleRightMargin;
    _sidebarContainerView.backgroundColor = [UIColor whiteColor];
    _sidebarContainerView.hidden = YES;

    // 1px sağ sınır çizgisi (Dinamik gölge yerine 60 FPS akıcılık ve kenar karartmasını önlemek için)
    UIView *rightBorder = [[UIView alloc] initWithFrame:CGRectMake(sWidth - 0.5, 0, 0.5, winBounds.size.height)];
    rightBorder.backgroundColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    rightBorder.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleLeftMargin;

    // Sidebar View Controller'ı bağla
    _sidebarVC = [[ChatHistorySidebarViewController alloc] init];
    _sidebarVC.delegate = self;
    _sidebarNavController = [[UINavigationController alloc] initWithRootViewController:_sidebarVC];
    _sidebarNavController.view.frame = _sidebarContainerView.bounds;
    _sidebarNavController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    [_sidebarContainerView addSubview:_sidebarNavController.view];
    [_sidebarContainerView addSubview:rightBorder];

    // Sola kaydırınca kapatma (Swipe Left on Sidebar)
    UISwipeGestureRecognizer *swipeLeft = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(closeSidebar)];
    swipeLeft.direction = UISwipeGestureRecognizerDirectionLeft;
    [_sidebarContainerView addGestureRecognizer:swipeLeft];

    [targetWindow addSubview:_sidebarContainerView];
}

- (void)ensureSettingsViews {
    if (self.settingsContainerView) return;

    UIWindow *targetWindow = self.view.window ?: [UIApplication sharedApplication].keyWindow;
    CGRect winBounds = targetWindow.bounds;
    CGFloat setWidth = [self settingsWidth];

    // Dimming overlay
    if (!_dimmingOverlayView) {
        _dimmingOverlayView = [[UIView alloc] initWithFrame:winBounds];
        _dimmingOverlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _dimmingOverlayView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.4];
        _dimmingOverlayView.alpha = 0.0;
        _dimmingOverlayView.hidden = YES;

        UITapGestureRecognizer *tapToClose = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDimmingOverlayTap)];
        [_dimmingOverlayView addGestureRecognizer:tapToClose];

        [targetWindow addSubview:_dimmingOverlayView];
    }

    // Settings Çekmecesi (Sağdan Enlemesine Kayar)
    _settingsContainerView = [[UIView alloc] initWithFrame:CGRectMake(winBounds.size.width, 0, setWidth, winBounds.size.height)];
    _settingsContainerView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleLeftMargin;
    _settingsContainerView.backgroundColor = [UIColor whiteColor];
    _settingsContainerView.hidden = YES;

    // 1px sol sınır çizgisi (Dinamik gölge yerine 60 FPS akıcılık ve kenar karartmasını önlemek için)
    UIView *leftBorder = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0.5, winBounds.size.height)];
    leftBorder.backgroundColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    leftBorder.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleRightMargin;

    _settingsVC = [[SettingsViewController alloc] init];
    _settingsVC.delegate = self;
    _settingsNavController = [[UINavigationController alloc] initWithRootViewController:_settingsVC];
    _settingsNavController.view.frame = _settingsContainerView.bounds;
    _settingsNavController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    [_settingsContainerView addSubview:_settingsNavController.view];
    [_settingsContainerView addSubview:leftBorder];

    // Sağa kaydırınca kapatma (Swipe Right on Settings)
    UISwipeGestureRecognizer *swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(closeSettings)];
    swipeRight.direction = UISwipeGestureRecognizerDirectionRight;
    [_settingsContainerView addGestureRecognizer:swipeRight];

    [targetWindow addSubview:_settingsContainerView];
}

- (void)handleDimmingOverlayTap {
    if (self.isSidebarOpen) {
        [self closeSidebar];
    }
    if (self.isSettingsOpen) {
        [self closeSettings];
    }
}

- (void)toggleSidebar {
    if (self.isSidebarOpen) {
        [self closeSidebar];
    } else {
        [self openSidebarAnimated:YES];
    }
}

- (void)openSidebarAnimated:(BOOL)animated {
    [self.view endEditing:YES];
    if (self.isSettingsOpen) {
        [self closeSettings];
    }
    [self ensureSidebarViews];
    [self.sidebarVC reloadHistory];

    UIWindow *targetWindow = self.view.window ?: [UIApplication sharedApplication].keyWindow;
    CGRect winBounds = targetWindow.bounds;
    CGFloat sWidth = [self sidebarWidth];

    self.dimmingOverlayView.frame = winBounds;
    self.sidebarContainerView.frame = CGRectMake(-sWidth, 0, sWidth, winBounds.size.height);
    self.dimmingOverlayView.hidden = NO;
    self.sidebarContainerView.hidden = NO;

    void (^animations)(void) = ^{
        self.dimmingOverlayView.alpha = 1.0;
        self.sidebarContainerView.frame = CGRectMake(0, 0, sWidth, winBounds.size.height);
    };

    void (^completion)(BOOL) = ^(BOOL finished) {
        self.isSidebarOpen = YES;
    };

    if (animated) {
        [UIView animateWithDuration:0.25 delay:0 options:(7 << 16) | UIViewAnimationOptionBeginFromCurrentState animations:animations completion:completion];
    } else {
        animations();
        completion(YES);
    }
}

- (void)closeSidebar {
    [self closeSidebarWithCompletion:nil];
}

- (void)closeSidebarWithCompletion:(void (^)(void))onComplete {
    if (!self.isSidebarOpen && self.sidebarContainerView.hidden) {
        if (onComplete) onComplete();
        return;
    }

    CGFloat sWidth = [self sidebarWidth];
    CGRect currentFrame = self.sidebarContainerView.frame;

    [UIView animateWithDuration:0.22 delay:0 options:(7 << 16) | UIViewAnimationOptionBeginFromCurrentState animations:^{
        if (!self.isSettingsOpen) {
            self.dimmingOverlayView.alpha = 0.0;
        }
        self.sidebarContainerView.frame = CGRectMake(-sWidth, currentFrame.origin.y, sWidth, currentFrame.size.height);
    } completion:^(BOOL finished) {
        self.isSidebarOpen = NO;
        self.sidebarContainerView.hidden = YES;
        if (!self.isSettingsOpen) {
            self.dimmingOverlayView.hidden = YES;
        }
        if (onComplete) onComplete();
    }];
}

- (void)openSidebarTapped {
    [self toggleSidebar];
}

- (void)newChatTapped {
    [self closeSidebarWithCompletion:^{
        ChatSession *newSession = [[ChatHistoryManager sharedManager] createNewSession];
        [self loadSession:newSession];
    }];
}

#pragma mark - ChatHistorySidebarDelegate

- (void)sidebarDidSelectSession:(ChatSession *)session {
    [self loadSession:session];
    [self closeSidebar];
}

- (void)sidebarDidDeleteSession:(ChatSession *)newActiveSession {
    // Sohbet silindiğinde arka plandaki konuşmayı güncelle ama sidebar'ı açık tut
    [self loadSession:newActiveSession];
}

- (void)sidebarDidRequestNewChat {
    [self closeSidebarWithCompletion:^{
        [self newChatTapped];
    }];
}

- (void)loadSession:(ChatSession *)session {
    [self.messages removeAllObjects];
    if (session.messages.count > 0) {
        [self.messages addObjectsFromArray:session.messages];
    } else {
        [self addWelcomeMessageIfNeeded];
    }
    self.title = session.title ?: @"ChatGPT";
    [self.tableView reloadData];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self scrollToBottomAnimated:NO];
    });
}

- (void)openSettingsAnimated:(BOOL)animated {
    [self.view endEditing:YES];
    if (self.isSidebarOpen) {
        [self closeSidebar];
    }
    [self ensureSettingsViews];
    [self.settingsVC.tableView reloadData];

    UIWindow *targetWindow = self.view.window ?: [UIApplication sharedApplication].keyWindow;
    CGRect winBounds = targetWindow.bounds;
    CGFloat setWidth = [self settingsWidth];

    self.dimmingOverlayView.frame = winBounds;
    self.settingsContainerView.frame = CGRectMake(winBounds.size.width, 0, setWidth, winBounds.size.height);
    self.dimmingOverlayView.hidden = NO;
    self.settingsContainerView.hidden = NO;

    void (^animations)(void) = ^{
        self.dimmingOverlayView.alpha = 1.0;
        self.settingsContainerView.frame = CGRectMake(winBounds.size.width - setWidth, 0, setWidth, winBounds.size.height);
    };

    void (^completion)(BOOL) = ^(BOOL finished) {
        self.isSettingsOpen = YES;
    };

    if (animated) {
        [UIView animateWithDuration:0.25 delay:0 options:(7 << 16) | UIViewAnimationOptionBeginFromCurrentState animations:animations completion:completion];
    } else {
        animations();
        completion(YES);
    }
}

- (void)closeSettings {
    [self closeSettingsWithCompletion:nil];
}

- (void)closeSettingsWithCompletion:(void (^)(void))onComplete {
    if (!self.isSettingsOpen && self.settingsContainerView.hidden) {
        if (onComplete) onComplete();
        return;
    }

    UIWindow *targetWindow = self.view.window ?: [UIApplication sharedApplication].keyWindow;
    CGRect winBounds = targetWindow.bounds;
    CGFloat setWidth = [self settingsWidth];

    [UIView animateWithDuration:0.22 delay:0 options:(7 << 16) | UIViewAnimationOptionBeginFromCurrentState animations:^{
        if (!self.isSidebarOpen) {
            self.dimmingOverlayView.alpha = 0.0;
        }
        self.settingsContainerView.frame = CGRectMake(winBounds.size.width, 0, setWidth, winBounds.size.height);
    } completion:^(BOOL finished) {
        self.isSettingsOpen = NO;
        self.settingsContainerView.hidden = YES;
        if (!self.isSidebarOpen) {
            self.dimmingOverlayView.hidden = YES;
        }
        if (onComplete) onComplete();
    }];
}

- (void)openSettingsTapped {
    if (self.isSettingsOpen) {
        [self closeSettings];
    } else {
        [self openSettingsAnimated:YES];
    }
}

- (void)settingsDidUpdate {
    [self updateTitleWithModel];
    self.isWebSearchActive = [OpenAIClient sharedClient].enableWebSearch;
    [self updateWebSearchButtonAppearance];
}

- (void)settingsDidRequestClose {
    [self closeSettings];
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

    // Web Arama Butonu (Temiz Vektör İkonu)
    _webSearchButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _webSearchButton.frame = CGRectMake(8, 7, 36, 36);
    _webSearchButton.layer.cornerRadius = 18.0;
    _webSearchButton.layer.masksToBounds = YES;
    UIImage *globeImg = [[UIImage imageNamed:@"GlobeIcon"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    if (globeImg) {
        [_webSearchButton setImage:globeImg forState:UIControlStateNormal];
        _webSearchButton.tintColor = [UIColor darkGrayColor];
    } else {
        [_webSearchButton setTitle:@"Web" forState:UIControlStateNormal];
        _webSearchButton.titleLabel.font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:13.0];
    }
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
    [OpenAIClient sharedClient].enableWebSearch = self.isWebSearchActive;

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
        self.webSearchButton.tintColor = [UIColor colorWithRed:16.0/255.0 green:163.0/255.0 blue:127.0/255.0 alpha:1.0];
    } else {
        self.webSearchButton.backgroundColor = [UIColor colorWithWhite:0.92 alpha:1.0];
        self.webSearchButton.layer.borderWidth = 0.5;
        self.webSearchButton.layer.borderColor = [UIColor colorWithWhite:0.8 alpha:1.0].CGColor;
        self.webSearchButton.tintColor = [UIColor darkGrayColor];
    }
}

- (void)saveCurrentSessionState {
    ChatSession *active = [ChatHistoryManager sharedManager].activeSession;
    if (active) {
        [active.messages removeAllObjects];
        for (ChatMessage *m in self.messages) {
            if ([m.text containsString:@"iPad Mini 1 (iOS 8.4)"]) continue;
            [active.messages addObject:m];
        }
        [[ChatHistoryManager sharedManager] saveSessions];
    }
}

- (void)addWelcomeMessageIfNeeded {
    NSString *welcome = LocalizedString(@"welcome_msg");
    [self.messages addObject:[ChatMessage messageWithText:welcome sender:ChatMessageSenderAssistant]];
    [self.tableView reloadData];
}

- (void)clearChatTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Sohbeti Temizle"
                                                                   message:@"Mevcut konuşmanın mesajları silinsin mi?"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Temizle" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self.messages removeAllObjects];
        ChatSession *active = [ChatHistoryManager sharedManager].activeSession;
        if (active) {
            [active.messages removeAllObjects];
            active.title = @"Yeni Sohbet";
            self.title = @"Yeni Sohbet";
            [[ChatHistoryManager sharedManager] saveSessions];
        }
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

    [[ChatHistoryManager sharedManager] updateActiveSessionWithUserMessage:rawText];
    self.title = [ChatHistoryManager sharedManager].activeSession.title ?: @"ChatGPT";
    [self saveCurrentSessionState];

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

        [self saveCurrentSessionState];
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
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:LocalizedString(@"auth_prompt_title")
                                                                   message:LocalizedString(@"auth_prompt_msg")
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:LocalizedString(@"auth_prompt_login") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        ChatGPTLoginModalViewController *modal = [[ChatGPTLoginModalViewController alloc] init];
        modal.delegate = self;
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:modal];
        nav.modalPresentationStyle = UIModalPresentationFormSheet;
        [self presentViewController:nav animated:YES completion:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:LocalizedString(@"auth_prompt_settings") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self openSettingsTapped];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:LocalizedString(@"cancel_button") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)chatGPTLoginDidComplete {
    [self updateTitleWithModel];
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
