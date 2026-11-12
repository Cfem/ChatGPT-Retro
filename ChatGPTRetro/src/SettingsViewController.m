#import "SettingsViewController.h"
#import "OpenAIClient.h"
#import "ChatGPTLoginModalViewController.h"
#import "LocalizationManager.h"

@interface SettingsViewController () <ChatGPTLoginModalDelegate>

@property (nonatomic, strong) UITextField *apiKeyField;
@property (nonatomic, strong) UITextField *modelField;
@property (nonatomic, strong) UITextView *systemInstructionTextView;
@property (nonatomic, strong) UISegmentedControl *languageSegment;
@property (nonatomic, assign) BOOL isFetchingModels;
@property (nonatomic, assign) BOOL isSigningIn;

@end

@implementation SettingsViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleGrouped];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = LocalizedString(@"settings_title");

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:LocalizedString(@"close_button")
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(closeButtonTapped)];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:LocalizedString(@"save_button")
                                                                               style:UIBarButtonItemStyleDone
                                                                              target:self
                                                                              action:@selector(saveSettingsAction)];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(authStateDidChange:)
                                                 name:kChatGPTAuthStateDidChangeNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(languageDidChange:)
                                                 name:kLanguageDidChangeNotification
                                               object:nil];

    [self setupFields];
}

- (void)languageDidChange:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.title = LocalizedString(@"settings_title");
        self.navigationItem.leftBarButtonItem.title = LocalizedString(@"close_button");
        self.navigationItem.rightBarButtonItem.title = LocalizedString(@"save_button");
        [self.tableView reloadData];
    });
}

- (void)authStateDidChange:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.isSigningIn = NO;
        [self.tableView reloadData];
        if ([self.delegate respondsToSelector:@selector(settingsDidUpdate)]) {
            [self.delegate settingsDidUpdate];
        }
    });
}

- (void)setupFields {
    // 1. Language Segmented Control
    _languageSegment = [[UISegmentedControl alloc] initWithItems:@[LocalizedString(@"lang_auto"), LocalizedString(@"lang_tr"), LocalizedString(@"lang_en")]];
    _languageSegment.selectedSegmentIndex = [LocalizationManager sharedManager].selectedLanguage;
    _languageSegment.tintColor = [UIColor colorWithRed:16.0/255.0 green:163.0/255.0 blue:127.0/255.0 alpha:1.0];
    [_languageSegment addTarget:self action:@selector(languageSegmentChanged:) forControlEvents:UIControlEventValueChanged];

    // 2. API Key
    _apiKeyField = [[UITextField alloc] initWithFrame:CGRectZero];
    _apiKeyField.placeholder = @"sk-... (API Key)";
    _apiKeyField.text = [OpenAIClient sharedClient].apiKey;
    _apiKeyField.font = [UIFont fontWithName:@"HelveticaNeue" size:14.0];
    _apiKeyField.secureTextEntry = YES;
    _apiKeyField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _apiKeyField.autocorrectionType = UITextAutocorrectionTypeNo;
    _apiKeyField.clearButtonMode = UITextFieldViewModeWhileEditing;

    // 3. Model
    _modelField = [[UITextField alloc] initWithFrame:CGRectZero];
    _modelField.placeholder = @"gpt-4o-mini";
    _modelField.text = [OpenAIClient sharedClient].selectedModel;
    _modelField.font = [UIFont fontWithName:@"HelveticaNeue" size:14.0];
    _modelField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _modelField.autocorrectionType = UITextAutocorrectionTypeNo;
    _modelField.clearButtonMode = UITextFieldViewModeWhileEditing;

    // 4. Custom System Instructions
    _systemInstructionTextView = [[UITextView alloc] initWithFrame:CGRectZero];
    _systemInstructionTextView.font = [UIFont fontWithName:@"HelveticaNeue" size:14.0];
    _systemInstructionTextView.backgroundColor = [UIColor clearColor];
    _systemInstructionTextView.text = [OpenAIClient sharedClient].customSystemInstruction;
}

- (void)languageSegmentChanged:(UISegmentedControl *)sender {
    [LocalizationManager sharedManager].selectedLanguage = sender.selectedSegmentIndex;
}

- (void)closeButtonTapped {
    [self.view endEditing:YES];
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Actions

- (void)saveSettingsAction {
    [self.view endEditing:YES];

    NSString *key = self.apiKeyField.text ?: @"";
    NSString *model = self.modelField.text ?: @"gpt-4o-mini";
    NSString *instruction = self.systemInstructionTextView.text ?: @"";

    [[OpenAIClient sharedClient] saveApiKey:key];
    [[OpenAIClient sharedClient] saveSelectedModel:model];
    [[OpenAIClient sharedClient] saveCustomSystemInstruction:instruction];

    if ([self.delegate respondsToSelector:@selector(settingsDidUpdate)]) {
        [self.delegate settingsDidUpdate];
    }

    NSString *msg = [NSString stringWithFormat:@"%@\n\n• Model: %@", LocalizedString(@"saved_alert_msg"), model];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:LocalizedString(@"saved_alert_title") message:msg preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:LocalizedString(@"ok_button") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
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
    if ([self.delegate respondsToSelector:@selector(settingsDidUpdate)]) {
        [self.delegate settingsDidUpdate];
    }
    NSString *email = [OpenAIClient sharedClient].userEmail ?: @"ChatGPT";
    [self showAlertWithTitle:LocalizedString(@"saved_alert_title")
                     message:[NSString stringWithFormat:@"%@: %@", LocalizedString(@"siwc_enabled"), email]];
}

- (void)pasteManualCallbackAction {
    [self.view endEditing:YES];
    UIAlertController *prompt = [UIAlertController alertControllerWithTitle:LocalizedString(@"siwc_manual_btn")
                                                                    message:@"http://127.0.0.1:8787/auth/callback?code=..."
                                                             preferredStyle:UIAlertControllerStyleAlert];
    [prompt addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"http://127.0.0.1:8787/auth/callback?code=...";
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [prompt addAction:[UIAlertAction actionWithTitle:LocalizedString(@"cancel_button") style:UIAlertActionStyleCancel handler:nil]];
    [prompt addAction:[UIAlertAction actionWithTitle:LocalizedString(@"ok_button") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *text = prompt.textFields.firstObject.text ?: @"";
        if (text.length > 0) {
            [[OpenAIClient sharedClient] handleIncomingCallbackURLString:text completion:^(BOOL success, NSError *error) {
                [self.tableView reloadData];
                if (success) {
                    if ([self.delegate respondsToSelector:@selector(settingsDidUpdate)]) {
                        [self.delegate settingsDidUpdate];
                    }
                    [self showAlertWithTitle:LocalizedString(@"saved_alert_title") message:LocalizedString(@"siwc_enabled")];
                } else {
                    [self showAlertWithTitle:@"Error" message:error.localizedDescription];
                }
            }];
        }
    }]];
    [self presentViewController:prompt animated:YES completion:nil];
}

- (void)manageUsageAction {
    NSURL *usageUrl = [NSURL URLWithString:@"https://chatgpt.com/settings/usage"];
    if (usageUrl) {
        [[UIApplication sharedApplication] openURL:usageUrl];
    }
}

- (void)disconnectAccountAction {
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:LocalizedString(@"siwc_disconnect")
                                                                     message:LocalizedString(@"siwc_disconnect")
                                                              preferredStyle:UIAlertControllerStyleActionSheet];
    [confirm addAction:[UIAlertAction actionWithTitle:LocalizedString(@"siwc_disconnect") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [[OpenAIClient sharedClient] disconnectChatGPTAccountWithCompletion:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.tableView reloadData];
                if ([self.delegate respondsToSelector:@selector(settingsDidUpdate)]) {
                    [self.delegate settingsDidUpdate];
                }
            });
        }];
    }]];
    [confirm addAction:[UIAlertAction actionWithTitle:LocalizedString(@"cancel_button") style:UIAlertActionStyleCancel handler:nil]];
    confirm.popoverPresentationController.sourceView = self.view;
    confirm.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 1, 1);
    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)refreshModelsAction {
    [self.view endEditing:YES];
    if (![[OpenAIClient sharedClient] isAuthenticated]) {
        [self showAlertWithTitle:LocalizedString(@"auth_prompt_title")
                         message:LocalizedString(@"auth_prompt_msg")];
        return;
    }

    self.isFetchingModels = YES;
    [self.tableView reloadData];

    [[OpenAIClient sharedClient] fetchAvailableModelsWithCompletion:^(NSArray *models, NSError *error) {
        self.isFetchingModels = NO;
        if (error) {
            [self showAlertWithTitle:@"Error" message:error.localizedDescription];
            [self.tableView reloadData];
            return;
        }

        if (models.count == 0) {
            [self showAlertWithTitle:@"Error" message:@"No models found."];
            [self.tableView reloadData];
            return;
        }

        UIAlertController *picker = [UIAlertController alertControllerWithTitle:LocalizedString(@"section_model")
                                                                        message:nil
                                                                 preferredStyle:UIAlertControllerStyleActionSheet];

        for (NSString *m in models) {
            [picker addAction:[UIAlertAction actionWithTitle:m style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                self.modelField.text = m;
                [[OpenAIClient sharedClient] saveSelectedModel:m];
                if ([self.delegate respondsToSelector:@selector(settingsDidUpdate)]) {
                    [self.delegate settingsDidUpdate];
                }
            }]];
        }

        [picker addAction:[UIAlertAction actionWithTitle:LocalizedString(@"cancel_button") style:UIAlertActionStyleCancel handler:nil]];
        picker.popoverPresentationController.sourceView = self.view;
        picker.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, 200, 1, 1);
        [self presentViewController:picker animated:YES completion:nil];
        [self.tableView reloadData];
    }];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)msg {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:LocalizedString(@"ok_button") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 6;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1; // Language selection
    if (section == 1) {
        // Sign in with ChatGPT (SIWC)
        if ([[OpenAIClient sharedClient] isChatGPTAccountLinked]) {
            return 4; // Connected, Status, Manage, Disconnect
        }
        return 2; // Continue with ChatGPT, Paste URL
    }
    if (section == 2) return 2; // Model & Refresh Models
    if (section == 3) return 1; // Custom System Instructions
    if (section == 4) return 1; // API Key
    return 2; // System Info
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return LocalizedString(@"section_language");
    if (section == 1) return LocalizedString(@"section_siwc");
    if (section == 2) return LocalizedString(@"section_model");
    if (section == 3) return LocalizedString(@"section_instructions");
    if (section == 4) return LocalizedString(@"section_apikey");
    return LocalizedString(@"section_system");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 3) return LocalizedString(@"instructions_footer");
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 3) {
        return 96.0; // Text view
    }
    return 44.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *cellId = [NSString stringWithFormat:@"Cell_%ld_%ld_%d", (long)indexPath.section, (long)indexPath.row, [[OpenAIClient sharedClient] isChatGPTAccountLinked]];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellId];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.textLabel.textColor = [UIColor blackColor];
    cell.textLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:16.0];
    cell.detailTextLabel.text = nil;
    cell.detailTextLabel.textColor = [UIColor grayColor];

    CGFloat w = tableView.bounds.size.width;
    UIColor *openAIGreen = [UIColor colorWithRed:16.0/255.0 green:163.0/255.0 blue:127.0/255.0 alpha:1.0];

    if (indexPath.section == 0) {
        // Dil Seçici Segment
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        self.languageSegment.frame = CGRectMake(14, 6, w - 28, 32);
        [cell.contentView addSubview:self.languageSegment];
    } else if (indexPath.section == 1) {
        if ([[OpenAIClient sharedClient] isChatGPTAccountLinked]) {
            if (indexPath.row == 0) {
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                NSString *email = [OpenAIClient sharedClient].userEmail;
                cell.textLabel.text = (email && email.length > 0) ? email : @"Connection 1";
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
    } else if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.textLabel.text = @"Model";
            self.modelField.frame = CGRectMake(110, 8, w - 126, 28);
            [cell.contentView addSubview:self.modelField];
        } else {
            if (self.isFetchingModels) {
                cell.textLabel.text = LocalizedString(@"fetching_models");
                cell.textLabel.textColor = [UIColor grayColor];
                UIActivityIndicatorView *spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
                [spin startAnimating];
                cell.accessoryView = spin;
            } else {
                cell.textLabel.text = LocalizedString(@"fetch_models_btn");
                cell.textLabel.textColor = openAIGreen;
            }
        }
    } else if (indexPath.section == 3) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        self.systemInstructionTextView.frame = CGRectMake(16, 6, w - 32, 84);
        [cell.contentView addSubview:self.systemInstructionTextView];
    } else if (indexPath.section == 4) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = @"API Key";
        self.apiKeyField.frame = CGRectMake(110, 8, w - 126, 28);
        [cell.contentView addSubview:self.apiKeyField];
    } else {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Host ID";
            cell.detailTextLabel.text = [OpenAIClient sharedClient].hostId;
            cell.detailTextLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:11.0];
        } else {
            cell.textLabel.text = @"Version";
            cell.detailTextLabel.text = @"v1.5 (Bilingual & Side Drawer)";
        }
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 1) {
        if ([[OpenAIClient sharedClient] isChatGPTAccountLinked]) {
            if (indexPath.row == 2) {
                [self manageUsageAction];
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
    } else if (indexPath.section == 2 && indexPath.row == 1) {
        if (!self.isFetchingModels) {
            [self refreshModelsAction];
        }
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
