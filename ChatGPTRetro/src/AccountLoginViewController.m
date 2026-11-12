#import "AccountLoginViewController.h"
#import "OpenAIClient.h"
#import "ChatGPTLoginModalViewController.h"
#import "LocalizationManager.h"

@interface AccountLoginViewController () <ChatGPTLoginModalDelegate, UITextFieldDelegate>

@property (nonatomic, strong) UITextField *apiKeyField;

@end

@implementation AccountLoginViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleGrouped];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = LocalizedString(@"section_account_login");

    _apiKeyField = [[UITextField alloc] initWithFrame:CGRectZero];
    _apiKeyField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _apiKeyField.placeholder = @"sk-...";
    _apiKeyField.text = [OpenAIClient sharedClient].apiKey;
    _apiKeyField.font = [UIFont fontWithName:@"HelveticaNeue" size:14.0];
    _apiKeyField.secureTextEntry = YES;
    _apiKeyField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _apiKeyField.autocorrectionType = UITextAutocorrectionTypeNo;
    _apiKeyField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _apiKeyField.delegate = self;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(authStateDidChange:)
                                                 name:kChatGPTAuthStateDidChangeNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.view endEditing:YES];
    NSString *key = self.apiKeyField.text ?: @"";
    [[OpenAIClient sharedClient] saveApiKey:key];
    if ([self.delegate respondsToSelector:@selector(accountLoginStateDidChange)]) {
        [self.delegate accountLoginStateDidChange];
    }
}

- (void)authStateDidChange:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
        if ([self.delegate respondsToSelector:@selector(accountLoginStateDidChange)]) {
            [self.delegate accountLoginStateDidChange];
        }
    });
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2; // Section 0: SIWC (ChatGPT Hesabı), Section 1: API Key
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        if ([[OpenAIClient sharedClient] isChatGPTAccountLinked]) {
            return 4; // Bağlandı, Durum, Kullanımı Yönet, Bağlantıyı Kes
        }
        return 2; // ChatGPT ile Devam Et (QR), Linki Manuel Yapıştır
    }
    return 1; // API Key
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *cellId = [NSString stringWithFormat:@"LoginCell_%ld_%ld_%d", (long)indexPath.section, (long)indexPath.row, [[OpenAIClient sharedClient] isChatGPTAccountLinked]];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellId];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.textLabel.text = nil;
    cell.textLabel.textColor = [UIColor blackColor];
    cell.textLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:16.0];
    cell.detailTextLabel.text = nil;
    cell.detailTextLabel.textColor = [UIColor grayColor];

    for (UIView *sub in cell.contentView.subviews) {
        if (sub == self.apiKeyField) {
            [sub removeFromSuperview];
        }
    }

    UIColor *openAIGreen = [UIColor colorWithRed:16.0/255.0 green:163.0/255.0 blue:127.0/255.0 alpha:1.0];
    CGFloat w = cell.contentView.bounds.size.width > 0 ? cell.contentView.bounds.size.width : tableView.bounds.size.width;

    if (indexPath.section == 0) {
        if ([[OpenAIClient sharedClient] isChatGPTAccountLinked]) {
            if (indexPath.row == 0) {
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                NSString *email = [OpenAIClient sharedClient].userEmail;
                cell.textLabel.text = (email && email.length > 0) ? email : @"Hesap";
                cell.detailTextLabel.text = LocalizedString(@"siwc_connected");
                cell.detailTextLabel.textColor = openAIGreen;
            } else if (indexPath.row == 1) {
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                cell.textLabel.text = LocalizedString(@"siwc_status");
                cell.detailTextLabel.text = [OpenAIClient sharedClient].isPlanSharingEnabled
                    ? LocalizedString(@"siwc_enabled")
                    : LocalizedString(@"siwc_identity_only");
            } else if (indexPath.row == 2) {
                cell.textLabel.text = LocalizedString(@"siwc_manage");
                cell.textLabel.textColor = openAIGreen;
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            } else {
                cell.textLabel.text = LocalizedString(@"siwc_disconnect");
                cell.textLabel.textColor = [UIColor redColor];
            }
        } else {
            if (indexPath.row == 0) {
                cell.textLabel.text = LocalizedString(@"siwc_login_btn");
                cell.textLabel.textColor = openAIGreen;
                cell.textLabel.font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:16.0];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            } else {
                cell.textLabel.text = LocalizedString(@"siwc_manual_btn");
                cell.textLabel.textColor = [UIColor darkGrayColor];
                cell.textLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:14.0];
            }
        }
    } else {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = LocalizedString(@"apikey_label");
        CGFloat labelW = 115.0;
        self.apiKeyField.frame = CGRectMake(labelW, 8, w - labelW - 20, 28);
        self.apiKeyField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [cell.contentView addSubview:self.apiKeyField];
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0) {
        if ([[OpenAIClient sharedClient] isChatGPTAccountLinked]) {
            if (indexPath.row == 2) {
                NSURL *u = [NSURL URLWithString:@"https://chatgpt.com/settings/usage"];
                if (u) [[UIApplication sharedApplication] openURL:u];
            } else if (indexPath.row == 3) {
                [self disconnectAccountAction];
            }
        } else {
            if (indexPath.row == 0) {
                [self signInWithChatGPTAction];
            } else if (indexPath.row == 1) {
                [self pasteManualCallbackAction];
            }
        }
    }
}

- (void)signInWithChatGPTAction {
    [self.view endEditing:YES];
    ChatGPTLoginModalViewController *modal = [[ChatGPTLoginModalViewController alloc] init];
    modal.delegate = self;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:modal];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)chatGPTLoginDidComplete {
    [self.tableView reloadData];
    if ([self.delegate respondsToSelector:@selector(accountLoginStateDidChange)]) {
        [self.delegate accountLoginStateDidChange];
    }
}

- (void)pasteManualCallbackAction {
    UIAlertController *prompt = [UIAlertController alertControllerWithTitle:LocalizedString(@"siwc_manual_btn")
                                                                    message:@"Tarayıcıdaki tam adresi yapıştırın:"
                                                             preferredStyle:UIAlertControllerStyleAlert];
    [prompt addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"http://127.0.0.1:8787/auth/callback?code=...";
    }];
    [prompt addAction:[UIAlertAction actionWithTitle:LocalizedString(@"cancel_button") style:UIAlertActionStyleCancel handler:nil]];
    [prompt addAction:[UIAlertAction actionWithTitle:LocalizedString(@"ok_button") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *text = prompt.textFields.firstObject.text ?: @"";
        if (text.length > 0) {
            [[OpenAIClient sharedClient] handleIncomingCallbackURLString:text completion:^(BOOL success, NSError *error) {
                [self.tableView reloadData];
                if ([self.delegate respondsToSelector:@selector(accountLoginStateDidChange)]) {
                    [self.delegate accountLoginStateDidChange];
                }
            }];
        }
    }]];
    [self presentViewController:prompt animated:YES completion:nil];
}

- (void)disconnectAccountAction {
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:LocalizedString(@"siwc_disconnect")
                                                                     message:LocalizedString(@"siwc_disconnect")
                                                              preferredStyle:UIAlertControllerStyleActionSheet];
    [confirm addAction:[UIAlertAction actionWithTitle:LocalizedString(@"siwc_disconnect") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [[OpenAIClient sharedClient] disconnectChatGPTAccountWithCompletion:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.tableView reloadData];
                if ([self.delegate respondsToSelector:@selector(accountLoginStateDidChange)]) {
                    [self.delegate accountLoginStateDidChange];
                }
            });
        }];
    }]];
    [confirm addAction:[UIAlertAction actionWithTitle:LocalizedString(@"cancel_button") style:UIAlertActionStyleCancel handler:nil]];
    confirm.popoverPresentationController.sourceView = self.view;
    confirm.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 1, 1);
    [self presentViewController:confirm animated:YES completion:nil];
}

@end
