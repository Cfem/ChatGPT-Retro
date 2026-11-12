#import "SettingsViewController.h"
#import "OpenAIClient.h"
#import "ChatGPTLoginModalViewController.h"

@interface SettingsViewController () <ChatGPTLoginModalDelegate>

@property (nonatomic, strong) UITextField *apiKeyField;
@property (nonatomic, strong) UITextField *modelField;
@property (nonatomic, strong) UITextView *systemInstructionTextView;
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
    self.title = @"Ayarlar";

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Kapat"
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(closeButtonTapped)];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Kaydet"
                                                                              style:UIBarButtonItemStyleDone
                                                                             target:self
                                                                             action:@selector(saveSettingsAction)];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(authStateDidChange:)
                                                 name:kChatGPTAuthStateDidChangeNotification
                                               object:nil];

    [self setupFields];
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
    // 1. API Key
    _apiKeyField = [[UITextField alloc] initWithFrame:CGRectZero];
    _apiKeyField.placeholder = @"sk-... (İsteğe Bağlı API Anahtarı)";
    _apiKeyField.text = [OpenAIClient sharedClient].apiKey;
    _apiKeyField.font = [UIFont fontWithName:@"HelveticaNeue" size:14.0];
    _apiKeyField.secureTextEntry = YES;
    _apiKeyField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _apiKeyField.autocorrectionType = UITextAutocorrectionTypeNo;
    _apiKeyField.clearButtonMode = UITextFieldViewModeWhileEditing;

    // 2. Model
    _modelField = [[UITextField alloc] initWithFrame:CGRectZero];
    _modelField.placeholder = @"gpt-4o-mini";
    _modelField.text = [OpenAIClient sharedClient].selectedModel;
    _modelField.font = [UIFont fontWithName:@"HelveticaNeue" size:14.0];
    _modelField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _modelField.autocorrectionType = UITextAutocorrectionTypeNo;
    _modelField.clearButtonMode = UITextFieldViewModeWhileEditing;

    // 3. Özel Sistem Talimatı (Bellek / Custom Instructions)
    _systemInstructionTextView = [[UITextView alloc] initWithFrame:CGRectZero];
    _systemInstructionTextView.font = [UIFont fontWithName:@"HelveticaNeue" size:14.0];
    _systemInstructionTextView.backgroundColor = [UIColor clearColor];
    _systemInstructionTextView.text = [OpenAIClient sharedClient].customSystemInstruction;
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

    NSString *authMode = [[OpenAIClient sharedClient] isChatGPTAccountLinked]
        ? [NSString stringWithFormat:@"ChatGPT Planı (%@)", [OpenAIClient sharedClient].userEmail ?: @"Bağlı"]
        : [NSString stringWithFormat:@"API Anahtarı (%lu karakter)", (unsigned long)key.length];

    NSString *msg = [NSString stringWithFormat:@"Ayarlar başarıyla kaydedildi!\n\n• Kimlik: %@\n• Seçili Model: %@",
                     authMode, model];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Kaydedildi" message:msg preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Tamam" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
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
    NSString *email = [OpenAIClient sharedClient].userEmail ?: @"ChatGPT Hesabı";
    [self showAlertWithTitle:@"Bağlantı Başarılı!"
                     message:[NSString stringWithFormat:@"%@ hesabınızla giriş yapıldı. ChatGPT Plus/Pro plan kullanımınız aktif!", email]];
}

- (void)pasteManualCallbackAction {
    [self.view endEditing:YES];
    UIAlertController *prompt = [UIAlertController alertControllerWithTitle:@"Doğrulama Linkini Yapıştır"
                                                                    message:@"Eğer Safari yönlendirmesi otomatik dönmediyse veya başka cihazda giriş yaptıysanız adres çubuğundaki (http://127.0.0.1:8787/auth/callback?...) linkini buraya yapıştırın:"
                                                             preferredStyle:UIAlertControllerStyleAlert];
    [prompt addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"http://127.0.0.1:8787/auth/callback?code=...";
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [prompt addAction:[UIAlertAction actionWithTitle:@"Vazgeç" style:UIAlertActionStyleCancel handler:nil]];
    [prompt addAction:[UIAlertAction actionWithTitle:@"Doğrula" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *text = prompt.textFields.firstObject.text ?: @"";
        if (text.length > 0) {
            [[OpenAIClient sharedClient] handleIncomingCallbackURLString:text completion:^(BOOL success, NSError *error) {
                [self.tableView reloadData];
                if (success) {
                    if ([self.delegate respondsToSelector:@selector(settingsDidUpdate)]) {
                        [self.delegate settingsDidUpdate];
                    }
                    [self showAlertWithTitle:@"Bağlandı!" message:@"ChatGPT hesabınız başarıyla doğrulandı."];
                } else {
                    [self showAlertWithTitle:@"Hata" message:error.localizedDescription];
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
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Bağlantıyı Kes"
                                                                     message:@"ChatGPT hesabı bağlantınızı kaldırmak istediğinize emin misiniz?"
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Vazgeç" style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Çıkış Yap" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [[OpenAIClient sharedClient] disconnectChatGPTAccountWithCompletion:^{
            [self.tableView reloadData];
            if ([self.delegate respondsToSelector:@selector(settingsDidUpdate)]) {
                [self.delegate settingsDidUpdate];
            }
        }];
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)refreshModelsAction {
    [self.view endEditing:YES];

    NSString *currentKey = self.apiKeyField.text ?: @"";
    if (currentKey.length > 0) {
        [[OpenAIClient sharedClient] saveApiKey:currentKey];
    }

    if (![[OpenAIClient sharedClient] isAuthenticated]) {
        [self showAlertWithTitle:@"Giriş Gerekli" 
                         message:@"Modelleri çekebilmek için lütfen önce 'Continue with ChatGPT' ile giriş yapın veya bir OpenAI API Anahtarı girin."];
        return;
    }

    self.isFetchingModels = YES;
    [self.tableView reloadData];

    [[OpenAIClient sharedClient] fetchAvailableModelsWithCompletion:^(NSArray *models, NSError *error) {
        self.isFetchingModels = NO;
        if (error) {
            [self showAlertWithTitle:@"Hata" message:error.localizedDescription];
            [self.tableView reloadData];
            return;
        }

        if (models.count == 0) {
            [self showAlertWithTitle:@"Model Bulunamadı" message:@"OpenAI model listesi boş döndü."];
            [self.tableView reloadData];
            return;
        }

        UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"Model Seçin"
                                                                        message:@"Kullanmak istediğiniz modeli seçin:"
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

        [picker addAction:[UIAlertAction actionWithTitle:@"İptal" style:UIAlertActionStyleCancel handler:nil]];
        picker.popoverPresentationController.sourceView = self.view;
        picker.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, 200, 1, 1);
        [self presentViewController:picker animated:YES completion:nil];
        [self.tableView reloadData];
    }];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)msg {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Tamam" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 5;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        // Section 0: Sign in with ChatGPT (SIWC)
        if ([[OpenAIClient sharedClient] isChatGPTAccountLinked]) {
            return 4; // Hesap (Connected), Plan Durumu, Manage Usage, Disconnect
        }
        return 2; // Continue with ChatGPT (Safari/QR), Manuel Link Yapıştır (Yedek)
    }
    if (section == 1) return 2; // Model & Refresh Models
    if (section == 2) return 1; // Custom System Instruction (Bellek / Özel Talimat)
    if (section == 3) return 1; // API Key
    return 2; // Sistem Bilgisi
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"SIGN IN WITH CHATGPT (PLAN KULLANIMI)";
    if (section == 1) return @"CHATGPT MODELİ";
    if (section == 2) return @"ÖZEL SİSTEM TALİMATI & BELLEK (CUSTOM INSTRUCTIONS)";
    if (section == 3) return @"OPENAI API ANAHTARI (OPSİYONEL)";
    return @"SİSTEM BİLGİSİ";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        if ([[OpenAIClient sharedClient] isChatGPTAccountLinked]) {
            return [NSString stringWithFormat:@"ChatGPT planınız bağlı (Client ID: %@). İstekleriniz doğrudan ChatGPT Plus/Pro planınız üzerinden tamamlanır.", [OpenAIClient sharedClient].issuedClientId];
        }
        return @"ChatGPT Plus veya Pro hesabınızla API anahtarına ihtiyaç duymadan QR / Safari üzerinden giriş yapabilirsiniz.";
    }
    if (section == 1) return @"Hesabınızda kullanılabilir modelleri görmek için 'Modelleri Canlı Güncelle' butonuna dokunun.";
    if (section == 2) return @"ChatGPT'nin sizi tanıması ve bağlamınızı hiç unutmamasını istediğiniz bilgileri (adınız, mesleğiniz, cevap tarzı, kurallar vb.) buraya yazın. Tüm sohbetlerde otomatik uygulanır.";
    if (section == 3) return @"ChatGPT hesabı yerine doğrudan Platform API anahtarıyla (sk-...) kullanmak isterseniz buraya girebilirsiniz.";
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 2) {
        return 96.0; // Text view for custom instructions
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
        if ([[OpenAIClient sharedClient] isChatGPTAccountLinked]) {
            if (indexPath.row == 0) {
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                NSString *email = [OpenAIClient sharedClient].userEmail;
                cell.textLabel.text = (email && email.length > 0) ? email : @"Connection 1";
                cell.detailTextLabel.text = @"🟢 Connected";
                cell.detailTextLabel.textColor = openAIGreen;
            } else if (indexPath.row == 1) {
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                cell.textLabel.text = @"Durum";
                cell.detailTextLabel.text = [OpenAIClient sharedClient].isPlanSharingEnabled
                    ? @"ChatGPT plan usage is enabled"
                    : @"Identity only";
            } else if (indexPath.row == 2) {
                cell.textLabel.text = @"📊 Manage usage (chatgpt.com/settings/usage)";
                cell.textLabel.textColor = openAIGreen;
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            } else {
                cell.textLabel.text = @"🔴 Bağlantıyı Kes (Disconnect)";
                cell.textLabel.textColor = [UIColor redColor];
            }
        } else {
            if (indexPath.row == 0) {
                cell.textLabel.text = @"🟢 Continue with ChatGPT (Safari ile Giriş)";
                cell.textLabel.textColor = openAIGreen;
                cell.textLabel.font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:16.0];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            } else {
                cell.textLabel.text = @"🔗 Doğrulama Linkini Manuel Yapıştır";
                cell.textLabel.textColor = [UIColor darkGrayColor];
                cell.textLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:14.0];
            }
        }
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.textLabel.text = @"Model";
            self.modelField.frame = CGRectMake(110, 8, w - 126, 28);
            [cell.contentView addSubview:self.modelField];
        } else {
            if (self.isFetchingModels) {
                cell.textLabel.text = @"Modeller taranıyor...";
                cell.textLabel.textColor = [UIColor grayColor];
                UIActivityIndicatorView *spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
                [spin startAnimating];
                cell.accessoryView = spin;
            } else {
                cell.textLabel.text = @"🔄 Modelleri Canlı Güncelle (Fetch Models)";
                cell.textLabel.textColor = openAIGreen;
            }
        }
    } else if (indexPath.section == 2) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        self.systemInstructionTextView.frame = CGRectMake(16, 6, w - 32, 84);
        [cell.contentView addSubview:self.systemInstructionTextView];
    } else if (indexPath.section == 3) {
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
            cell.textLabel.text = @"Sürüm";
            cell.detailTextLabel.text = @"v1.4 (Custom Instructions & Memory)";
        }
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0) {
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
    } else if (indexPath.section == 1 && indexPath.row == 1) {
        if (!self.isFetchingModels) {
            [self refreshModelsAction];
        }
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
